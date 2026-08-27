-- KaataGo — langganan bulanan resto.
--
-- Jalankan SETELAH schema.sql, rls_hardening.sql, dan super_admin.sql.
-- Aman dijalankan berulang. Butuh pg_cron.
--
-- Resto membayar biaya langganan bulanan. Harganya dan tanggal
-- tagihannya ditentukan per resto oleh Super Admin — bukan satu angka
-- untuk semuanya, karena resto yang baru buka dan jaringan sepuluh
-- cabang tidak pernah dinilai sama.
--
-- Tiga hari sebelum jatuh tempo, restonya diingatkan. Lewat satu hari
-- dari jatuh tempo dan tagihannya belum lunas, restonya terkunci.
--
-- ── Kenapa penguncian ditegakkan di sini, bukan di aplikasi ──────────
--
-- Aplikasi ini berbicara langsung ke Postgres tanpa server perantara.
-- Layar yang terkunci hanyalah layar: siapa pun yang memegang kunci
-- publik proyek bisa memanggil API-nya langsung dan tetap membuat
-- pesanan. Karena itu penguncian dipasang sebagai kebijakan RLS
-- restrictive — yang tidak bisa dilewati lewat jalan mana pun, termasuk
-- jalan yang belum terpikirkan hari ini.
--
-- ── Yang sengaja TIDAK dikunci ───────────────────────────────────────
--
-- Membaca tagihan sendiri dan mengunggah bukti bayar tetap terbuka.
-- Mengunci itu berarti mengunci satu-satunya jalan keluar dari
-- penguncian — resto yang sudah membayar tidak punya cara memberi tahu
-- siapa pun.

begin;

create extension if not exists pg_cron with schema extensions;

-- ─────────────────────────────────────────────────────────────────────
-- Setelan langganan per resto
-- ─────────────────────────────────────────────────────────────────────

create table if not exists resto_billing (
  resto_id text primary key references restaurants (id) on delete cascade,

  -- Rupiah per bulan. Nol berarti gratis — dipakai untuk masa percobaan
  -- dan resto milik sendiri, dan resto bernilai nol tidak pernah
  -- terkunci.
  monthly_price bigint not null default 0 check (monthly_price >= 0),

  -- Tanggal jatuh tempo tiap bulan. Dibatasi 1–28 supaya artinya sama
  -- di bulan mana pun: "tanggal 31" tidak ada di bulan Februari, dan
  -- menggesernya diam-diam ke 28 membuat tagihan datang di hari yang
  -- tidak dijanjikan.
  billing_day smallint not null default 1
    check (billing_day between 1 and 28),

  -- Tenggang sesudah jatuh tempo sebelum restonya terkunci.
  grace_days smallint not null default 1 check (grace_days >= 0),

  -- Dimatikan berarti resto ini tidak pernah ditagih dan tidak pernah
  -- terkunci, apa pun isi tabel tagihannya.
  active boolean not null default true,

  started_on date not null default current_date,
  note text,
  updated_at timestamptz not null default now()
);

