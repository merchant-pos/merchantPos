-- KaataGo — Setoran Saldo Cash + pemisahan Cash / Non Cash
-- (run AFTER journal_integrity.sql dan tax_and_service.sql).
--
-- Sampai sekarang semua pemasukan dianggap satu kantong. Padahal uang
-- tunai berbeda sifatnya: ia benar-benar ada di laci kasir dan harus
-- disetorkan, sedangkan QRIS dan transfer sudah langsung mendarat di
-- rekening. Menyatukan keduanya membuat "Saldo Penghasilan" tidak bisa
-- dipakai untuk menjawab satu pertanyaan yang paling sering ditanyakan
-- pemilik resto: berapa uang tunai yang seharusnya ada di laci sekarang?
--
-- Karena itu:
--   Saldo Cash     = pemasukan tunai − setoran − top up petty cash dari tunai
--   Saldo Non Cash = pemasukan QRIS/transfer − top up petty cash dari situ
--
-- Setoran memindahkan uang, bukan menghabiskannya: GL Cash berkurang,
-- GL Total Saldo bertambah. Saldo Total resto tidak berubah karenanya.

-- ── 1. Tabel setoran ─────────────────────────────────────────────────
create table if not exists cash_deposits (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  amount integer not null check (amount > 0),
  -- Bukti transfer/setor, disimpan langsung sebagai base64 di barisnya —
  -- pendekatan yang sama dengan foto produk dan nota pengeluaran, jadi
  -- tidak ada storage bucket baru yang perlu disiapkan dan dijaga
  -- izinnya.
  proof_base64 text,
  note text,
  -- Email penyetor. Kasir yang menyetor uang laci adalah orang yang
  -- bertanggung jawab atas selisihnya, jadi ini bukan sekadar audit.
  created_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_cash_deposits_resto on cash_deposits(resto_id);

alter table cash_deposits enable row level security;

-- Kasir memegang uang lacinya, jadi merekalah yang menyetor. Finance dan
-- admin ikut melihat, tapi pembatalan setoran hanya untuk mereka —
-- menghapus setoran menulis ulang jurnal.
drop policy if exists "cash_deposits: staff read" on cash_deposits;
create policy "cash_deposits: staff read" on cash_deposits
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "cash_deposits: staff insert" on cash_deposits;
create policy "cash_deposits: staff insert" on cash_deposits
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "cash_deposits: finance delete" on cash_deposits;
create policy "cash_deposits: finance delete" on cash_deposits
  for delete using (is_resto_employee(resto_id, array['admin', 'finance']));

-- ── 2. Petty cash boleh bersumber dari saldo tunai ───────────────────
-- Nilai lama 'income_withdrawal' dipertahankan apa adanya dan kini
-- dibaca sebagai "dari Non Cash"; menulis ulang baris lama akan
-- memalsukan riwayat yang saat itu memang belum membedakan keduanya.
alter table petty_cash_entries drop constraint if exists petty_cash_entries_source_check;
alter table petty_cash_entries add constraint petty_cash_entries_source_check
  check (source in ('manual', 'income_withdrawal', 'cash_withdrawal'));

-- ── 3. Jurnal setoran: GL Cash keluar, GL Total Saldo masuk ──────────
alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

create or replace function log_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_gl record;
  v_total_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  -- Uang tunai meninggalkan laci → kredit GL Cash.
  select * into v_cash_gl from _gl_account_for(new.resto_id, 'cash');
  if v_cash_gl.gl_code is not null and v_cash_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_cash_gl.gl_code, v_cash_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', 'Setor tunai #' || v_ref
    );
  end if;

  -- Dan mendarat di rekening → debit GL Total Saldo.
  select * into v_total_gl from _gl_account_for(new.resto_id, 'total_balance');
  if v_total_gl.gl_code is not null and v_total_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_total_gl.gl_code, v_total_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Terima setoran tunai #' || v_ref
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_cash_deposit_journal on cash_deposits;
create trigger trg_log_cash_deposit_journal
  after insert on cash_deposits
  for each row execute function log_cash_deposit_journal();

-- Pembatalan setoran dibalik, bukan dihapus — sama seperti pengeluaran
-- dan petty cash, supaya riwayat jurnalnya utuh.
create or replace function reverse_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform _reverse_journal_for('cash_deposit', old.id::text, 'Pembatalan setoran tunai');
  return old;
end;
$$;

drop trigger if exists trg_reverse_cash_deposit_journal on cash_deposits;
create trigger trg_reverse_cash_deposit_journal
  before delete on cash_deposits
  for each row execute function reverse_cash_deposit_journal();

-- ── 4. Jurnal petty cash: sumber tunai memotong GL Cash ──────────────
-- Sebelumnya hanya ada satu lawan akun ('income_aggregate'). Sekarang
-- sumbernya menentukan akun mana yang berkurang, supaya saldo tunai di
-- laci ikut turun saat dipakai mengisi petty cash.
create or replace function log_petty_cash_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petty_gl record;
  v_source_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_label text;
begin
  v_label := case new.source
    when 'cash_withdrawal' then 'Saldo Cash'
    when 'income_withdrawal' then 'Saldo Non Cash'
    else null
  end;

  -- Petty cash adalah aset: bertambah → debit.
  select * into v_petty_gl from _gl_account_for(new.resto_id, 'petty_cash');
  if v_petty_gl.gl_code is not null and v_petty_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_petty_gl.gl_code, v_petty_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'debit',
      coalesce('Top Up Petty Cash dari ' || v_label, 'Top Up Petty Cash (Manual)')
    );
  end if;

  -- Top up manual adalah modal dari luar, jadi tidak punya lawan akun.
  if v_label is not null then
    select * into v_source_gl from _gl_account_for(
      new.resto_id,
      case when new.source = 'cash_withdrawal' then 'cash' else 'income_aggregate' end
    );
    if v_source_gl.gl_code is not null and v_source_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_source_gl.gl_code, v_source_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit', 'Dipindah ke Petty Cash'
      );
    end if;
  end if;

  return new;
end;
$$;

-- Tidak ada perubahan hak baca `orders`: policy "orders: public read"
-- yang sudah ada sudah cukup untuk layar Setor Saldo menghitung berapa
-- tunai yang seharusnya ada di laci.
