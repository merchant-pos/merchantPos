-- KaataGo — pelanggan boleh membatalkan pesanannya sendiri selama
-- pembayarannya belum diterima.
--
-- Jalankan SETELAH cash_payment_expiry.sql. Aman dijalankan berulang.
--
-- Sampai sekarang pesanan yang terlanjur dibuat cuma punya dua jalan
-- keluar: dibayar, atau menunggu tiga puluh menit sampai hangus
-- sendiri. Yang berubah pikiran satu menit setelah memesan tetap
-- terlihat di layar kasir dan di dapur selama setengah jam, dan yang
-- harus menjelaskannya adalah pramusaji.
--
-- Dibatalkan berbeda dari hangus, dan keduanya sengaja dibedakan:
-- 'expired' adalah pesanan yang ditinggalkan, 'cancelled' adalah
-- pesanan yang ditarik. Yang pertama pertanda pelanggan hilang, yang
-- kedua tidak — dan resto yang membaca angkanya nanti berhak tahu
-- bedanya.

begin;

alter table orders drop constraint if exists orders_payment_status_check;
alter table orders add constraint orders_payment_status_check
  check (payment_status in ('pending', 'paid', 'expired', 'cancelled'));

-- Lewat fungsi, bukan UPDATE langsung.
--
-- rls_hardening.sql menutup UPDATE pada orders untuk siapa pun selain
-- karyawan, dan itu benar: tanpa itu, siapa pun yang punya anon key
-- bisa menandai pesanan orang lain sudah dibayar. Pengaman
-- pembatalannya ditanam di dalam fungsi ini, bukan dengan membuka
-- kembali pintunya.
create or replace function cancel_my_order(
  p_order_id uuid,
  p_session_id text default null,
  p_email text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    return 'Pesanan tidak ditemukan.';
  end if;

  -- Miliknya sendiri. Pelanggan yang login dikenali dari emailnya, tamu
  -- dari session id yang tersimpan di HP-nya. Tanpa pemeriksaan ini,
  -- nomor pesanan yang terbaca dari struk orang lain sudah cukup untuk
  -- membatalkan pesanannya.
  if not (
    (p_email is not null and v_order.customer_label = p_email)
    or (p_session_id is not null and v_order.session_id = p_session_id)
  ) then
    return 'Pesanan ini bukan milikmu.';
  end if;

  if v_order.source <> 'customer' then
    return 'Pesanan yang diinput kasir dibatalkan lewat kasir.';
  end if;

  if v_order.payment_status = 'paid' then
    return 'Pesanan sudah dibayar. Hubungi kasir untuk pembatalan.';
  end if;

  if v_order.payment_status <> 'pending' then
    return 'Pesanan ini sudah tidak aktif.';
  end if;

  -- Dapur sudah mulai memasak berarti bahannya sudah terpakai.
  -- Membatalkannya sepihak dari HP memindahkan kerugiannya ke resto,
  -- dan yang menanggungnya bukan pihak yang membuat keputusannya.
  if v_order.kitchen_status <> 'waiting' then
    return 'Pesanan sudah mulai dimasak. Hubungi kasir kalau mau batal.';
  end if;

  update orders set payment_status = 'cancelled' where id = p_order_id;
  return null;
end;
$$;

grant execute on function cancel_my_order(uuid, text, text) to anon, authenticated;

commit;
