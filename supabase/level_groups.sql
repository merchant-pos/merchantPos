-- KaataGo — tiap resto menyusun sendiri kelompok levelnya.
--
-- Jalankan SETELAH product_level_groups.sql. Aman diulang.
--
-- Sebelumnya daftarnya tertanam di dalam aplikasi: lima kelompok tetap
-- (Level Pedas, Level Gula, Level Es, Suhu, Ukuran), sama untuk semua
-- resto. Cukup untuk warung nasi dan kedai kopi, dan langsung kurang
-- untuk yang berikutnya — tingkat kematangan steak, pilihan topping,
-- jenis susu. Resto yang butuh satu kelompok di luar lima itu tidak
-- punya jalan apa pun selain menyuruh pelanggannya mengetik di kolom
-- catatan, yang tidak terbaca sebagai pilihan oleh dapur maupun kasir.
--
-- Produk tetap menyandang NAMA kelompoknya (products.level_groups),
-- bukan id-nya. Sengaja: itu yang sudah tersimpan di ribuan baris
-- produk dan pesanan, dan mengubahnya jadi id berarti membongkar
-- riwayat pesanan yang sudah terjadi hanya demi kerapian.

begin;

create table if not exists level_groups (
  id text primary key,
  resto_id text not null references restaurants (id) on delete cascade,

  -- Namanya yang mengikat produk ke kelompok ini, jadi tidak boleh
  -- kembar di dalam satu resto.
  name text not null,

  options jsonb not null default '[]'::jsonb,

  -- Urutan tampilnya di layar pesan. Kelompok yang paling sering
  -- dipakai pantas berada di atas, dan itu berbeda tiap resto.
  sort_order integer not null default 0,

  created_at timestamptz not null default now(),
  unique (resto_id, name)
);

create index if not exists idx_level_groups_resto on level_groups (resto_id);

alter table level_groups enable row level security;

-- Dibaca siapa saja, termasuk pelanggan tamu yang belum login: tanpa
-- ini dropdown level di layar pesan kosong, dan pesanan pedas tidak
-- bisa dibedakan dari yang tidak.
drop policy if exists "level_groups: public read" on level_groups;
create policy "level_groups: public read" on level_groups
  for select using (true);

drop policy if exists "level_groups: admin write" on level_groups;
create policy "level_groups: admin write" on level_groups
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['admin'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['admin'])
  );

-- ─────────────────────────────────────────────────────────────────────
-- Bibit: lima kelompok yang selama ini tertanam di aplikasi
-- ─────────────────────────────────────────────────────────────────────
--
-- Disemaikan ke tiap resto yang sudah ada, sekali. Tanpa ini semua resto
-- membuka tab Level yang kosong dan produk mereka yang sudah menyandang
-- "Level Pedas" menunjuk kelompok yang tidak ada lagi.
--
-- `on conflict do nothing` yang membuatnya aman diulang: resto yang
-- sudah menyunting "Level Pedas"-nya sendiri tidak dikembalikan ke
-- bentuk bawaan hanya karena berkas ini dijalankan dua kali.

insert into level_groups (id, resto_id, name, options, sort_order)
select
  r.id || ':' || b.name,
  r.id,
  b.name,
  b.options,
  b.sort_order
from restaurants r
cross join (values
  ('Level Pedas',
   '["Tidak Pedas","Sedang","Pedas","Extra Pedas"]'::jsonb, 0),
  ('Level Gula',
   '["Normal","Kurang Manis","Setengah Manis","Tanpa Gula"]'::jsonb, 1),
  ('Level Es',
   '["Normal","Less Ice","No Ice"]'::jsonb, 2),
  ('Suhu',
   '["Panas","Dingin"]'::jsonb, 3),
  ('Ukuran',
   '["Regular","Large"]'::jsonb, 4)
) as b(name, options, sort_order)
on conflict (resto_id, name) do nothing;

commit;

-- Resto yang dibuat SESUDAH ini tetap perlu bibitnya. Pemicu di bawah
-- yang mengurusnya, supaya tidak ada yang harus ingat menjalankan
-- berkas ini lagi tiap kali ada resto baru.
create or replace function seed_level_groups()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into level_groups (id, resto_id, name, options, sort_order)
  select new.id || ':' || b.name, new.id, b.name, b.options, b.sort_order
  from (values
    ('Level Pedas', '["Tidak Pedas","Sedang","Pedas","Extra Pedas"]'::jsonb, 0),
    ('Level Gula', '["Normal","Kurang Manis","Setengah Manis","Tanpa Gula"]'::jsonb, 1),
    ('Level Es', '["Normal","Less Ice","No Ice"]'::jsonb, 2),
    ('Suhu', '["Panas","Dingin"]'::jsonb, 3),
    ('Ukuran', '["Regular","Large"]'::jsonb, 4)
  ) as b(name, options, sort_order)
  on conflict (resto_id, name) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_level_groups on restaurants;
create trigger trg_seed_level_groups
  after insert on restaurants
  for each row execute function seed_level_groups();
