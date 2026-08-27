-- KaataGo — rincian kuitansi QRIS dari Xendit, jadi kolomnya sendiri.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Seluruh data ini sebenarnya sudah tersimpan sejak awal di kolom
-- `raw`, apa adanya dari Xendit. Tapi terkubur di dalam JSON ia tidak
-- bisa dicari, tidak bisa diurutkan, dan tidak bisa dicocokkan
-- baris-per-baris dengan mutasi di dashboard penyedia — dan itu persis
-- yang dibutuhkan saat ada satu pembayaran yang angkanya tidak cocok.
--
-- `raw` tetap disimpan dan tetap jadi sumber kebenarannya. Kolom di
-- bawah ini salinan yang dikeluarkan untuk dibaca; kalau suatu saat
-- Xendit mengganti nama medannya, yang hilang cuma salinannya.

begin;

-- ID Transaksi — pengenal pembayaran di sisi Xendit.
alter table payment_charges add column if not exists transaction_id text;

-- ID QR — pengenal QR yang dipindai.
alter table payment_charges add column if not exists qr_id text;

-- ID Product.
alter table payment_charges add column if not exists product_id text;

-- Mitra, dan nama partnernya.
alter table payment_charges add column if not exists partner_code text;
alter table payment_charges add column if not exists partner_name text;

-- ID Kuitansi Mitra — nomor struk di sisi mitra pembayaran.
alter table payment_charges add column if not exists partner_receipt_id text;

-- Sumber dana.
alter table payment_charges add column if not exists payment_source text;

-- ID Pengakuisisi.
alter table payment_charges add column if not exists acquirer_id text;

-- Customer PAN, dan merchant PAN pasangannya.
--
-- PAN pelanggan disimpan sebagaimana dikirim Xendit — sudah tersamar
-- di sisi mereka, dan yang sampai ke sini bukan nomor kartu utuh.
-- Kolomnya ikut aturan baca yang sama dengan seluruh baris ini:
-- pegawai resto yang bersangkutan dan Super Admin, bukan pelanggan.
alter table payment_charges add column if not exists customer_pan text;
alter table payment_charges add column if not exists merchant_pan text;

-- Status apa adanya dari penyedia, berikut kapan terakhir berubah.
--
-- Terpisah dari kolom `status` milik kita sendiri. Yang kita catat
-- hanya mengenal 'pending' dan 'paid' karena itu yang menentukan
-- pesanannya boleh jalan atau tidak; yang dikirim Xendit jauh lebih
-- banyak — ACTIVE, INACTIVE, EXPIRED, FAILED — dan menimpanya ke satu
-- kolom yang sama berarti kehilangan bedanya antara "belum dibayar"
-- dan "sudah gagal".
alter table payment_charges add column if not exists provider_status text;
alter table payment_charges
  add column if not exists provider_status_at timestamptz;

-- Sebabnya kalau gagal, apa adanya dari penyedia.
--
-- Disimpan supaya yang menanyakan besok pagi tidak perlu membuka log
-- fungsi edge — dan supaya pelanggan yang bilang "sudah saya bayar tapi
-- ditolak" bisa dijawab dengan sebab yang sebenarnya.
alter table payment_charges add column if not exists failure_reason text;

-- Dicari saat mencocokkan satu pembayaran dengan mutasi penyedia.
create index if not exists payment_charges_transaction_idx
  on payment_charges (transaction_id);
create index if not exists payment_charges_partner_receipt_idx
  on payment_charges (partner_receipt_id);

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Mengisinya dari yang sudah terlanjur tersimpan
-- ─────────────────────────────────────────────────────────────────────
--
-- Pembayaran yang sudah lewat tetap punya rinciannya di `raw`. Tanggal
-- berkas ini dijalankan bukan garis pemisah antara yang bisa dicocokkan
-- dan yang tidak.
--
-- Nama medannya dicari di dua tempat: badan callback Xendit membungkus
-- isinya di `data`, tapi sebagian versi mengirimnya rata di akar.

update payment_charges c
set provider_status    = coalesce(c.provider_status, d.d ->> 'status'),
    failure_reason     = coalesce(c.failure_reason,
                                  d.d ->> 'failure_code',
                                  d.d ->> 'failure_reason'),
    transaction_id     = coalesce(c.transaction_id, d.d ->> 'id'),
    qr_id              = coalesce(c.qr_id, d.d ->> 'qr_id'),
    product_id         = coalesce(c.product_id, d.d ->> 'product_id'),
    partner_code       = coalesce(c.partner_code, d.d ->> 'channel_code'),
    partner_name       = coalesce(c.partner_name, d.d ->> 'partner'),
    partner_receipt_id = coalesce(c.partner_receipt_id,
                                  d.pd ->> 'receipt_id'),
    payment_source     = coalesce(c.payment_source, d.pd ->> 'source'),
    acquirer_id        = coalesce(c.acquirer_id, d.pd ->> 'acquirer_id'),
    customer_pan       = coalesce(c.customer_pan, d.pd ->> 'customer_pan'),
    merchant_pan       = coalesce(c.merchant_pan, d.pd ->> 'merchant_pan')
from (
  select id,
         coalesce(raw -> 'data', raw) as d,
         coalesce(raw -> 'data' -> 'payment_detail',
                  raw -> 'payment_detail',
                  '{}'::jsonb) as pd
  from payment_charges
  where raw is not null
) as d(id, d, pd)
where c.id = d.id;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select created_at, status, provider_status, amount, transaction_id,
--          qr_id, partner_code, partner_receipt_id, payment_source,
--          acquirer_id, customer_pan, failure_reason
--   from payment_charges
--   order by created_at desc limit 20;
--
-- Yang masih menunggu dan yang gagal ikut tersimpan — status penyedia
-- di kolomnya sendiri, dan `status` milik kita baru berubah jadi 'paid'
-- saat uangnya benar-benar diterima.
--
-- Kolom yang kosong berarti Xendit memang tidak mengirim medan itu
-- untuk pembayaran tersebut — bukan berarti datanya hilang. Yang
-- sebenarnya dikirim selalu bisa dilihat utuh:
--
--   select raw from payment_charges where reference_id = '...';
