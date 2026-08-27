-- KaataGo — pesanan tunai yang tidak dilunasi di kasir hangus sendiri.
--
-- Pelanggan yang memesan dari HP lalu memilih bayar tunai diarahkan ke
-- meja kasir. Sebagian tidak pernah sampai ke sana: berubah pikiran,
-- salah pencet, atau memang tidak berniat datang. Tanpa batas waktu,
-- pesanan itu menetap selamanya di layar Pending Payment dan di dapur —
-- dan tiap hari sisanya bertambah sedikit, sampai layarnya tidak lagi
-- bisa dipakai membaca apa yang benar-benar sedang ditunggu.
--
-- Tiga puluh menit dihitung dari pesanannya dibuat. Angka yang sama
-- ditulis di HP pelanggan (CustomerOrder.paymentWindow) — kalau salah
-- satunya diubah, keduanya harus diubah.
--
-- Butuh pg_cron. Kalau belum aktif: Dashboard → Database → Extensions →
-- cari "pg_cron" → Enable. Aman dijalankan berulang kali.

begin;

create extension if not exists pg_cron with schema extensions;

-- 'expired' — dibatalkan karena tidak dibayar. Dibedakan dari 'pending'
-- supaya hilang dari antrean kasir dan dapur, dan dibedakan dari 'paid'
-- supaya tidak pernah ikut terhitung sebagai pendapatan.
--
-- Daftarnya ditulis lengkap — termasuk 'cancelled' yang baru
-- diperkenalkan berkas lain. Berkas yang menuliskan daftar sepanjang
-- zamannya sendiri berjalan baik tepat sekali: saat dijalankan berurutan
-- di database kosong. Menjalankan ulang yang lebih tua sesudah yang
-- lebih baru menyempitkan daftarnya lagi, dan baris yang terlanjur
-- memakai nilai baru langsung melanggarnya:
--
--   check constraint "orders_payment_status_check" is violated by some row
--
-- Tidak ada satu pun data yang salah di sana. Yang salah adalah
-- batasannya yang mundur.
alter table orders drop constraint if exists orders_payment_status_check;
alter table orders add constraint orders_payment_status_check
  check (payment_status in ('pending', 'paid', 'expired', 'cancelled'));

create or replace function expire_unpaid_cash_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with hangus as (
    update orders
    set payment_status = 'expired'
    where payment_status = 'pending'
      and source = 'customer'
      -- Hanya yang tunai. Pesanan QRIS punya tenggangnya sendiri di sisi
      -- penyedia pembayaran, dan membatalkannya dari sini berarti
      -- membatalkan pesanan yang uangnya mungkin sedang dalam perjalanan.
      and _normalize_payment_method(source, payment_method) = 'cash'
      and created_at <= now() - interval '30 minutes'
    returning 1
  )
  select count(*) into v_count from hangus;
  return v_count;
end;
$$;

-- Tiap menit. Tenggangnya tetap 30 menit — yang diputuskan di sini cuma
-- seberapa cepat pesanan yang sudah lewat tenggang benar-benar hilang
-- dari layar, dan menitan sudah cukup rapat untuk itu.
select cron.unschedule('expire-unpaid-cash-orders')
where exists (
  select 1 from cron.job where jobname = 'expire-unpaid-cash-orders'
);

select cron.schedule(
  'expire-unpaid-cash-orders',
  '* * * * *',
  $$select expire_unpaid_cash_orders();$$
);

commit;
