-- KaataGo — ketersediaan produk ditandai, bukan dihitung.
--
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang produk hilang dari menu begitu stoknya 0. Itu memaksa
-- tiap resto mengurus angka yang sebagian besar tidak pernah mereka
-- hitung: nasi goreng tidak punya "sisa 7 porsi", yang ada cuma "masih
-- ada" atau "bahannya habis". Resto yang membiarkan stoknya 0 karena
-- angkanya memang tidak relevan justru kehilangan seluruh menunya, dan
-- tidak pernah tahu kenapa.
--
-- Sekarang angka stok jadi catatan biasa — boleh diisi, boleh tidak —
-- dan yang menentukan bisa dipesan atau tidak cuma kolom ini, yang
-- dinyatakan sengaja oleh orang yang tahu keadaan dapurnya.

begin;

alter table products
  add column if not exists out_of_stock boolean not null default false;

-- Stok tidak lagi wajib. Produk yang tidak diisi angkanya bukan produk
-- yang habis — cuma produk yang tidak dihitung.
alter table products alter column stock drop not null;
alter table products alter column stock set default 0;

-- Produk lama dianggap tersedia, termasuk yang stoknya 0.
--
-- Sebagian dari mereka memang benar-benar habis, dan menyalakannya
-- kembali berarti resto harus menandainya lagi satu per satu. Itu
-- disengaja: resto jauh lebih cepat menandai barang yang habis daripada
-- menemukan sendiri kenapa separuh menunya tidak pernah muncul.
update products set out_of_stock = false where out_of_stock is null;

commit;

-- Catatan: fungsi decrement_stock tetap dipakai — angkanya masih
-- berguna buat resto yang memang menghitung. Yang berubah cuma
-- artinya: mencapai nol tidak lagi menyembunyikan produknya.
