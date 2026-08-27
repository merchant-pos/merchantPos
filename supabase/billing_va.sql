-- KaataGo — tagihan langganan dibayar lewat Virtual Account Xendit.
--
-- Jalankan SETELAH billing.sql. Aman diulang.
--
-- Sebelumnya resto mengunggah foto bukti transfer dan menunggu
-- diperiksa manusia. Itu bekerja, tapi menaruh jeda berjam-jam — kadang
-- semalam — antara uang yang sudah dikirim dan kunci yang dibuka. Yang
-- menanggung jeda itu adalah resto yang tidak bisa berjualan.
--
-- Virtual Account menutup jeda itu: nomornya tetap, nominalnya terkunci,
-- dan begitu ditransfer, Xendit mengabari kita dalam hitungan detik.
--
-- ── Perbedaan penting dari QRIS pesanan ──────────────────────────────
--
-- QRIS pesanan dibuat atas nama sub-akun restonya, supaya dananya cair
-- ke rekening resto itu. VA langganan justru kebalikannya: dibuat atas
-- nama akun platform, karena inilah satu-satunya aliran uang yang
-- tujuannya memang rekening KaataGo.
--
-- Salah memasang `for-user-id` di sini berarti resto membayar tagihan
-- langganan ke rekeningnya sendiri — dan tidak ada satu pun galat yang
-- muncul saat itu terjadi.

begin;

alter table billing_invoices add column if not exists va_bank text;
alter table billing_invoices add column if not exists va_number text;
alter table billing_invoices add column if not exists va_id text;
alter table billing_invoices add column if not exists va_expires_at timestamptz;
alter table billing_invoices add column if not exists xendit_payment_id text;

-- Bagaimana tagihannya akhirnya lunas. Dibedakan karena keduanya punya
-- tingkat kepercayaan yang berbeda: 'xendit_va' berarti uangnya benar
-- benar masuk dan terkonfirmasi mesin, 'manual' berarti ada orang yang
-- memutuskan berdasarkan foto.
alter table billing_invoices add column if not exists paid_via text;
alter table billing_invoices drop constraint if exists billing_invoices_paid_via_check;
alter table billing_invoices add constraint billing_invoices_paid_via_check
  check (paid_via is null or paid_via in ('xendit_va', 'manual', 'waived'));

create index if not exists idx_billing_invoices_va
  on billing_invoices (va_id) where va_id is not null;

-- Dipakai webhook untuk menemukan tagihannya dari nomor VA-nya.
create index if not exists idx_billing_invoices_va_number
  on billing_invoices (va_number) where va_number is not null;

-- ─────────────────────────────────────────────────────────────────────
-- Bank yang tersedia
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan sebagai batasan, bukan daftar bebas: kode bank yang salah
-- ketik baru ketahuan saat Xendit menolaknya, dan yang melihat
-- penolakan itu adalah resto yang sedang mencoba membayar.
alter table billing_invoices drop constraint if exists billing_invoices_va_bank_check;
alter table billing_invoices add constraint billing_invoices_va_bank_check
  check (va_bank is null or va_bank in
    ('BCA', 'BNI', 'BRI', 'MANDIRI', 'PERMATA', 'BSI', 'CIMB'));

-- ─────────────────────────────────────────────────────────────────────
-- Pelunasan oleh mesin
-- ─────────────────────────────────────────────────────────────────────
--
-- Dipanggil fungsi edge pemroses callback Xendit, memakai service role.
-- Ditulis sebagai fungsi, bukan UPDATE lepas di dalam fungsi edge,
-- supaya syaratnya — nominal cukup, tagihan belum lunas — hidup di satu
-- tempat yang sama dengan aturan lainnya.
-- Dibuang dulu, bukan sekadar `create or replace`.
--
-- Versi pertama fungsi ini mengembalikan boolean; sekarang text.
-- Postgres menolak `create or replace` yang mengubah tipe kembalian —
-- dan penolakannya baru terlihat di database yang sudah pernah
-- menjalankan versi lama, bukan di database kosong tempat berkas ini
-- biasanya diuji:
--
--   ERROR: cannot change return type of existing function
--
-- Tanda tangannya ditulis lengkap supaya yang dibuang persis fungsi
-- ini, bukan fungsi bernama sama dengan argumen berbeda.
drop function if exists settle_billing_va(text, bigint, text);

create or replace function settle_billing_va(
  p_invoice_id text,
  p_amount bigint,
  p_payment_id text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv billing_invoices;
begin
  select * into v_inv from billing_invoices where id = p_invoice_id;

  -- Empat jawaban berbeda, bukan satu "gagal".
  --
  -- Ketiga kegagalannya sama-sama berarti "tidak dilunasi", tapi
  -- artinya jauh berbeda saat ditelusuri: tagihan yang tidak ditemukan
  -- menunjuk ke nomor yang salah, kurang bayar menunjuk ke uang yang
  -- benar-benar masuk tapi kurang. Menyatukan keduanya di bawah satu
  -- pesan membuat penelusuran uang berangkat ke arah yang salah — dan
  -- ini catatan yang dibaca justru saat ada uang yang tidak jelas
  -- rimbanya.
  if v_inv.id is null then
    return 'not_found';
  end if;

  -- Xendit mengulang callback-nya sampai dijawab 200, dan percobaan
  -- kedua tidak boleh menimpa catatan siapa yang melunasi.
  if v_inv.status in ('paid', 'waived') then
    return 'already_paid';
  end if;

  -- VA-nya dibuat tertutup di nominal tagihan, jadi ini seharusnya
  -- tidak pernah terjadi — dan justru karena itu, kalau terjadi, ia
  -- layak berhenti di sini alih-alih diam-diam membuka kunci.
  if p_amount < v_inv.amount then
    return 'underpaid';
  end if;

  update billing_invoices
  set status = 'paid',
      paid_via = 'xendit_va',
      xendit_payment_id = p_payment_id,
      confirmed_by = 'xendit',
      confirmed_at = now(),
      reject_reason = null
  where id = p_invoice_id;

  return 'paid';
end;
$$;

-- Pelunasan manual ikut menandai jalurnya, supaya laporan bisa
-- membedakan mana yang terkonfirmasi mesin dan mana yang keputusan
-- orang.
create or replace function review_billing_payment(
  p_invoice_id text,
  p_accept boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat memutuskan';
  end if;

  update billing_invoices
  set status = case when p_accept then 'paid' else 'unpaid' end,
      paid_via = case when p_accept then 'manual' else null end,
      confirmed_by = auth.jwt() ->> 'email',
      confirmed_at = now(),
      reject_reason = case when p_accept then null else p_reason end
  where id = p_invoice_id;
end;
$$;

commit;
