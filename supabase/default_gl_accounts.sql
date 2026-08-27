-- KaataGo — resto baru langsung punya bagan akun dan tarif pajaknya.
--
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang resto yang baru dibuat lahir tanpa satu pun GL
-- account. Akibatnya bukan sekadar merepotkan: pemicu jurnal melewatkan
-- baris yang GL-nya kosong, jadi transaksi hari-hari pertama benar-benar
-- terjadi, uangnya benar-benar diterima, tapi tidak pernah masuk Jurnal
-- GL. Yang menemukan lubangnya adalah Finance, berminggu-minggu
-- kemudian, saat mencari ke mana perginya penjualan minggu pembukaan.
--
-- Semua yang diisi di sini tetap bisa diubah Finance lewat Mapping GL
-- Account. Yang diberikan cuma titik berangkat yang masuk akal.
--
-- Pengelompokan nomornya:
--
--   195xxxx  Pemasukan (tunai, QRIS, transfer, agregat)
--   196xxxx  Pajak & service
--   198xxxx  Petty cash
--   199xxxx  Total saldo
--   210xxxx  Suspense & pengeluaran
--   220xxxx  Payment gateway & diskon

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tarif bawaan
-- ─────────────────────────────────────────────────────────────────────
--
-- PPN 11% dan service 5% — yang paling lazim dipakai restoran di
-- Indonesia. Nol sebagai bawaan terlihat aman, tapi artinya tiap resto
-- baru menjual dengan harga yang belum memuat pajak sampai ada yang
-- ingat menyetelnya, dan selisih itu tidak bisa ditagih ulang ke
-- pelanggan yang sudah pulang.
--
-- Hanya berlaku untuk resto yang dibuat SESUDAH ini. Resto yang sudah
-- ada tidak disentuh: mengubah tarif pajak resto yang sedang berjalan
-- akan mengubah harga jual seluruh menunya dalam satu perintah.
alter table restaurants alter column ppn_percent set default 11;
alter table restaurants alter column service_percent set default 5;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Bagan akun bawaan
-- ─────────────────────────────────────────────────────────────────────

create or replace function _default_gl_accounts()
returns table (payment_method text, gl_code text, gl_name text)
language sql
immutable
as $$
  values
    -- Pemasukan
    ('cash',             '1950001', 'GL Kas Tunai'),
    ('qris',             '1950002', 'GL Penerimaan QRIS'),
    ('transfer',         '1950003', 'GL Penerimaan Transfer'),
    ('income_aggregate', '1950000', 'GL Pemasukan'),
    -- Pajak & service
    ('ppn',              '1960001', 'GL PPN Keluaran'),
    ('service',          '1960002', 'GL Biaya Service'),
    -- Petty cash
    ('petty_cash',       '1980001', 'GL Petty Cash'),
    -- Total saldo
    ('total_balance',    '1990001', 'GL Total Saldo'),
    -- Suspense — titipan yang belum diakui masuk ke mana pun
    ('suspense',         '2100001', 'GL Suspense Setoran'),
    ('suspense_petty',   '2100002', 'GL Suspense Petty Cash'),
    -- Payment gateway & diskon
    ('gateway_fee',      '2200001', 'GL Biaya Payment Gateway'),
    ('discount',         '2200002', 'GL Diskon Penjualan');
$$;

-- Akun biaya bawaan. Terpisah dari yang di atas karena pengeluaran
-- memang berkategori banyak, dan tiap resto akan menambah sendiri
-- sesudahnya.
create or replace function _default_expense_gl_accounts()
returns table (gl_code text, gl_name text)
language sql
immutable
as $$
  values
    ('2101001', 'GL Biaya Operasional'),
    ('2101002', 'GL Biaya Bahan Baku'),
    ('2101003', 'GL Biaya Gaji'),
    ('2101004', 'GL Biaya Sewa'),
    ('2101005', 'GL Biaya Listrik & Air'),
    ('2101009', 'GL Biaya Lain-lain');
$$;

create or replace function seed_gl_accounts(p_resto_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- `do nothing`, bukan `do update`: resto yang sudah menyetel
  -- nomornya sendiri tidak boleh dikembalikan ke bawaan hanya karena
  -- berkas ini dijalankan lagi. Yang diisi cuma yang belum ada.
  insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
  select p_resto_id, d.payment_method, d.gl_code, d.gl_name
  from _default_gl_accounts() d
  on conflict (resto_id, payment_method) do nothing;

  insert into expense_gl_accounts (resto_id, gl_code, gl_name)
  select p_resto_id, d.gl_code, d.gl_name
  from _default_expense_gl_accounts() d
  where not exists (
    select 1 from expense_gl_accounts e
    where e.resto_id = p_resto_id and e.gl_code = d.gl_code
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Resto baru langsung terisi
-- ─────────────────────────────────────────────────────────────────────
--
-- Lewat pemicu, bukan lewat aplikasi. Resto bisa dibuat dari layar Super
-- Admin, dari SQL saat memulihkan data, atau dari alat lain nanti — dan
-- yang lahir tanpa bagan akun akan diam-diam kehilangan jurnalnya.
create or replace function seed_gl_accounts_for_new_resto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform seed_gl_accounts(new.id);
  return new;
end;
$$;

drop trigger if exists trg_seed_gl_accounts on restaurants;
create trigger trg_seed_gl_accounts
  after insert on restaurants
  for each row execute function seed_gl_accounts_for_new_resto();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Resto yang sudah ada ikut dilengkapi
-- ─────────────────────────────────────────────────────────────────────
--
-- Hanya yang belum punya. Nomor yang sudah disetel Finance tetap seperti
-- adanya — lihat `do nothing` di atas.
do $$
declare
  r record;
begin
  for r in select id from restaurants loop
    perform seed_gl_accounts(r.id);
  end loop;
end $$;

commit;

-- Memeriksa hasilnya:
--
--   select r.name, count(g.*) as akun
--   from restaurants r
--   left join gl_accounts g on g.resto_id = r.id
--   group by r.name order by akun;
