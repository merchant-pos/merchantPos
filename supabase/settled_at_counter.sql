-- KaataGo — menandai pesanan mandiri yang uangnya diterima di meja
-- kasir, alih-alih menebaknya dari cara bayarnya.
--
-- Aman dijalankan berulang kali.
--
-- Riwayat Kasir berisi dua hal: pesanan yang diinput kasir, dan pesanan
-- mandiri pelanggan yang dilunasi di meja kasir. Yang kedua sampai
-- sekarang dikenali dengan menebak — "cara bayarnya tunai berarti
-- dibayar di kasir".
--
-- Tebakan itu benar selama tunai adalah satu-satunya cara melunasi di
-- meja kasir. Sejak layar Pending Payment bisa mengganti cara bayar ke
-- QRIS atau transfer, tebakannya jadi salah: begitu kasir memilih
-- QRIS, cara bayarnya berubah, tebakannya tidak lagi cocok, dan
-- pesanannya menghilang dari Riwayat Kasir — padahal uangnya baru saja
-- diterima orang yang sedang berdiri di sana.
--
-- Uang yang masuk laci tapi tidak muncul di riwayat adalah selisih yang
-- ditemukan saat tutup shift, oleh orang yang tidak tahu sebabnya.
--
-- Yang ditambahkan di sini adalah catatan tegas: siapa yang menerima,
-- dan kapan. Tidak ada lagi yang perlu ditebak.

begin;

alter table orders add column if not exists settled_by text;
alter table orders add column if not exists settled_at timestamptz;

-- Baris lama tidak diisi surut.
--
-- Yang lama semuanya dilunasi tunai — satu-satunya cara yang ada saat
-- itu — jadi tebakan lamanya masih benar untuk mereka, dan aplikasi
-- tetap memakainya sebagai cadangan. Menuliskan nama penerima yang
-- tidak pernah tercatat justru mengarang riwayat.

commit;