-- Resto baru langsung punya barisnya, gratis, sampai Super Admin
-- menetapkan harganya. Bawaan yang menagih sebelum ada yang menyepakati
-- harganya akan mengunci resto yang belum pernah diberi tahu.
create or replace function seed_resto_billing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into resto_billing (resto_id, monthly_price, billing_day)
  values (new.id, 0, 1)
  on conflict (resto_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_resto_billing on restaurants;
create trigger trg_seed_resto_billing
  after insert on restaurants
  for each row execute function seed_resto_billing();

insert into resto_billing (resto_id, monthly_price, billing_day)
select r.id, 0, 1 from restaurants r
on conflict (resto_id) do nothing;

-- ─────────────────────────────────────────────────────────────────────
-- Tagihan
-- ─────────────────────────────────────────────────────────────────────

create table if not exists billing_invoices (
  id text primary key,
  resto_id text not null references restaurants (id) on delete cascade,

  period_start date not null,
  period_end date not null,
  due_date date not null,
  amount bigint not null check (amount >= 0),

  -- unpaid  → belum dibayar
  -- review  → resto sudah mengunggah bukti, menunggu diperiksa KaataGo
  -- paid    → diterima
  -- waived  → dibebaskan (masa percobaan, kompensasi gangguan)
  status text not null default 'unpaid'
    check (status in ('unpaid', 'review', 'paid', 'waived')),

  proof_base64 text,
  paid_note text,
  submitted_at timestamptz,

  confirmed_by text,
  confirmed_at timestamptz,
  reject_reason text,

  created_at timestamptz not null default now(),

  -- Satu tagihan per resto per periode. Tanpa ini, pembangkit yang
  -- kebetulan berjalan dua kali menagih dua kali — dan yang menemukannya
  -- adalah restonya, bukan kita.
  constraint billing_invoices_period_unique unique (resto_id, period_start)
);

create index if not exists idx_billing_invoices_resto
  on billing_invoices (resto_id, due_date desc);
create index if not exists idx_billing_invoices_open
  on billing_invoices (due_date) where status in ('unpaid', 'review');

-- ─────────────────────────────────────────────────────────────────────
-- Penerbitan tagihan
-- ─────────────────────────────────────────────────────────────────────

-- Jatuh tempo berikutnya bagi sebuah tanggal.
create or replace function _billing_due_on(p_day smallint, p_from date)
returns date
language sql
immutable
as $$
  select case
    when extract(day from p_from) <= p_day
      then make_date(extract(year from p_from)::int,
                     extract(month from p_from)::int, p_day)
    else (make_date(extract(year from p_from)::int,
                    extract(month from p_from)::int, p_day)
          + interval '1 month')::date
  end;
$$;

-- Diterbitkan tujuh hari sebelum jatuh tempo, supaya pengingat H-3
-- punya tagihan yang bisa ditunjuk — pengingat membayar tanpa nominal
-- dan nomor tagihan bukan pengingat, cuma kabar cemas.
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
begin
  for b in
    select * from resto_billing
    where active = true and monthly_price > 0
  loop
    v_due := _billing_due_on(b.billing_day, current_date);
    continue when v_due - current_date > 7;

    insert into billing_invoices (
      id, resto_id, period_start, period_end, due_date, amount
    ) values (
      'INV-' || upper(substr(md5(b.resto_id || v_due::text), 1, 10)),
      b.resto_id,
      (v_due - interval '1 month')::date,
      (v_due - interval '1 day')::date,
      v_due,
      b.monthly_price
    )
    on conflict (resto_id, period_start) do nothing;

    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

select cron.unschedule('generate-billing-invoices')
where exists (
  select 1 from cron.job where jobname = 'generate-billing-invoices'
);

-- Sekali sehari, lewat tengah malam WIB (17:00 UTC).
select cron.schedule(
  'generate-billing-invoices',
  '5 17 * * *',
  $$select generate_billing_invoices();$$
);

-- ─────────────────────────────────────────────────────────────────────
-- Keadaan langganan sebuah resto
-- ─────────────────────────────────────────────────────────────────────

-- Satu sumber kebenaran, dipakai RLS maupun layar aplikasi. Dua
-- perhitungan terpisah akan berpisah, dan yang terlihat adalah layar
-- yang mengaku aman sementara database menolak menyimpan apa pun.
-- Dibuang dulu, bukan langsung `create or replace`.
--
-- `billing_due_day.sql` menambah kolom `next_due_date` ke kembaliannya,
-- dan Postgres menolak `create or replace` yang mengubah tipe
-- kembalian. Di basis data yang sudah menjalankan berkas itu, berkas
-- ini akan gagal dengan 42P13 — dan berkas yang tidak aman dijalankan
-- ulang berhenti jadi berkas yang bisa dipercaya (lihat TSD §11.2).
drop function if exists resto_billing_state(text);

create or replace function resto_billing_state(p_resto_id text)
returns table (
  locked boolean,
  due_date date,
  days_left integer,
  amount bigint,
  invoice_id text,
  invoice_status text,
  monthly_price bigint,
  billing_day smallint,
  active boolean
)
language sql
security definer
set search_path = public
stable
as $$
  with setelan as (
    select * from resto_billing where resto_id = p_resto_id
  ),
  tertunggak as (
    select i.* from billing_invoices i
    where i.resto_id = p_resto_id
      and i.status in ('unpaid', 'review')
    order by i.due_date
    limit 1
  )
  select
    -- Terkunci hanya kalau tagihannya benar-benar lewat tenggang DAN
    -- belum diserahkan buktinya. Resto yang sudah mengunggah bukti
    -- diberi kesempatan sampai diperiksa — mengunci orang yang sudah
    -- membayar adalah kesalahan yang paling mahal di seluruh fitur ini.
    coalesce(
      s.active
      and s.monthly_price > 0
      and t.id is not null
      and t.status = 'unpaid'
      and current_date > t.due_date + s.grace_days,
      false
    ),
    t.due_date,
    (t.due_date - current_date)::integer,
    t.amount,
    t.id,
    t.status,
    coalesce(s.monthly_price, 0),
    coalesce(s.billing_day, 1::smallint),
    coalesce(s.active, false)
  from setelan s
  left join tertunggak t on true;
$$;

-- Bentuk ringkas untuk RLS. Super Admin tidak pernah terkunci: dialah
-- yang membuka kuncinya.
create or replace function is_resto_billing_locked(p_resto_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when is_super_admin() then false
    else coalesce((select locked from resto_billing_state(p_resto_id)), false)
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Penguncian
-- ─────────────────────────────────────────────────────────────────────
--
-- Kebijakan RESTRICTIVE, bukan permissive. Kebijakan permissive
-- digabung dengan OR — menambah satu lagi justru MELONGGARKAN aksesnya.
-- Yang restrictive digabung dengan AND, dan itulah satu-satunya bentuk
-- yang benar-benar menutup pintu tanpa menyentuh kebijakan yang sudah
-- ada.

drop policy if exists "orders: billing lock" on orders;
create policy "orders: billing lock" on orders
  as restrictive for insert
  with check (not is_resto_billing_locked(resto_id));

drop policy if exists "orders: billing lock update" on orders;
create policy "orders: billing lock update" on orders
  as restrictive for update
  using (not is_resto_billing_locked(resto_id));

-- Katalog ikut dibekukan. Tanpa ini, resto terkunci masih bisa
-- mengubah harga dan menu — pekerjaan yang hasilnya tidak bisa dijual.
drop policy if exists "products: billing lock" on products;
create policy "products: billing lock" on products
  as restrictive for all
  using (not is_resto_billing_locked(resto_id))
  with check (not is_resto_billing_locked(resto_id));

-- ─────────────────────────────────────────────────────────────────────
-- RLS tabel langganan
-- ─────────────────────────────────────────────────────────────────────

alter table resto_billing enable row level security;
alter table billing_invoices enable row level security;

-- Resto boleh melihat setelannya sendiri — orang berhak tahu berapa
-- yang ditagihkan kepadanya dan kapan. Yang mengubah hanya Super Admin.
drop policy if exists "resto_billing: read" on resto_billing;
create policy "resto_billing: read" on resto_billing
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

drop policy if exists "resto_billing: super admin write" on resto_billing;
create policy "resto_billing: super admin write" on resto_billing
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "billing_invoices: read" on billing_invoices;
create policy "billing_invoices: read" on billing_invoices
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance', 'kasir', 'chef'])
  );

drop policy if exists "billing_invoices: super admin write" on billing_invoices;
create policy "billing_invoices: super admin write" on billing_invoices
  for all using (is_super_admin()) with check (is_super_admin());

-- Resto mengunggah bukti bayar lewat RPC, bukan UPDATE langsung —
-- kalau langsung, tidak ada yang mencegahnya menulis status 'paid'
-- sendiri.
create or replace function submit_billing_payment(
  p_invoice_id text,
  p_proof_base64 text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resto text;
begin
  select resto_id into v_resto from billing_invoices where id = p_invoice_id;
  if v_resto is null then
    raise exception 'Tagihan tidak ditemukan';
  end if;

  if not (is_super_admin()
          or is_resto_employee(v_resto, array['owner', 'admin', 'finance'])) then
    raise exception 'Tidak berwenang atas tagihan ini';
  end if;

  update billing_invoices
  set status = 'review',
      proof_base64 = coalesce(p_proof_base64, proof_base64),
      paid_note = p_note,
      submitted_at = now(),
      reject_reason = null
  where id = p_invoice_id
    and status in ('unpaid', 'review');
end;
$$;

-- Hanya KaataGo yang menyatakan lunas. Itu satu-satunya cara membuka
-- kunci, jadi wewenangnya tidak dibagi.
create or replace function review_billing_payment(
  p_invoice_id text,
  p_accept boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat memutuskan';
  end if;

  update billing_invoices
  set status = case when p_accept then 'paid' else 'unpaid' end,
      confirmed_by = auth.jwt() ->> 'email',
      confirmed_at = now(),
      reject_reason = case when p_accept then null else p_reason end
  where id = p_invoice_id;
end;
$$;

commit;
