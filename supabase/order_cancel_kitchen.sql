-- KaataGo — pesanan yang batal berhenti punya status dapur.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Sampai sekarang `kitchen_status` berhenti di nilai terakhirnya saat
-- pesanannya dibatalkan. Datanya jadi berbunyi "sedang dimasak" untuk
-- pesanan yang sudah tidak akan pernah dimasak — dan tiap layar yang
-- membacanya harus ingat sendiri untuk mengabaikannya. Yang lupa
-- mengingat itu menampilkan "Sedang Dimasak" ke pelanggan yang
-- pesanannya sudah batal.
--
-- Lebih baik keadaannya ditulis apa adanya di datanya, sekali, daripada
-- diperbaiki berulang kali di tiap layar yang menampilkannya.

begin;

alter table orders drop constraint if exists orders_kitchen_status_check;
alter table orders add constraint orders_kitchen_status_check
  check (kitchen_status in ('waiting', 'onProgress', 'done', 'cancelled'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pemicunya
-- ─────────────────────────────────────────────────────────────────────
--
-- Berjalan saat status bayarnya berubah jadi batal atau hangus.
-- Keduanya berarti sama bagi dapur: makanannya tidak jadi dibuat.
--
-- Yang sudah 'done' tidak diubah. Pesanan yang sudah matang lalu
-- dibatalkan tetap pernah dimasak, dan menghapus jejak itu membuat
-- dapur kehilangan satu-satunya catatan bahwa bahannya sudah terpakai.

create or replace function sync_kitchen_on_cancel()
returns trigger
language plpgsql
as $$
begin
  if new.payment_status in ('cancelled', 'expired')
     and old.payment_status is distinct from new.payment_status
     and new.kitchen_status <> 'done' then
    new.kitchen_status := 'cancelled';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_kitchen_on_cancel on orders;
create trigger trg_sync_kitchen_on_cancel
  before update on orders
  for each row execute function sync_kitchen_on_cancel();

-- ─────────────────────────────────────────────────────────────────────
-- Yang sudah terlanjur tersimpan
-- ─────────────────────────────────────────────────────────────────────
--
-- Pesanan lama yang batal masih membawa status dapur yang tidak berlaku.
-- Tanggal berkas ini dijalankan bukan garis pemisah antara data yang
-- benar dan yang menyesatkan.

update orders
set kitchen_status = 'cancelled'
where payment_status in ('cancelled', 'expired')
  and kitchen_status in ('waiting', 'onProgress');

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
-- Tidak boleh ada yang tersisa:
--
--   select id, payment_status, kitchen_status from orders
--   where payment_status in ('cancelled', 'expired')
--     and kitchen_status in ('waiting', 'onProgress');
--
--   select kitchen_status, count(*) from orders group by 1;
