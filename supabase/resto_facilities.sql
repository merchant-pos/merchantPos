-- KaataGo — fasilitas merchant.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Yang membuat orang memilih satu tempat dibanding tempat lain sering
-- bukan menunya: ada AC atau tidak, boleh merokok atau tidak, aman untuk
-- anak atau tidak. Selama ini tidak ada tempat menuliskannya, jadi
-- pelanggan baru tahu setelah sampai — dan yang salah pilih tidak
-- kembali.

begin;

-- Daftar bebas, bukan pilihan tetap.
--
-- Sempat terpikir membuat tabel acuan berisi nama fasilitas yang boleh
-- dipakai. Itu berarti tiap kali ada merchant yang punya sesuatu yang
-- belum terdaftar — mushola, colokan di tiap meja, parkir luas — dia
-- harus menunggu daftarnya ditambah orang lain. Daftar yang menghambat
-- pemiliknya menggambarkan tempatnya sendiri lebih buruk daripada
-- daftar yang sesekali salah ketik.
alter table restaurants
  add column if not exists facilities jsonb not null default '[]'::jsonb;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Catatan
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang boleh mengubahnya sudah diatur kebijakan `restaurants` yang ada:
-- Super Admin, dan Admin/Owner merchant itu sendiri. Tidak ada kebijakan
-- baru di sini — menambahnya justru berisiko melonggarkan yang sudah
-- ketat, karena kebijakan permisif saling di-OR.
--
-- Memeriksanya:
--
--   select name, facilities from restaurants where jsonb_array_length(facilities) > 0;
