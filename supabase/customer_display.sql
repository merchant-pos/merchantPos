-- KaataGo — layar pelanggan di meja kasir.
--
-- Jalankan kapan saja setelah payment_gateway.sql. Aman diulang.
--
-- Perangkat kedua menghadap pelanggan, menampilkan apa yang sedang
-- ditagih kasir: jumlah yang harus dibayar dan QR-nya.
--
-- Yang ditampilkan disebut di sini, satu baris per resto — bukan
-- ditebak dari "tagihan terakhir". Tebakan semacam itu meleset persis
-- saat paling ramai: dua kasir melayani berbarengan, dan layar depan
-- menampilkan tagihan orang yang mengantre di belakang.
--
-- Barisnya membawa isi tampilannya, bukan penunjuk ke pesanan.
--
-- Rancangan pertamanya menunjuk ke `orders.id` supaya tidak ada angka
-- yang tersalin dua kali. Itu tidak bisa: di alur kasir, pesanannya
-- baru dibuat sesudah pembayaran dikonfirmasi — saat QR-nya tampil,
-- belum ada baris pesanan untuk ditunjuk sama sekali.
--
-- Salinan angkanya aman di sini karena baris ini bukan catatan uang.
-- Ia tampilan sesaat yang ditimpa tiap transaksi dan dikosongkan sesudah
-- selesai; yang dipakai membukukan tetap pesanan dan payment_charges.

begin;

create table if not exists customer_displays (
  resto_id text primary key references restaurants (id) on delete cascade,

  -- 'idle'     — tidak ada yang ditagih
  -- 'awaiting' — menunggu pelanggan membayar
  -- 'paid'     — lunas, tampil sebentar sebagai konfirmasi
  status text not null default 'idle'
    check (status in ('idle', 'awaiting', 'paid')),

  amount bigint,
  qr_string text,

  -- Keterangan singkat: nomor meja, nama pelanggan, atau nomor pesanan
  -- kalau sudah ada.
  label text,

  updated_by text,
  updated_at timestamptz not null default now()
);

alter table customer_displays enable row level security;

-- Dibaca dan ditulis pegawai resto yang bersangkutan.
--
-- Perangkat layar depan masuk dengan akun pegawai resto itu juga.
-- Membiarkannya terbuka untuk umum berarti siapa pun bisa memantau
-- tagihan yang sedang berjalan di resto mana pun — termasuk isi QR-nya,
-- yang bisa dipindai orang lain sebelum pelanggannya sempat.
drop policy if exists "customer_displays: staff read" on customer_displays;
create policy "customer_displays: staff read" on customer_displays
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'kasir', 'finance'])
  );

drop policy if exists "customer_displays: staff write" on customer_displays;
create policy "customer_displays: staff write" on customer_displays
  for all using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'kasir'])
  ) with check (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'kasir'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Menyalakan dan memadamkannya
-- ─────────────────────────────────────────────────────────────────────
--
-- Satu pernyataan, supaya dua kasir yang menekan Bayar hampir bersamaan
-- tidak meninggalkan baris ganda — yang menekan belakangan yang tampil,
-- dan itu memang yang sedang berdiri di depan mesinnya.

create or replace function set_customer_display(
  p_resto_id text,
  p_status text,
  p_amount bigint default null,
  p_qr_string text default null,
  p_label text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'admin', 'kasir'])) then
    raise exception 'Tidak berwenang atas layar merchant ini';
  end if;

  insert into customer_displays (
    resto_id, status, amount, qr_string, label, updated_by, updated_at
  ) values (
    p_resto_id, coalesce(p_status, 'idle'), p_amount, p_qr_string, p_label,
    auth.jwt() ->> 'email', now()
  )
  on conflict (resto_id) do update
    set status = excluded.status,
        amount = excluded.amount,
        qr_string = excluded.qr_string,
        label = excluded.label,
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$$;

revoke all on function set_customer_display(text, text, bigint, text, text)
  from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- Supaya perubahannya sampai seketika
-- ─────────────────────────────────────────────────────────────────────
--
-- Tanpa ini layarnya baru berubah saat dimuat ulang — dan tidak ada
-- yang memuat ulang layar yang menghadap pelanggan.
--
-- Dibungkus penangkap galat, bukan sekadar diberi catatan "abaikan
-- kalau gagal". Menjalankan ulang berkas ini adalah hal biasa, dan
-- galat di sini menghentikan sisa bagiannya — jadi catatan yang
-- menyuruh mengabaikannya justru menyuruh mengabaikan sesuatu yang
-- sudah terlanjur merusak jalannya.
do $$
begin
  alter publication supabase_realtime add table customer_displays;
exception when duplicate_object then null;
end $$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select d.resto_id, r.name, d.status, d.amount, d.label,
--          d.updated_by, d.updated_at
--   from customer_displays d left join restaurants r on r.id = d.resto_id;
