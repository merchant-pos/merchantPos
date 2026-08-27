-- KaataGo — banner promo per resto.
--
-- Jalankan kapan saja setelah schema.sql. Aman dijalankan berulang kali.
--
-- Bannernya milik resto, bukan milik KaataGo: tiap resto memasang
-- promonya sendiri, dan customer hanya melihat banner resto yang sedang
-- dia buka.

begin;

create table if not exists promo_banners (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),

  -- Gambar disimpan langsung sebagai base64 di barisnya, sama seperti
  -- logo resto dan foto produk. Tidak ada storage bucket baru yang perlu
  -- disiapkan dan dijaga izinnya — dan banner jumlahnya sedikit, tidak
  -- seperti foto struk yang tumbuh tiap hari.
  image_base64 text not null,

  title text,
  description text,

  -- Nonaktif berarti disimpan tapi tidak ditampilkan. Promo musiman
  -- biasanya kembali dipakai tahun depan, jadi menghapusnya berarti
  -- mengunggah ulang gambar yang sama.
  active boolean not null default true,

  -- Urutan tampil. Promo utama harus bisa ditaruh di depan tanpa
  -- menghapus dan mengunggah ulang yang lain.
  sort_order integer not null default 0,

  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists idx_promo_banners_resto
  on promo_banners(resto_id, active, sort_order);

alter table promo_banners enable row level security;

-- Dibaca siapa saja, termasuk tamu: banner promo justru ditujukan untuk
-- orang yang belum punya akun.
drop policy if exists "promo_banners: public read" on promo_banners;
create policy "promo_banners: public read" on promo_banners
  for select using (true);

-- Yang mengelola hanya admin restonya sendiri (dan owner, yang lolos
-- setiap pemeriksaan peran lewat is_resto_employee), atau super_admin.
drop policy if exists "promo_banners: admin manage" on promo_banners;
create policy "promo_banners: admin manage" on promo_banners
  for all
  using (is_super_admin() or is_resto_employee(resto_id, array['admin']))
  with check (is_super_admin() or is_resto_employee(resto_id, array['admin']));

commit;
