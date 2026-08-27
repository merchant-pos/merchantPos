-- KaataGo — laporan penjualan untuk merchant sendiri.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Angka penjualan selama ini hanya bisa dibaca sebagai daftar transaksi
-- satu per satu. Itu cukup untuk mencocokkan uang, tapi tidak menjawab
-- pertanyaan yang benar-benar menentukan: menu mana yang sebaiknya
-- ditambah porsinya, menu mana yang sebaiknya dibuang dari daftar, dan
-- jam berapa orang harus disiapkan lebih banyak.
--
-- ── Kenapa dihitung di server ────────────────────────────────────────
--
-- Menghitungnya di aplikasi berarti mengunduh seluruh pesanan satu
-- merchant ke sebuah HP, lalu menguraikan `items` satu per satu. Batas
-- 1.000 baris PostgREST memotongnya diam-diam pada merchant yang ramai
-- — dan yang tampil di layar adalah peringkat yang salah tanpa satu pun
-- tanda ada yang hilang. Merchant yang paling butuh laporan ini justru
-- yang paling cepat melewati batas itu.
--
-- ── Siapa yang boleh membacanya ──────────────────────────────────────
--
-- Owner dan Admin saja. Syaratnya ditulis sebagai bagian WHERE, bukan
-- `raise`: yang tidak berhak menerima daftar kosong, karena pesan galat
-- justru mengonfirmasi bahwa datanya ada.
--
-- Kasir dan Chef sengaja tidak. Yang mereka butuhkan pesanan yang
-- sedang berjalan, bukan peringkat menu — dan omzet merchant bukan
-- angka yang perlu beredar di antara semua orang yang memegang HP.
--
-- ── Apa yang dihitung ────────────────────────────────────────────────
--
-- Hanya pesanan **lunas**. Pesanan batal pernah ada di layar kasir tapi
-- tidak pernah jadi uang; menghitungnya membuat menu yang sering
-- dibatalkan terlihat laris.

-- ─────────────────────────────────────────────────────────────────────
-- Menu terlaris
-- ─────────────────────────────────────────────────────────────────────
--
-- Nama menunya diambil dari baris pesanannya, bukan dari katalog. Menu
-- yang sudah dihapus tetap punya sejarah penjualan, dan laporan yang
-- menghilangkannya akan menyebut omzet yang lebih kecil daripada yang
-- benar-benar diterima.
create or replace function report_menu_sales(
  p_resto_id text,
  p_from date,
  p_to date,
  p_limit integer default 10)
returns table (
  product_id text,
  product_name text,
  qty bigint,
  omzet bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select item ->> 'productId',
         max(item ->> 'productName'),
         sum((item ->> 'quantity')::bigint),
         sum((item ->> 'price')::bigint * (item ->> 'quantity')::bigint)
  from orders o,
       lateral jsonb_array_elements(o.items) item
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and (o.created_at at time zone 'Asia/Jakarta')::date
        between p_from and p_to
  group by 1
  order by sum((item ->> 'quantity')::bigint) desc
  limit greatest(1, least(coalesce(p_limit, 10), 100));
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menu yang tidak laku
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang diam justru yang paling menyuruh melakukan sesuatu. Peringkat
-- teratas menyenangkan dilihat tapi tidak mengubah apa pun; menu yang
-- nol selama sebulan adalah bahan yang dibeli, tempat yang dipakai di
-- daftar, dan waktu pelanggan yang terpakai untuk melewatinya.
--
-- Dibaca dari katalog, bukan dari pesanan: menu yang tidak pernah
-- terjual memang tidak punya baris di `orders` sama sekali.
create or replace function report_idle_menus(
  p_resto_id text,
  p_from date,
  p_to date)
returns table (
  product_id text,
  product_name text,
  category text,
  price integer,
  qty bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with terjual as (
    select item ->> 'productId' as pid,
           sum((item ->> 'quantity')::bigint) as qty
    from orders o,
         lateral jsonb_array_elements(o.items) item
    where o.resto_id = p_resto_id
      and o.payment_status = 'paid'
      and (o.created_at at time zone 'Asia/Jakarta')::date
          between p_from and p_to
    group by 1
  )
  select p.id, p.name, p.category, p.price, coalesce(t.qty, 0)
  from products p
  left join terjual t on t.pid = p.id
  where p.resto_id = p_resto_id
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and coalesce(t.qty, 0) = 0
  order by p.category, p.name;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Jam ramai
-- ─────────────────────────────────────────────────────────────────────
--
-- Jam WIB, bukan UTC. Jam ramai yang bergeser tujuh jam adalah jadwal
-- shift yang salah, dan yang menanggungnya kasir yang datang di jam
-- sepi lalu pulang saat antreannya mulai.
create or replace function report_busy_hours(
  p_resto_id text,
  p_from date,
  p_to date)
returns table (
  jam integer,
  orders_count bigint,
  omzet bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select extract(hour from (o.created_at at time zone 'Asia/Jakarta'))::integer,
         count(*),
         coalesce(sum(o.total), 0)::bigint
  from orders o
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and (o.created_at at time zone 'Asia/Jakarta')::date
        between p_from and p_to
  group by 1
  order by 1;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Ringkasan
-- ─────────────────────────────────────────────────────────────────────
--
-- Empat angka yang menjadi pembanding seluruh isi laporan. Tanpa
-- pembanding, "Nasi Goreng terjual 43" adalah angka yang tidak bisa
-- dinilai bagus atau buruk oleh siapa pun.
create or replace function report_sales_summary(
  p_resto_id text,
  p_from date,
  p_to date)
returns table (
  orders_count bigint,
  omzet bigint,
  rata_transaksi bigint,
  menu_terjual bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with pesanan as (
    select o.total, o.items
    from orders o
    where o.resto_id = p_resto_id
      and o.payment_status = 'paid'
      and is_resto_employee(p_resto_id, array['owner', 'admin'])
      and (o.created_at at time zone 'Asia/Jakarta')::date
          between p_from and p_to
  )
  select count(*),
         coalesce(sum(total), 0)::bigint,
         -- Dibulatkan ke bawah supaya sejalan dengan seluruh angka
         -- rupiah di aplikasi ini, yang tidak pernah mengenal sen.
         coalesce(floor(avg(total)), 0)::bigint,
         coalesce((
           select sum((item ->> 'quantity')::bigint)
           from pesanan p2, lateral jsonb_array_elements(p2.items) item
         ), 0)
  from pesanan;
$$;

grant execute on function report_menu_sales(text, date, date, integer) to authenticated;
grant execute on function report_idle_menus(text, date, date) to authenticated;
grant execute on function report_busy_hours(text, date, date) to authenticated;
grant execute on function report_sales_summary(text, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from report_sales_summary('<resto_id>', '2026-08-01', '2026-08-31');
--   select * from report_menu_sales('<resto_id>', '2026-08-01', '2026-08-31', 10);
--   select * from report_idle_menus('<resto_id>', '2026-08-01', '2026-08-31');
--   select * from report_busy_hours('<resto_id>', '2026-08-01', '2026-08-31');
--
--   -- Sebagai Kasir, keempatnya harus mengembalikan daftar kosong —
--   -- bukan pesan galat.
