-- KaataGo — diskon ikut memotong tagihan yang sudah terbit.
--
-- Jalankan SETELAH resto_soft_delete.sql. Aman diulang.
--
-- Tagihan diterbitkan tujuh hari sebelum jatuh tempo. Diskon yang dibuat
-- sesudah itu tidak pernah sampai ke tagihan yang sudah ada: penerbitnya
-- memakai `on conflict do nothing`, yang memang menjaga satu tagihan per
-- periode — tapi juga membekukan nominalnya sejak detik pertama.
--
-- Yang terlihat: harga langganan di kartu paket sudah turun, sementara
-- tagihannya masih penuh. Orang yang membacanya menyimpulkan diskonnya
-- tidak berlaku, dan itu kesimpulan yang wajar.
--
-- ── Nomor VA harus ikut dibuang ──────────────────────────────────────
--
-- VA-nya tertutup di nominal tagihan (`is_closed` + `expected_amount`).
-- Kalau nominalnya berubah sementara nomor VA lamanya dibiarkan,
-- transfer sebesar nominal baru akan DITOLAK bank — resto membayar
-- jumlah yang benar dan tetap dianggap belum bayar. Karena itu nomornya
-- dikosongkan tiap kali nominalnya berubah, supaya yang berikutnya
-- diterbitkan ulang dengan nominal yang benar.

begin;

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

    -- Menyegarkan tagihan yang sudah ada, selama belum dibayar.
    --
    -- Hanya yang berstatus 'unpaid'. Yang sudah 'review' berarti restonya
    -- sudah mentransfer sejumlah tertentu dan sedang menunggu diperiksa —
    -- mengubah nominalnya di bawah kaki orang yang sudah membayar adalah
    -- cara tercepat membuat pembayaran yang benar terlihat kurang.
    update billing_invoices i
    set amount = v_amount,
        gross_amount = b.monthly_price,
        discount_id = v_disc.id,
        discount_name = v_disc.name,
        discount_amount = coalesce(v_disc.amount, 0),
        -- Nomor VA dibuang begitu nominalnya berubah. Lihat catatan di
        -- kepala berkas: VA tertutup akan menolak transfer sebesar
        -- nominal baru.
        va_bank = null,
        va_number = null,
        va_id = null,
        va_expires_at = null
    where i.resto_id = b.resto_id
      and i.period_start = (v_due - interval '1 month')::date
      and i.status = 'unpaid'
      and i.amount <> v_amount;
  end loop;
  return v_count;
end;
$$;

-- Menyegarkan satu tagihan sekarang juga.
--
-- Dipakai layar Super Admin sesudah menyunting diskon: menunggu
-- penjadwal harian berarti resto melihat tagihan penuh sampai besok,
-- dan yang menjelaskan selisihnya adalah orang yang menerima telepon.
create or replace function refresh_billing_invoice(p_invoice_id text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv billing_invoices;
  v_price bigint;
  v_disc record;
  v_amount bigint;
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menyegarkan tagihan';
  end if;

  select * into v_inv from billing_invoices where id = p_invoice_id;
  if v_inv.id is null then
    raise exception 'Tagihan tidak ditemukan';
  end if;
  if v_inv.status <> 'unpaid' then
    return v_inv.amount;
  end if;

  select monthly_price into v_price from resto_billing where resto_id = v_inv.resto_id;
  if v_price is null then
    return v_inv.amount;
  end if;

  select * into v_disc from _best_billing_discount(v_inv.resto_id, v_price);
  v_amount := v_price - coalesce(v_disc.amount, 0);

  update billing_invoices
  set amount = v_amount,
      gross_amount = v_price,
      discount_id = v_disc.id,
      discount_name = v_disc.name,
      discount_amount = coalesce(v_disc.amount, 0),
      va_bank = case when v_amount <> v_inv.amount then null else va_bank end,
      va_number = case when v_amount <> v_inv.amount then null else va_number end,
      va_id = case when v_amount <> v_inv.amount then null else va_id end,
      va_expires_at =
        case when v_amount <> v_inv.amount then null else va_expires_at end
  where id = p_invoice_id;

  return v_amount;
end;
$$;

-- Tagihan lama yang terbit sebelum kolom diskon ada belum punya
-- gross_amount. Diisi dari nominalnya sendiri, supaya rincian di layar
-- tidak menampilkan "harga langganan Rp 0".
update billing_invoices
set gross_amount = amount
where gross_amount is null;

commit;
