-- KaataGo — diskon dengan syarat jumlah pembelian.
--
-- Jalankan SETELAH discounts.sql. Aman diulang.
--
-- "Beli 2 Mont Blanc diskon 30%" adalah bentuk promo yang paling sering
-- dipakai resto, dan sampai sekarang tidak bisa dinyatakan: aturan
-- diskon hanya menyebut menunya, tidak berapa banyak. Akibatnya promo
-- yang dimaksudkan untuk mendorong pembelian kedua ikut terpakai oleh
-- yang membeli satu — persis kebalikan dari maksudnya.
--
-- Bawaannya 1, jadi seluruh diskon yang sudah ada berlaku persis
-- seperti sebelumnya.

begin;

alter table discounts add column if not exists min_qty integer not null default 1;

-- Nol atau negatif tidak punya arti; yang dimaksud "tanpa syarat
-- jumlah" adalah 1.
alter table discounts drop constraint if exists discounts_min_qty_check;
alter table discounts add constraint discounts_min_qty_check
  check (min_qty >= 1);

commit;
