-- KaataGo — banner promo punya masa berlaku.
--
-- Aman dijalankan berulang kali.
--
-- Sebelumnya banner hanya punya saklar aktif/nonaktif, dan itu berarti
-- ada orang yang harus ingat mematikannya. Promo Ramadan yang masih
-- terpasang di bulan Juli bukan sekadar salah — ia menjanjikan harga
-- yang sudah tidak berlaku kepada orang yang sedang memesan.
--
-- Tanggal, bukan timestamp: resto berpikir dalam hari, dan "sampai 31
-- Agustus" berarti sampai tutup toko tanggal 31.

begin;

alter table promo_banners add column if not exists starts_on date;
alter table promo_banners add column if not exists ends_on date;

alter table promo_banners drop constraint if exists promo_banners_period_check;
alter table promo_banners add constraint promo_banners_period_check
  check (ends_on is null or starts_on is null or ends_on > starts_on);

commit;
