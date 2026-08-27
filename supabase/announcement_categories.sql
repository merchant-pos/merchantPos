-- KaataGo — pengumuman dibagi dua jenis, dan admin resto boleh mengirim.
--
-- Jalankan SETELAH rilis_setor_petty_inbox.sql. Aman dijalankan
-- berulang kali.
--
-- Sampai sekarang kotak masuk cuma berisi satu jenis pesan: pemberitahuan
-- versi baru, dan hanya Super Admin yang boleh mengirimnya. Dua hal
-- berubah di sini — pengumuman punya jenis, dan pengumuman umum boleh
-- diterbitkan admin resto untuk restonya sendiri.

begin;

-- 'update' = pemberitahuan versi baru, 'general' = pengumuman biasa
-- termasuk promo. Baris lama semuanya pemberitahuan versi, jadi
-- defaultnya itu — dan karena kolomnya baru, seluruh baris lama terisi
-- benar tanpa perlu ditebak satu-satu.
alter table app_announcements
  add column if not exists category text not null default 'update';

alter table app_announcements
  drop constraint if exists app_announcements_category_check;
alter table app_announcements
  add constraint app_announcements_category_check
  check (category in ('update', 'general'));

-- Null berarti untuk semua resto — itulah pengumuman dari Super Admin.
-- Terisi berarti hanya untuk resto itu.
alter table app_announcements
  add column if not exists resto_id text references restaurants (id) on delete cascade;

-- Gambar promo sebagai base64, sependekatan dengan banner promo dan logo
-- resto. Menyimpannya di kolom, bukan di object storage, membuat satu
-- pengumuman tetap satu baris — dan pengumuman yang gambarnya hilang
-- karena berkasnya terhapus terpisah adalah jenis kerusakan yang tidak
-- perlu diciptakan.
alter table app_announcements
  add column if not exists image_base64 text;

create index if not exists idx_announcements_category
  on app_announcements (category, created_at desc);
create index if not exists idx_announcements_resto
  on app_announcements (resto_id);

-- ─────────────────────────────────────────────────────────────────────
-- Siapa boleh menerbitkan apa
-- ─────────────────────────────────────────────────────────────────────
--
-- Super Admin: apa saja, untuk resto mana saja.
--
-- Admin dan Owner: hanya 'general', hanya untuk restonya sendiri.
-- Pemberitahuan versi sengaja tetap milik Super Admin — itu menyangkut
-- APK yang dia terbitkan, dan admin resto tidak punya cara mengetahui
-- versi mana yang sebenarnya sudah rilis.
--
-- Batasnya ditegakkan di sini, bukan hanya di aplikasi: tombol yang
-- disembunyikan cuma menghalangi orang yang memakai aplikasinya.

drop policy if exists "announcements: super_admin write" on app_announcements;
drop policy if exists "announcements: super_admin all" on app_announcements;
create policy "announcements: super_admin all" on app_announcements
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "announcements: resto admin general" on app_announcements;
create policy "announcements: resto admin general" on app_announcements
  for insert
  with check (
    category = 'general'
    and resto_id is not null
    and is_resto_employee(resto_id, array['admin'])
  );

-- Menghapus pengumuman sendiri: yang salah kirim harus bisa ditarik,
-- tapi hanya miliknya sendiri dan hanya yang umum.
drop policy if exists "announcements: resto admin delete own" on app_announcements;
create policy "announcements: resto admin delete own" on app_announcements
  for delete
  using (
    category = 'general'
    and resto_id is not null
    and is_resto_employee(resto_id, array['admin'])
  );

commit;
