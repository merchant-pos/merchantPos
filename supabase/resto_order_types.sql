-- KaataGo — resto menentukan sendiri melayani Dine In, Take Away, atau
-- keduanya.
--
-- Aman dijalankan berulang kali.
--
-- Selama ini kedua pilihan selalu ditawarkan di layar checkout, di
-- semua resto. Padahal tidak semua resto melayani keduanya: gerai food
-- court dan cloud kitchen tidak punya meja sama sekali. Selama
-- pilihannya tetap ada, pesanan yang tidak bisa dilayani tetap masuk —
-- dan yang harus menolaknya adalah orang, di depan pelanggan yang sudah
-- membayar.
--
-- Keduanya true untuk semua resto yang sudah ada. Mematikan salah
-- satunya harus jadi keputusan yang diambil sengaja, bukan akibat kolom
-- baru yang belum sempat diisi.

begin;

alter table restaurants
  add column if not exists dine_in_enabled boolean not null default true;
alter table restaurants
  add column if not exists take_away_enabled boolean not null default true;

-- Resto yang tidak melayani keduanya tidak bisa menerima pesanan apa
-- pun — layar checkoutnya tidak punya satu pun pilihan yang bisa
-- ditekan. Itu bukan konfigurasi, itu resto yang tutup, dan untuk itu
-- sudah ada kolom `active`.
alter table restaurants drop constraint if exists restaurants_order_type_check;
alter table restaurants add constraint restaurants_order_type_check
  check (dine_in_enabled or take_away_enabled);

commit;
