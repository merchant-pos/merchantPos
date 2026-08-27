-- KaataGo — pencairan langsung ke rekening masing-masing resto.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang seluruh pembayaran QRIS masuk ke satu akun penyedia:
-- yang kuncinya terpasang di server. Untuk resto milik sendiri itu tidak
-- masalah. Untuk resto milik orang lain, itu berarti uang mereka mampir
-- dulu ke rekening KaataGo — dan menampung lalu meneruskan dana milik
-- pihak lain bukan sekadar urusan pembukuan.
--
-- Jalan keluarnya sub-akun: tiap resto punya akunnya sendiri di
-- penyedia, dan pembayarannya dibuat atas nama akun itu. Dananya cair
-- langsung ke rekening restonya, tanpa pernah lewat rekening KaataGo.
--
-- Yang disimpan di sini hanya PENGENAL sub-akunnya, bukan kuncinya.
-- Menyimpan secret key milik resto lain berarti satu kebocoran database
-- membuka seluruh akun penyedia mereka sekaligus — kerugian yang bukan
-- milik kita tapi kita yang menyebabkannya.

begin;

create table if not exists resto_payment_accounts (
  resto_id text primary key references restaurants (id) on delete cascade,

  provider text not null default 'xendit',

  -- Pengenal sub-akun di penyedia. Dikirim sebagai header saat membuat
  -- tagihan, dan itu yang menentukan ke rekening siapa dananya cair.
  account_id text not null,

  -- Sekadar catatan supaya Finance tahu ini akun yang mana tanpa harus
  -- membuka dashboard penyedia.
  account_label text,

  active boolean not null default true,
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table resto_payment_accounts enable row level security;

-- Tidak terbaca pelanggan. Tabel `settings` disiarkan realtime ke layar
-- pembayaran pelanggan, jadi pengenal ini sengaja tidak dititipkan di
-- sana — bukan karena rahasia, tapi karena tidak ada gunanya di HP
-- pelanggan dan yang tidak berguna di sana sebaiknya tidak ada di sana.
drop policy if exists "resto_payment_accounts: staff read" on resto_payment_accounts;
create policy "resto_payment_accounts: staff read" on resto_payment_accounts
  for select using (
    is_super_admin() or is_resto_employee(resto_id, array['finance', 'admin'])
  );

drop policy if exists "resto_payment_accounts: staff write" on resto_payment_accounts;
create policy "resto_payment_accounts: staff write" on resto_payment_accounts
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['finance'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Aktifkan xenPlatform di akun Xendit KaataGo (butuh verifikasi
--    badan usaha; di mode uji bisa langsung dicoba).
--
-- 2. Buat sub-akun untuk tiap resto — lewat Dashboard atau API:
--
--      curl -X POST https://api.xendit.co/v2/accounts \
--        -u 'xnd_development_...:' -H 'Content-Type: application/json' \
--        -d '{"email":"resto@contoh.com","type":"OWNED",
--             "public_profile":{"business_name":"Kaata Resto Dago"}}'
--
--    Jawabannya memuat "id" berawalan angka/huruf — itu yang diisikan
--    ke aplikasi lewat Finance → Pengaturan Pembayaran.
--
-- 3. Tiap resto melengkapi rekening banknya sendiri di sub-akun itu.
--    Sampai itu selesai, dananya tertahan di saldo sub-akun — tidak
--    hilang, tapi juga tidak cair.
--
-- Memeriksa resto mana yang sudah terpasang:
--
--   select r.name, a.account_id, a.active
--   from restaurants r
--   left join resto_payment_accounts a on a.resto_id = r.id;
