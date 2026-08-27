-- KaataGo — menghapus resto tanpa membuang datanya.
--
-- Jalankan SETELAH platform_finance.sql. Aman diulang.
--
-- `delete from restaurants` akan bekerja — dan membawa serta seluruh
-- isinya, karena hampir semua tabel menggantung padanya dengan
-- `on delete cascade`. Termasuk jurnal GL-nya.
--
-- Itu bukan yang dimaksud orang saat menghapus resto dari daftar.
-- Restonya berhenti berjualan, tapi pembukuan tahun berjalan masih
-- harus bisa dibaca, tagihan langganannya masih harus bisa ditelusuri,
-- dan kalau ternyata salah pencet — resto yang mirip namanya — harus
-- ada jalan kembali.
--
-- Jadi yang dihapus cuma penandanya.

begin;

alter table restaurants add column if not exists is_deleted boolean not null default false;
alter table restaurants add column if not exists deleted_at timestamptz;
alter table restaurants add column if not exists deleted_by text;

create index if not exists idx_restaurants_hidup
  on restaurants (id) where is_deleted = false;

-- ─────────────────────────────────────────────────────────────────────
-- Yang terhapus benar-benar berhenti
-- ─────────────────────────────────────────────────────────────────────
--
-- Menyembunyikannya dari daftar saja tidak cukup. Pelanggan yang
-- terlanjur menyimpan tautan mejanya, atau memindai QR meja yang masih
-- tertempel, akan tetap sampai ke menunya — dan memesan dari resto yang
-- sudah tidak melayani siapa pun.
--
-- RESTRICTIVE, sama alasannya dengan penguncian tagihan: kebijakan
-- permissive digabung dengan OR, jadi menambah satu justru
-- melonggarkan. Yang restrictive digabung dengan AND.

create or replace function is_resto_deleted(p_resto_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select is_deleted from restaurants where id = p_resto_id), false);
$$;

drop policy if exists "orders: deleted resto" on orders;
create policy "orders: deleted resto" on orders
  as restrictive for insert
  with check (not is_resto_deleted(resto_id));

drop policy if exists "products: deleted resto" on products;
create policy "products: deleted resto" on products
  as restrictive for all
  using (not is_resto_deleted(resto_id))
  with check (not is_resto_deleted(resto_id));

-- ─────────────────────────────────────────────────────────────────────
-- Berhenti ditagih
-- ─────────────────────────────────────────────────────────────────────
--
-- Resto yang sudah dihapus tidak boleh menerima tagihan bulan depan.
-- Tagihan yang sudah terbit dibiarkan apa adanya — itu utang yang
-- benar-benar pernah ada, dan menghapusnya berarti menghapus catatan
-- pendapatan yang mungkin sudah masuk.

create or replace function generate_billing_invoices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  b record;
  v_due date;
  v_disc record;
  v_amount bigint;
begin
  for b in
    select rb.* from resto_billing rb
    join restaurants r on r.id = rb.resto_id
    where rb.active = true
      and rb.monthly_price > 0
      and r.is_deleted = false
  loop
    v_due := _billing_due_on(b.billing_day, current_date);
    continue when v_due - current_date > 7;

    select * into v_disc from _best_billing_discount(b.resto_id, b.monthly_price);
    v_amount := b.monthly_price - coalesce(v_disc.amount, 0);

    insert into billing_invoices (
      id, resto_id, period_start, period_end, due_date,
      amount, gross_amount, discount_id, discount_name, discount_amount
    ) values (
      'INV-' || upper(substr(md5(b.resto_id || v_due::text), 1, 10)),
      b.resto_id,
      (v_due - interval '1 month')::date,
      (v_due - interval '1 day')::date,
      v_due,
      v_amount,
      b.monthly_price,
      v_disc.id,
      v_disc.name,
      coalesce(v_disc.amount, 0)
    )
    on conflict (resto_id, period_start) do nothing;

    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- Resto terhapus juga tidak dikunci karena tagihan: layar penguncian
-- menawarkan membayar, dan tidak ada gunanya menagih resto yang sudah
-- kita hentikan sendiri.
create or replace function is_resto_billing_locked(p_resto_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when is_super_admin() then false
    when is_resto_deleted(p_resto_id) then false
    else coalesce((select locked from resto_billing_state(p_resto_id)), false)
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menghapus dan mengembalikan
-- ─────────────────────────────────────────────────────────────────────
--
-- Lewat RPC, bukan UPDATE langsung: penandanya ikut mencatat siapa dan
-- kapan. Penghapusan tanpa jejak siapa yang melakukannya adalah
-- pertanyaan yang tidak akan pernah terjawab saat ada yang menanyakannya
-- enam bulan kemudian.

create or replace function set_resto_deleted(p_resto_id text, p_deleted boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menghapus merchant';
  end if;

  if p_resto_id = 'kaatago' then
    raise exception 'Penyewa platform tidak dapat dihapus';
  end if;

  update restaurants
  set is_deleted = p_deleted,
      deleted_at = case when p_deleted then now() else null end,
      deleted_by = case when p_deleted then auth.jwt() ->> 'email' else null end,
      -- Ikut dinonaktifkan supaya seluruh saringan `active` yang sudah
      -- ada di aplikasi langsung berlaku, tanpa menunggu tiap layar
      -- diajari mengenali penanda baru ini.
      active = case when p_deleted then false else active end
  where id = p_resto_id;
end;
$$;

commit;
