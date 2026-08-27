-- KaataGo — nomor pesanan harian per resto.
--
-- Jalankan kapan saja setelah schema.sql. Aman dijalankan berulang.
--
-- Sampai sekarang pesanan hanya punya UUID. Itu cukup untuk mesin, tapi
-- tidak untuk orang: kasir tidak bisa memanggil "pesanan
-- 8f3a1c2e-..." ke ruangan, dan pelanggan tidak bisa mengingatnya
-- sampai makanannya datang.
--
-- Nomornya dimulai dari 1 tiap hari, dan berdiri sendiri di tiap resto.
-- Angka yang terus bertambah selamanya jadi empat digit dalam sebulan
-- dan berhenti bisa diteriakkan; angka yang dibagi antar resto membuat
-- resto kedua mulai dari nomor yang tidak pernah dia pakai.
--
-- Harinya memakai waktu Jakarta, sama dengan seluruh pembukuan di sini.
-- Memakai UTC berarti nomornya berganti pukul tujuh pagi — di tengah
-- persiapan buka, bukan di antara dua hari kerja.

begin;

alter table orders add column if not exists order_no integer;

-- Tanggal yang dipakai menghitungnya, disimpan supaya nomor lama tetap
-- bisa dibaca artinya tanpa menghitung ulang zona waktunya.
alter table orders add column if not exists order_date date;

-- Nomor yang sama tidak boleh terbit dua kali di resto dan hari yang
-- sama. Ini batasan basis data, bukan pemeriksaan di kode: dua pesanan
-- yang masuk di detik yang sama adalah keadaan biasa saat ramai, dan
-- justru saat ramai itulah nomor kembar paling merepotkan.
create unique index if not exists orders_no_harian_idx
  on orders (resto_id, order_date, order_no)
  where order_no is not null;

-- Pencacahnya. Satu baris per resto per hari.
create table if not exists order_counters (
  resto_id text not null references restaurants (id) on delete cascade,
  order_date date not null,
  last_no integer not null default 0,
  primary key (resto_id, order_date)
);

alter table order_counters enable row level security;
-- Tidak ada kebijakan untuk siapa pun. Yang menyentuhnya hanya pemicu
-- di bawah, yang berjalan SECURITY DEFINER. Tangan yang bisa mengubah
-- pencacah ini adalah tangan yang bisa membuat dua pesanan bernomor
-- sama.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pemberian nomornya
-- ─────────────────────────────────────────────────────────────────────
--
-- Diberikan saat pesanannya dibuat, apa pun status bayarnya. Pelanggan
-- yang masih menunggu QRIS-nya sudah memegang nomor, dan itu memang
-- yang dia butuhkan: nomor itulah yang disebut kasir kalau QRIS-nya
-- gagal dan dia beralih membayar tunai.
--
-- Nomornya tidak ditarik kembali kalau pesanannya batal. Nomor yang
-- dipakai ulang berarti dua struk berbeda menyebut angka yang sama di
-- hari yang sama — dan yang menemukannya adalah orang yang mengambil
-- pesanan orang lain.

create or replace function assign_order_no()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tanggal date := (coalesce(new.created_at, now()) at time zone 'Asia/Jakarta')::date;
  v_no integer;
begin
  if new.order_no is not null then
    return new;
  end if;

  -- Satu pernyataan, dan pertambahannya terjadi di dalam basis data.
  -- Membacanya dulu lalu menambah satu di aplikasi berarti dua pesanan
  -- yang datang bersamaan sama-sama membaca angka yang sama.
  insert into order_counters (resto_id, order_date, last_no)
  values (new.resto_id, v_tanggal, 1)
  on conflict (resto_id, order_date)
  do update set last_no = order_counters.last_no + 1
  returning last_no into v_no;

  new.order_no := v_no;
  new.order_date := v_tanggal;
  return new;
end;
$$;

drop trigger if exists trg_assign_order_no on orders;
create trigger trg_assign_order_no
  before insert on orders
  for each row execute function assign_order_no();

-- ─────────────────────────────────────────────────────────────────────
-- Pesanan yang sudah terlanjur ada
-- ─────────────────────────────────────────────────────────────────────
--
-- Diberi nomor menurut urutan waktunya, per resto per hari — supaya
-- riwayat lama tidak jadi satu-satunya bagian yang kosong nomornya.
-- Pencacahnya ikut disetel ke angka terakhir tiap hari, supaya pesanan
-- berikutnya di hari yang sama tidak menabrak nomor yang sudah dipakai.

with bernomor as (
  select id,
         resto_id,
         (created_at at time zone 'Asia/Jakarta')::date as tgl,
         row_number() over (
           partition by resto_id, (created_at at time zone 'Asia/Jakarta')::date
           order by created_at, id
         ) as no
  from orders
  where order_no is null
)
update orders o
set order_no = b.no, order_date = b.tgl
from bernomor b
where o.id = b.id;

insert into order_counters (resto_id, order_date, last_no)
select resto_id, order_date, max(order_no)
from orders
where order_no is not null and order_date is not null
group by resto_id, order_date
on conflict (resto_id, order_date)
do update set last_no = greatest(order_counters.last_no, excluded.last_no);

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select order_date, resto_id, order_no, payment_status, total
--   from orders order by created_at desc limit 20;
--
-- Tidak boleh ada yang kembar:
--
--   select resto_id, order_date, order_no, count(*)
--   from orders where order_no is not null
--   group by 1, 2, 3 having count(*) > 1;
