-- KaataGo — topping per menu, berikut harga dan batas pilihnya.
--
-- Jalankan SETELAH platform_gl_renumber.sql. Aman diulang.
--
-- Topping berbeda bentuk dari level/varian, dan itu sebabnya ia tidak
-- menumpang di sana: level dipilih SATU dari beberapa ("Pedas" atau
-- "Tidak Pedas"), topping dipilih BEBERAPA sekaligus ("Keju dan
-- Telur"). Memaksakan keduanya jadi satu bentuk berarti salah satunya
-- harus berpura-pura jadi yang lain, dan yang berpura-pura selalu bocor
-- di tempat yang tidak terduga.
--
-- Bentuknya:
--
--   [{"name": "Keju", "price": 5000}, {"name": "Telur", "price": 3000}]
--
-- Harga disimpan di sini, bukan dikirim bersama pilihan dari HP: harga
-- yang datang dari aplikasi bisa diubah siapa pun yang ingin menambahkan
-- keju seharga nol rupiah.

begin;

alter table products add column if not exists toppings jsonb not null default '[]'::jsonb;

-- Paling banyak berapa yang boleh dipilih sekaligus. Nol berarti tanpa
-- batas — sebanyak yang ditawarkan.
--
-- Batasnya ada bukan cuma soal harga: dapur punya ruang terbatas di atas
-- satu porsi, dan "semua topping sekaligus" adalah pesanan yang tidak
-- bisa dibuat.
alter table products add column if not exists max_toppings smallint not null default 0;

alter table products drop constraint if exists products_max_toppings_check;
alter table products add constraint products_max_toppings_check
  check (max_toppings >= 0);

commit;
