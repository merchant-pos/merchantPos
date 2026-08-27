-- KaataGo — QRIS sungguhan lewat Xendit.
--
-- Jalankan SETELAH customer_cash_payment.sql. Aman dijalankan berulang
-- kali.
--
-- Sampai sekarang QRIS-nya simulasi: kodenya dibangkitkan sendiri dan
-- yang menandai lunas adalah tombol yang ditekan pelanggan. Berkas ini
-- menyiapkan sisi database untuk pembayaran yang benar-benar terjadi —
-- tagihannya dibuat di server, dan yang menyatakannya lunas adalah
-- webhook dari Xendit, bukan siapa pun yang memegang HP.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tagihan yang dibuat di penyedia
-- ─────────────────────────────────────────────────────────────────────

-- Satu baris per tagihan, bukan kolom tambahan di `orders`.
--
-- Sebuah pesanan bisa punya lebih dari satu tagihan: QR yang kedaluwarsa
-- sebelum dibayar harus dibuatkan yang baru, dan yang lama tetap perlu
-- tercatat — kalau ternyata dibayar juga di detik terakhir, webhooknya
-- datang menyebut tagihan yang mana.
create table if not exists payment_charges (
  id uuid primary key default gen_random_uuid(),

  order_id uuid not null references orders (id) on delete cascade,
  resto_id text references restaurants (id) on delete cascade,

  provider text not null default 'xendit',

  -- Pengenal yang kita kirim ke penyedia, dan yang dikembalikan lagi di
  -- webhooknya. Unik, karena itulah yang dipakai mencocokkan kembali.
  reference_id text not null unique,

  -- Pengenal milik penyedia.
  provider_charge_id text,

  -- Isi QR-nya. Disimpan supaya layar yang dibuka ulang menampilkan QR
  -- yang sama persis, bukan membuat tagihan baru tiap kali orangnya
  -- kembali ke layar itu.
  qr_string text,

  amount bigint not null,
  status text not null default 'pending',
  expires_at timestamptz,
  paid_at timestamptz,

  -- Jawaban mentah dari penyedia, apa adanya. Saat ada selisih uang,
  -- inilah satu-satunya keterangan yang tidak bisa dibantah.
  raw jsonb,

  created_at timestamptz not null default now()
);

alter table payment_charges
  drop constraint if exists payment_charges_status_check;
alter table payment_charges add constraint payment_charges_status_check
  check (status in ('pending', 'paid', 'expired', 'failed'));

create index if not exists payment_charges_order_idx on payment_charges (order_id);
create index if not exists payment_charges_status_idx on payment_charges (status, created_at desc);

alter table payment_charges enable row level security;

-- Tidak ada kebijakan apa pun untuk aplikasi. Yang membuat tagihan dan
-- yang menandainya lunas sama-sama Edge Function dengan service role.
-- Membiarkan aplikasi menulis ke sini berarti membiarkan siapa pun yang
-- memegang anon key menyatakan tagihannya sendiri lunas.
revoke all on table payment_charges from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Pelunasan, hanya dari webhook
-- ─────────────────────────────────────────────────────────────────────

-- Dipanggil Edge Function penerima webhook. Satu fungsi, satu tugas:
-- menandai tagihan dan pesanannya lunas, sekali saja.
--
-- Webhook penyedia bisa datang dua kali untuk pembayaran yang sama —
-- itu perilaku normal, bukan kesalahan. Tanpa penjagaan di sini,
-- pesanan yang sama akan masuk jurnal dua kali dan pemasukan hari itu
-- tercatat dobel.
create or replace function settle_gateway_payment(
  p_reference_id text,
  p_provider_charge_id text default null,
  p_raw jsonb default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_charge payment_charges;
begin
  select * into v_charge from payment_charges
  where reference_id = p_reference_id for update;

  if v_charge.id is null then
    return 'tagihan tidak dikenal';
  end if;

  if v_charge.status = 'paid' then
    return 'sudah lunas sebelumnya';
  end if;

  update payment_charges set
    status = 'paid',
    paid_at = now(),
    provider_charge_id = coalesce(p_provider_charge_id, provider_charge_id),
    raw = coalesce(p_raw, raw)
  where id = v_charge.id;

  -- Pesanannya sendiri hanya disentuh kalau memang masih menunggu.
  -- Pesanan yang sudah dilunasi lewat jalan lain — misalnya pelanggan
  -- akhirnya membayar tunai di kasir — tidak boleh ikut tertimpa.
  update orders set payment_status = 'paid'
  where id = v_charge.order_id and payment_status = 'pending';

  return 'lunas';
end;
$$;

-- Tidak diberikan ke anon maupun authenticated. Hanya service role, yang
-- memang melewati pemeriksaan hak akses.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Langkah berikutnya, di luar berkas ini
-- ─────────────────────────────────────────────────────────────────────
--
--   supabase secrets set --project-ref xizpwtycczigjhzxegen \
--     XENDIT_SECRET_KEY='xnd_development_...' \
--     XENDIT_CALLBACK_TOKEN='...'
--
--   supabase functions deploy create-qris    --project-ref xizpwtycczigjhzxegen
--   supabase functions deploy xendit-webhook --project-ref xizpwtycczigjhzxegen --no-verify-jwt
--
-- Lalu daftarkan URL webhooknya di Dashboard Xendit → Settings →
-- Callbacks → QR Code payment:
--
--   https://xizpwtycczigjhzxegen.supabase.co/functions/v1/xendit-webhook
--
-- Memeriksa hasilnya kapan pun:
--
--   select reference_id, amount, status, expires_at, paid_at
--   from payment_charges order by created_at desc limit 20;
