-- KaataGo — penilaian merchant oleh pelanggan, dan jam bukanya.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Dua hal yang paling sering menentukan orang jadi datang atau tidak,
-- dan keduanya belum punya tempat: apa kata orang yang sudah ke sana,
-- dan apakah tempatnya sedang buka.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Jam buka
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan sebagai satu objek per merchant, bukan tujuh baris tabel
-- terpisah. Yang dibaca dan ditulis selalu tujuh-tujuhnya sekaligus —
-- tidak ada satu pun layar yang menanyakan "jam buka hari Rabu saja".
--
-- Bentuknya: {"1": {"buka":"08:00","tutup":"22:00"}, ...} dengan 1 =
-- Senin sampai 7 = Minggu, mengikuti penomoran ISO. Hari yang tidak ada
-- kuncinya berarti tutup — itu lebih jujur daripada menyimpan
-- "00:00-00:00" yang bisa terbaca sebagai buka 24 jam.
alter table restaurants
  add column if not exists opening_hours jsonb not null default '{}'::jsonb;

-- ─────────────────────────────────────────────────────────────────────
-- Penilaian
-- ─────────────────────────────────────────────────────────────────────

create table if not exists merchant_reviews (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  -- Email pelanggan. Penilaian menempel pada orang, bukan pada
  -- perangkat: yang menilai di HP lama harus tetap menemukannya di HP
  -- baru, dan yang membacanya berhak tahu itu orang yang berbeda-beda.
  customer_email text not null,

  -- Namanya disalin saat menilai, tidak dibaca ulang dari profilnya.
  -- Profil bisa berganti nama besok; ulasan yang tiba-tiba berganti
  -- penulis adalah ulasan yang tidak bisa dipercaya.
  customer_name text not null,

  rating smallint not null check (rating between 1 and 5),
  comment text,

  -- Foto, base64, paling banyak tiga. Disimpan di kolom seperti banner
  -- dan foto menu — satu ulasan tetap satu baris.
  photos jsonb not null default '[]'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Satu orang satu penilaian per merchant. Yang berubah pikiran
  -- mengubah penilaiannya, bukan menambah yang kedua — tanpa ini, satu
  -- orang yang kecewa bisa menenggelamkan rata-ratanya sendirian.
  unique (resto_id, customer_email)
);

create index if not exists merchant_reviews_resto_idx
  on merchant_reviews (resto_id, created_at desc);

alter table merchant_reviews enable row level security;

-- Dibaca siapa saja, termasuk tamu.
--
-- Ulasan memang untuk dibaca sebelum memutuskan, dan yang paling
-- membutuhkannya justru orang yang belum punya akun.
drop policy if exists "merchant_reviews: public read" on merchant_reviews;
create policy "merchant_reviews: public read" on merchant_reviews
  for select using (true);

-- Ditulis hanya oleh pemiliknya sendiri, dan hanya kalau sudah masuk.
drop policy if exists "merchant_reviews: own write" on merchant_reviews;
create policy "merchant_reviews: own write" on merchant_reviews
  for all using (customer_email = auth.jwt() ->> 'email')
  with check (customer_email = auth.jwt() ->> 'email');

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Rata-rata dan jumlahnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Dihitung server, bukan diunduh seluruh ulasannya lalu dijumlahkan di
-- HP. Daftar merchant menampilkan puluhan baris sekaligus; mengunduh
-- seluruh ulasan tiap merchant untuk satu angka bintang berarti layar
-- pilih merchant menarik ribuan baris tiap kali dibuka.

create or replace function merchant_rating_summary()
returns table (resto_id text, rata numeric, jumlah bigint)
language sql
stable
as $$
  select r.resto_id,
         round(avg(r.rating)::numeric, 1),
         count(*)
  from merchant_reviews r
  group by r.resto_id;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from merchant_rating_summary();
--
--   select m.name, r.customer_name, r.rating, r.comment, r.created_at
--   from merchant_reviews r join restaurants m on m.id = r.resto_id
--   order by r.created_at desc limit 20;
