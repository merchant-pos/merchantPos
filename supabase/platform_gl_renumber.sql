-- KaataGo — nomor akun penyewa platform dipindah ke golongan 11xxxxx.
--
-- Jalankan SETELAH gl_discount_backfill.sql. Aman diulang.
--
-- ── Kenapa nomornya tidak sesuai ─────────────────────────────────────
--
-- Baris 'kaatago' dimasukkan ke tabel restaurants, dan pemicu
-- seed_gl_accounts_for_new_resto langsung menyemai bagan akun BAWAAN
-- RESTO untuknya — 195xxxx, 196xxxx, 199xxxx, dan seterusnya. Nomor
-- 11xxxxx yang dimaksudkan untuk platform baru disisipkan sesudah itu,
-- dan `on conflict do nothing` membuatnya tidak melakukan apa-apa.
--
-- Akibatnya bukan sekadar angka yang berbeda dari dokumen. Janjinya
-- adalah satu baris jurnal bisa dikenali pemiliknya hanya dari nomor
-- akunnya — dan dengan KaataGo memakai 199xxxx yang sama dengan resto,
-- janji itu tidak berlaku. Orang yang membaca ekspor gabungan tidak
-- punya cara membedakan mana pendapatan resto dan mana pendapatan kami.
--
-- ── Yang tidak disentuh ──────────────────────────────────────────────
--
-- Hanya nomor yang masih sama persis dengan bawaan resto yang dipindah.
-- Nomor yang sudah disunting sendiri lewat Mapping GL dibiarkan: itu
-- keputusan orang, dan menimpanya berarti mengembalikan pekerjaannya ke
-- bawaan tanpa dia tahu.
--
-- Jurnal yang sudah tercatat ikut dipindahkan nomornya, supaya baris
-- lama dan baru menunjuk akun yang sama. Yang diubah cuma label
-- akunnya; nominal, arah, dan rujukannya tidak disentuh sama sekali.

begin;

-- Pasangan nomor bawaan resto → nomor platform.
--
-- Ditulis sebagai daftar sebaris di dalam tiap pernyataan, bukan tabel
-- sementara. Tabel sementara hanya hidup di satu sesi, dan SQL Editor
-- Supabase bisa menjalankan tiap pernyataan lewat koneksi yang berbeda:
--
--   ERROR: relation "_peta_gl" does not exist
--
-- Galatnya muncul di pernyataan kedua, bukan pada yang membuat tabelnya
-- — jadi yang membacanya menyangka ada yang salah pada UPDATE-nya.

-- Jurnal lebih dulu, selagi nomor lamanya masih bisa dicocokkan.
update gl_journal_entries j
set gl_code = p.ke,
    gl_name = p.nama
from (values
  ('cash',             '1950001', '1100010', 'GL Kas Tunai KaataGo'),
  ('qris',             '1950002', '1100012', 'GL Penerimaan QRIS KaataGo'),
  ('transfer',         '1950003', '1100011', 'GL Rekening KaataGo'),
  ('income_aggregate', '1950010', '1100020', 'GL Pendapatan KaataGo'),
  ('ppn',              '1960001', '1100070', 'GL PPN KaataGo'),
  ('service',          '1960002', '1100071', 'GL Biaya Service KaataGo'),
  ('petty_cash',       '1980001', '1100030', 'GL Petty Cash KaataGo'),
  ('total_balance',    '1990001', '1100040', 'GL Total Saldo KaataGo'),
  ('suspense',         '2100001', '1100050', 'GL Suspense KaataGo'),
  ('suspense_petty',   '2100002', '1100051', 'GL Suspense Petty KaataGo'),
  ('gateway_fee',      '2200001', '1100060', 'GL Biaya Gateway KaataGo'),
  ('discount',         '2200002', '1100072', 'GL Diskon Lain KaataGo')
) as p(payment_method, dari, ke, nama)
where j.resto_id = 'kaatago'
  and j.gl_code = p.dari;

update gl_accounts a
set gl_code = p.ke,
    gl_name = p.nama
from (values
  ('cash',             '1950001', '1100010', 'GL Kas Tunai KaataGo'),
  ('qris',             '1950002', '1100012', 'GL Penerimaan QRIS KaataGo'),
  ('transfer',         '1950003', '1100011', 'GL Rekening KaataGo'),
  ('income_aggregate', '1950010', '1100020', 'GL Pendapatan KaataGo'),
  ('ppn',              '1960001', '1100070', 'GL PPN KaataGo'),
  ('service',          '1960002', '1100071', 'GL Biaya Service KaataGo'),
  ('petty_cash',       '1980001', '1100030', 'GL Petty Cash KaataGo'),
  ('total_balance',    '1990001', '1100040', 'GL Total Saldo KaataGo'),
  ('suspense',         '2100001', '1100050', 'GL Suspense KaataGo'),
  ('suspense_petty',   '2100002', '1100051', 'GL Suspense Petty KaataGo'),
  ('gateway_fee',      '2200001', '1100060', 'GL Biaya Gateway KaataGo'),
  ('discount',         '2200002', '1100072', 'GL Diskon Lain KaataGo')
) as p(payment_method, dari, ke, nama)
where a.resto_id = 'kaatago'
  and a.payment_method = p.payment_method
  and a.gl_code = p.dari;

-- Dua akun yang memang hanya milik platform. Disisipkan kalau pemicunya
-- tidak pernah membuatnya — ia hanya menyemai bawaan resto, dan
-- langganan bukan salah satunya.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values
  ('kaatago', 'subscription',          '1100001', 'GL Pendapatan Langganan'),
  ('kaatago', 'subscription_discount', '1100002', 'GL Diskon Langganan')
on conflict (resto_id, payment_method) do nothing;

commit;
