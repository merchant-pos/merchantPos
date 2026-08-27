-- KaataGo — pencairan dana dari payment gateway.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang pesanan QRIS dicatat penuh dan seketika ke GL QRIS,
-- seolah uangnya langsung ada di rekening. Dengan gateway sungguhan itu
-- tidak benar dua kali:
--
--   1. Yang benar-benar masuk rekening adalah nominal DIKURANGI MDR
--      (sekitar 0,7%).
--   2. Masuknya BARU T+1 atau T+2, bukan saat pelanggan membayar.
--
-- Kalau dibiarkan, GL QRIS akan terus bertambah tanpa pernah cocok
-- dengan mutasi bank mana pun, dan selisihnya menumpuk tiap hari sampai
-- tidak ada yang berani menutup buku.
--
-- Yang berubah di sini bukan pencatatan pemasukannya — itu tetap seperti
-- sekarang. GL QRIS-nya sendiri yang berubah arti: bukan "uang di
-- rekening", melainkan "uang yang ditahan penyedia dan akan cair".
-- Berkas ini menambahkan kejadian keduanya: saat dananya benar-benar
-- cair.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Akun biaya MDR
-- ─────────────────────────────────────────────────────────────────────

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- ─────────────────────────────────────────────────────────────────────
-- 2. Catatan pencairan
-- ─────────────────────────────────────────────────────────────────────

-- Bruto, biaya, dan neto disimpan ketiganya, walaupun yang satu bisa
-- dihitung dari dua lainnya.
--
-- Ini bukan penyimpanan berlebih: yang tertulis di mutasi bank adalah
-- neto, yang tertulis di laporan penyedia adalah bruto dan biaya, dan
-- saat keduanya tidak cocok — pembulatan, biaya tambahan, penyesuaian —
-- yang dibutuhkan justru ketiganya apa adanya. Menghitung ulang salah
-- satunya berarti menghapus bukti bahwa mereka pernah berbeda.
create table if not exists gateway_settlements (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  settled_on date not null default (now() at time zone 'Asia/Jakarta')::date,

  gross_amount bigint not null,
  fee_amount bigint not null default 0,
  net_amount bigint not null,

  provider text not null default 'xendit',
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists gateway_settlements_resto_idx
  on gateway_settlements (resto_id, settled_on desc);

alter table gateway_settlements enable row level security;

drop policy if exists "gateway_settlements: finance read" on gateway_settlements;
create policy "gateway_settlements: finance read" on gateway_settlements
  for select using (is_resto_employee(resto_id, array['finance', 'admin']));

-- Hanya Finance yang mencatatnya. Ini bukan pengajuan yang butuh
-- persetujuan seperti setoran tunai — Finance sedang menyalin apa yang
-- sudah terjadi di rekening, bukan meminta sesuatu terjadi.
drop policy if exists "gateway_settlements: finance write" on gateway_settlements;
create policy "gateway_settlements: finance write" on gateway_settlements
  for all using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));

-- ─────────────────────────────────────────────────────────────────────
-- 3. Jurnalnya
-- ─────────────────────────────────────────────────────────────────────

-- Tiga kaki, dan ketiganya harus seimbang:
--
--   GL QRIS         debit  bruto   uang meninggalkan penampungan penyedia
--   GL Total Saldo  credit neto    yang benar-benar masuk rekening
--   GL Biaya MDR    credit biaya   potongan penyedia, diakui sebagai beban
--
-- Debit = uang keluar dari akun, credit = uang masuk ke akun — konvensi
-- yang sama dengan seluruh jurnal KaataGo lainnya.
create or replace function log_gateway_settlement_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_qris_gl record;
  v_total_gl record;
  v_fee_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  select * into v_qris_gl from _gl_account_for(new.resto_id, 'qris');
  if v_qris_gl.gl_code is not null and v_qris_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_qris_gl.gl_code, v_qris_gl.gl_name, 'gateway_settlement', new.id::text,
      new.gross_amount, 'debit', 'Pencairan gateway #' || v_ref
    );
  end if;

  select * into v_total_gl from _gl_account_for(new.resto_id, 'total_balance');
  if v_total_gl.gl_code is not null and v_total_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_total_gl.gl_code, v_total_gl.gl_name, 'gateway_settlement', new.id::text,
      new.net_amount, 'credit', 'Dana gateway masuk rekening #' || v_ref
    );
  end if;

  -- Biaya nol tidak dijurnal sama sekali. Baris bernilai nol bukan
  -- keterangan, cuma derau yang harus dilewati mata setiap kali.
  if new.fee_amount > 0 then
    select * into v_fee_gl from _gl_account_for(new.resto_id, 'gateway_fee');
    if v_fee_gl.gl_code is not null and v_fee_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_fee_gl.gl_code, v_fee_gl.gl_name, 'gateway_settlement', new.id::text,
        new.fee_amount, 'credit', 'Biaya MDR pencairan #' || v_ref
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_gateway_settlement on gateway_settlements;
create trigger trg_log_gateway_settlement
  after insert on gateway_settlements
  for each row execute function log_gateway_settlement_journal();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- Isi nomor GL untuk "GL Biaya MDR" di Finance → Mapping GL Account.
-- Tanpa itu, biayanya tidak akan tercatat dan jurnal pencairannya jadi
-- timpang sebesar potongan penyedia.
--
-- Memeriksa keseimbangannya kapan pun:
--
--   select reference_id,
--          sum(case when entry_type = 'debit'  then amount else 0 end) as debit,
--          sum(case when entry_type = 'credit' then amount else 0 end) as kredit
--   from gl_journal_entries
--   where reference_type = 'gateway_settlement'
--   group by reference_id;
