-- KaataGo — keuangan KaataGo sendiri, terpisah dari keuangan resto.
--
-- Jalankan SETELAH billing.sql dan billing_va.sql. Aman diulang.
--
-- Sampai sekarang seluruh pembukuan di aplikasi ini milik resto: uang
-- yang masuk ke mereka, pengeluaran mereka, kas kecil mereka. Pendapatan
-- KaataGo sendiri — biaya langganan yang dibayarkan resto — tidak
-- tercatat di mana pun kecuali sebagai baris tagihan berstatus lunas.
--
-- ── Kenapa memakai "resto" sendiri, bukan tabel baru ─────────────────
--
-- Seluruh mesin pembukuan yang sudah ada — bagan akun, jurnal,
-- pengeluaran, kas kecil, berikut pemicu dan kebijakannya — bekerja per
-- resto. Menyalinnya jadi tabel platform_* berarti dua salinan aturan
-- yang sama, dan dua salinan akan berpisah: perbaikan yang dipasang di
-- satu sisi tidak pernah ikut ke sisi lain, dan yang menemukannya
-- adalah selisih angka berbulan-bulan kemudian.
--
-- Jadi KaataGo diberi satu barisnya sendiri di tabel restaurants,
-- ditandai is_platform. Seluruh layar keuangan yang sudah ada langsung
-- bekerja untuknya.
--
-- Konsekuensinya harus dijaga: baris itu tidak boleh muncul di daftar
-- resto mana pun yang dilihat pelanggan atau karyawan.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Penyewa platform
-- ─────────────────────────────────────────────────────────────────────

alter table restaurants add column if not exists is_platform boolean not null default false;

-- active = false supaya ia lolos dari setiap saringan yang sudah ada:
-- daftar resto pelanggan, pemilih resto, dan pencarian semuanya sudah
-- menyaring yang tidak aktif. Penandanya sendiri (is_platform) dipakai
-- untuk menyaring di tempat yang tidak melihat `active` — daftar resto
-- di Super Admin, dan daftar langganan.
insert into restaurants (id, name, address, active, is_platform)
values ('kaatago', 'KaataGo', 'Pembukuan internal KaataGo', false, true)
on conflict (id) do update set is_platform = true;

-- Ia bukan pelanggan dirinya sendiri.
update resto_billing set active = false, monthly_price = 0
where resto_id = 'kaatago';

-- ─────────────────────────────────────────────────────────────────────
-- Bagan akun KaataGo
-- ─────────────────────────────────────────────────────────────────────
--
-- Nomor 11xxxxx dipakai supaya berbeda jelas dari 19xxxxx milik resto.
-- Selisih golongan itu yang membuat satu baris jurnal bisa dikenali
-- pemiliknya hanya dari nomornya, tanpa menelusuri restonya lebih dulu.

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values
  ('kaatago', 'subscription',          '1100001', 'GL Pendapatan Langganan'),
  ('kaatago', 'subscription_discount', '1100002', 'GL Diskon Langganan'),
  ('kaatago', 'cash',                  '1100010', 'GL Kas Tunai KaataGo'),
  ('kaatago', 'transfer',              '1100011', 'GL Rekening KaataGo'),
  ('kaatago', 'qris',                  '1100012', 'GL Penerimaan QRIS KaataGo'),
  ('kaatago', 'income_aggregate',      '1100020', 'GL Pendapatan KaataGo'),
  ('kaatago', 'petty_cash',            '1100030', 'GL Petty Cash KaataGo'),
  ('kaatago', 'total_balance',         '1100040', 'GL Total Saldo KaataGo'),
  ('kaatago', 'suspense',              '1100050', 'GL Suspense KaataGo'),
  ('kaatago', 'suspense_petty',        '1100051', 'GL Suspense Petty KaataGo'),
  ('kaatago', 'gateway_fee',           '1100060', 'GL Biaya Gateway KaataGo'),
  ('kaatago', 'ppn',                   '1100070', 'GL PPN KaataGo'),
  ('kaatago', 'service',               '1100071', 'GL Biaya Service KaataGo'),
  ('kaatago', 'discount',              '1100072', 'GL Diskon Lain KaataGo')
