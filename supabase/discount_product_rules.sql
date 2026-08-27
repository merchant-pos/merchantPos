-- KaataGo — syarat jumlah menempel di tiap menu, bukan di promonya.
--
-- Jalankan SETELAH discounts.sql dan discount_min_qty.sql. Aman diulang.
--
-- min_qty menyimpan satu angka untuk seluruh promo, dan itu terlalu
-- longgar untuk bundling: promo "Nasi Goreng + Es Teh, beli 2" berlaku
-- untuk keranjang berisi dua Nasi Goreng dan segelas kopi. Paket yang
-- dijanjikan spanduknya tidak pernah benar-benar dibeli, tapi restonya
-- tetap membayar potongannya.
--
-- Sekarang tiap menu membawa syaratnya sendiri, dan seluruhnya harus
-- terpenuhi:
--
--   [{"product_id": "abc", "qty": 2, "mode": "exactly"},
--    {"product_id": "def", "qty": 1, "mode": "at_least"}]
--
-- 'exactly' untuk paket yang isinya sudah pasti — tiga ayam bukan lagi
-- paket "2 ayam + 1 nasi", dan kalau tetap diberi potongan, harga
-- paketnya tidak berarti apa-apa.

begin;

alter table discounts add column if not exists product_rules jsonb not null default '[]'::jsonb;

-- Promo yang sudah ada dipindahkan apa adanya: tiap menunya memakai
-- min_qty yang berlaku untuknya selama ini. Yang belum punya aturan
-- saja — supaya menjalankan ulang berkas ini tidak menimpa aturan yang
-- sudah disunting Admin.
update discounts
set product_rules = (
  select jsonb_agg(jsonb_build_object(
    'product_id', id,
    'qty', greatest(coalesce(min_qty, 1), 1),
    'mode', 'at_least'
  ))
  from jsonb_array_elements_text(product_ids) as t(id)
)
where basis = 'products'
  and jsonb_array_length(product_ids) > 0
  and jsonb_array_length(product_rules) = 0;

-- min_qty sengaja TIDAK dihapus. Aplikasi versi 1.45.3 masih
-- membacanya, dan kolom yang hilang membuat layar diskonnya gagal
-- memuat — bukan menampilkan promo tanpa syarat jumlah, tapi tidak
-- menampilkan apa-apa. Dibiarkan sampai versi itu tidak lagi terpasang.

commit;