on conflict (resto_id, payment_method) do nothing;

insert into expense_gl_accounts (resto_id, gl_code, gl_name)
select 'kaatago', d.gl_code, d.gl_name
from _default_expense_gl_accounts() d
where not exists (
  select 1 from expense_gl_accounts e
  where e.resto_id = 'kaatago' and e.gl_code = d.gl_code
);

-- ─────────────────────────────────────────────────────────────────────
-- Diskon langganan
-- ─────────────────────────────────────────────────────────────────────
--
-- Potongan harga langganan untuk resto tertentu — masa percobaan,
-- promo pembukaan, kompensasi gangguan. Dipilih per resto, bukan
-- berlaku untuk semuanya: yang sering terjadi justru satu-dua resto
-- yang perlu diperlakukan berbeda.

create table if not exists billing_discounts (
  id text primary key,
  name text not null,

  kind text not null default 'percent' check (kind in ('percent', 'amount')),
  value bigint not null check (value > 0),

  -- Resto yang dikenai. Kosong berarti tidak mengenai siapa pun —
  -- diskon tanpa sasaran bukan diskon, itu setengah jadi.
  resto_ids jsonb not null default '[]'::jsonb,

  starts_on date,
  ends_on date,
  active boolean not null default true,

  created_by text,
  created_at timestamptz not null default now(),

  constraint billing_discounts_period_check
    check (ends_on is null or starts_on is null or ends_on > starts_on),
  constraint billing_discounts_percent_check
    check (kind <> 'percent' or value between 1 and 100)
);

alter table billing_discounts enable row level security;

drop policy if exists "billing_discounts: super admin" on billing_discounts;
create policy "billing_discounts: super admin" on billing_discounts
  for all using (is_super_admin()) with check (is_super_admin());

-- Resto boleh melihat diskon yang mengenai dirinya — potongan yang
-- muncul di tagihan tanpa nama dan alasan terbaca sebagai salah hitung.
drop policy if exists "billing_discounts: resto read" on billing_discounts;
create policy "billing_discounts: resto read" on billing_discounts
  for select using (
    is_super_admin()
    or exists (
      select 1 from jsonb_array_elements_text(resto_ids) t(rid)
      where is_resto_employee(t.rid, array['owner', 'admin', 'finance'])
    )
  );

alter table billing_invoices add column if not exists discount_id text;
alter table billing_invoices add column if not exists discount_name text;
alter table billing_invoices add column if not exists discount_amount bigint not null default 0;
alter table billing_invoices add column if not exists gross_amount bigint;

-- Potongan terbaik untuk sebuah resto hari ini.
--
-- Satu diskon, bukan ditumpuk — alasannya sama dengan diskon menu di
-- resto: dua potongan yang kebetulan berlaku bersamaan bisa melebihi
-- harga langganannya sendiri.
create or replace function _best_billing_discount(p_resto_id text, p_price bigint)
returns table (id text, name text, amount bigint)
language sql
stable
as $$
  select d.id, d.name,
    least(
      case when d.kind = 'percent' then p_price * d.value / 100 else d.value end,
      p_price
    )::bigint as amount
  from billing_discounts d
  where d.active
    and (d.starts_on is null or d.starts_on <= current_date)
    and (d.ends_on is null or d.ends_on >= current_date)
    and d.resto_ids ? p_resto_id
  order by amount desc
  limit 1;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Penerbitan tagihan berikut diskonnya
-- ─────────────────────────────────────────────────────────────────────

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
    select * from resto_billing
    where active = true and monthly_price > 0
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

-- ─────────────────────────────────────────────────────────────────────
-- Jurnal pendapatan langganan
-- ─────────────────────────────────────────────────────────────────────
--
-- Dicatat di buku KaataGo, bukan di buku restonya. Bagi resto, biaya
-- langganan adalah pengeluaran mereka — dan mereka mencatatnya sendiri
-- lewat menu Pengeluaran kalau mau. Menuliskannya ke jurnal mereka dari
-- sini berarti kami menulis di pembukuan orang lain.

alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

create or replace function log_billing_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
  v_resto text;
begin
  if new.status <> 'paid' then
    return new;
  end if;

  -- Sudah pernah dicatat? Tagihan bisa berpindah status lebih dari
  -- sekali — ditolak lalu diterima lagi — dan tiap perpindahan tidak
  -- boleh menambah pendapatan sekali lagi.
  if exists (
    select 1 from gl_journal_entries
    where reference_type = 'billing' and reference_id = new.id
  ) then
    return new;
  end if;

  select name into v_resto from restaurants where id = new.resto_id;

  -- Pendapatan: kredit, karena uang masuk.
  select * into v_gl from _gl_account_for('kaatago', 'subscription');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      'kaatago',
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'billing', new.id, new.amount, 'credit',
      'Langganan ' || coalesce(v_resto, new.resto_id) || ' — ' || new.id
    );
  end if;

  -- Diskon: debit, karena pendapatan yang tidak jadi diterima.
  if coalesce(new.discount_amount, 0) > 0 then
    select * into v_gl from _gl_account_for('kaatago', 'subscription_discount');
    if v_gl.gl_code is not null and v_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        'kaatago',
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl.gl_code, v_gl.gl_name,
        'billing_discount', new.id, new.discount_amount, 'debit',
        coalesce(nullif(new.discount_name, ''), 'Diskon langganan')
          || ' — ' || coalesce(v_resto, new.resto_id)
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_billing_journal on billing_invoices;
create trigger trg_log_billing_journal
  after update of status on billing_invoices
  for each row execute function log_billing_journal();

drop trigger if exists trg_log_billing_journal_insert on billing_invoices;
create trigger trg_log_billing_journal_insert
  after insert on billing_invoices
  for each row execute function log_billing_journal();

-- ─────────────────────────────────────────────────────────────────────
-- Akses Super Admin ke seluruh pembukuan
-- ─────────────────────────────────────────────────────────────────────
--
-- Ditambahkan sebagai kebijakan BARU, bukan dengan menulis ulang yang
-- sudah ada. Kebijakan permissive digabung dengan OR, jadi menambah satu
-- cukup untuk memberi akses — dan menulis ulang yang lama berarti
-- menyalin ulang syaratnya, yang suatu hari akan tersalin tidak lengkap.

drop policy if exists "gl_accounts: super admin" on gl_accounts;
create policy "gl_accounts: super admin" on gl_accounts
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "expense_gl_accounts: super admin" on expense_gl_accounts;
create policy "expense_gl_accounts: super admin" on expense_gl_accounts
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "expenses: super admin" on expenses;
create policy "expenses: super admin" on expenses
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "petty_cash_entries: super admin" on petty_cash_entries;
create policy "petty_cash_entries: super admin" on petty_cash_entries
  for all using (is_super_admin()) with check (is_super_admin());

-- Jurnal: BACA SAJA, lintas seluruh resto.
--
-- Sengaja tanpa insert/update/delete. Tiap baris jurnal ditulis pemicu
-- yang mengikuti kejadian nyata di orders/expenses; tangan yang bisa
-- menulis langsung ke sini adalah tangan yang bisa membuat pembukuan
-- berbeda dari yang benar-benar terjadi — dan itu berlaku untuk Super
-- Admin persis seperti untuk yang lain.
drop policy if exists "gl_journal_entries: super admin read" on gl_journal_entries;
create policy "gl_journal_entries: super admin read" on gl_journal_entries
  for select using (is_super_admin());

-- Pesanan dan setoran ikut terbaca, supaya layar Pemasukan dan rincian
-- jurnal lintas resto punya isinya.
drop policy if exists "orders: super admin read" on orders;
create policy "orders: super admin read" on orders
  for select using (is_super_admin());

drop policy if exists "cash_deposits: super admin read" on cash_deposits;
create policy "cash_deposits: super admin read" on cash_deposits
  for select using (is_super_admin());

commit;
