-- KaataGo — setoran & top up petty cash berjenjang, GL Suspense, dan
-- kotak masuk pengumuman.
--
-- SATU file untuk seluruh rilis ini; menggantikan deposit_approval.sql
-- dan inbox_and_petty_approval.sql yang sebelumnya terpisah. Aman
-- dijalankan berulang kali.
--
-- Alurnya:
--   Kasir/Admin mencatat  → status 'pending', uang ditampung di GL
--                           Suspense (setoran dan petty cash punya
--                           akun suspense masing-masing).
--   Finance mengonfirmasi → dipindah dari suspense ke akun tujuannya.
--   Finance menolak       → dikembalikan ke akun asalnya.
--
-- Mengonfirmasi hanya milik Finance (dan Owner, yang lolos setiap
-- pemeriksaan peran). Admin disamakan dengan kasir: keduanya mengajukan,
-- bukan memutuskan — persetujuan atas permintaan sendiri tidak berarti
-- apa-apa.

-- ARAH JURNAL. Aplikasi ini memakai satu kesepakatan di seluruh
-- layarnya: **kredit = uang masuk ke akun itu, debit = uang keluar**.
-- Penjualan mengkredit akun pemasukan, dan panah di layar Jurnal GL
-- mengikuti aturan yang sama.
--
-- Kesepakatan akuntansi aset yang biasa (aset bertambah = debit) adalah
-- kebalikannya, dan sempat terpakai di sini — akibatnya setoran tunai
-- menambah sisi yang sama dengan penjualan alih-alih menguranginya, dan
-- di layar terbaca seolah GL Suspense yang mengeluarkan uang.

begin;


-- ── 1. Status persetujuan ────────────────────────────────────────────
alter table cash_deposits add column if not exists status text not null default 'pending';
alter table cash_deposits add column if not exists reviewed_by text;
alter table cash_deposits add column if not exists reviewed_at timestamptz;
alter table cash_deposits add column if not exists review_note text;

alter table cash_deposits drop constraint if exists cash_deposits_status_check;
alter table cash_deposits add constraint cash_deposits_status_check
  check (status in ('pending', 'approved', 'rejected'));

-- Setoran yang sudah terlanjur tercatat sebelum alur ini ada memang sudah
-- masuk GL Total Saldo, jadi statusnya disamakan dengan 'approved' —
-- menandainya 'pending' akan meminta Finance menyetujui sesuatu yang
-- uangnya sudah lama diakui.
update cash_deposits set status = 'approved' where status = 'pending' and created_at < now() - interval '1 second';

create index if not exists idx_cash_deposits_status on cash_deposits(resto_id, status);

-- ── 2. GL Suspense ───────────────────────────────────────────────────
-- Batasan payment_method dipasang sekali saja, di bagian GL Suspense
-- Petty Cash di bawah — daftarnya sudah memuat 'suspense' sekaligus
-- 'suspense_petty'. Memasang daftar yang lebih pendek lebih dulu membuat
-- file ini menolak dirinya sendiri saat dijalankan ulang, karena baris
-- 'suspense_petty' yang dibuatnya sudah ada.

-- ── 3. Jurnal saat setoran diajukan ──────────────────────────────────
-- Uang meninggalkan laci, tapi berhenti dulu di Suspense.
create or replace function log_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_gl record;
  v_suspense_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  select * into v_cash_gl from _gl_account_for(new.resto_id, 'cash');
  if v_cash_gl.gl_code is not null and v_cash_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_cash_gl.gl_code, v_cash_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Setor tunai #' || v_ref || ' (menunggu approval)'
    );
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', 'Titipan setoran #' || v_ref
    );
  end if;

  return new;
end;
$$;

-- ── 4. Jurnal saat disetujui / ditolak ───────────────────────────────
-- Dipicu oleh perubahan status, dan hanya untuk baris yang berubah, jadi
-- setoran lain yang masih menunggu tidak ikut terbawa.
create or replace function log_cash_deposit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suspense_gl record;
  v_target_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Titipan setoran #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    v_target := 'total_balance';
    v_note := 'Setoran #' || v_ref || ' disetujui';
  else
    -- Ditolak: uangnya kembali menjadi tanggung jawab laci kasir.
    v_target := 'cash';
    v_note := 'Setoran #' || v_ref || ' ditolak, kembali ke kas';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', v_note
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_cash_deposit_review on cash_deposits;
create trigger trg_log_cash_deposit_review
  after update of status on cash_deposits
  for each row execute function log_cash_deposit_review();

-- ── 5. Hanya Finance/Admin/Owner yang boleh menyetujui ───────────────
-- Kasir dan Admin tetap boleh menambah setoran, tapi tidak boleh
-- mengubah statusnya sendiri. Owner ikut lolos lewat klausa 'owner' di
-- dalam is_resto_employee.
drop policy if exists "cash_deposits: finance review" on cash_deposits;
create policy "cash_deposits: finance review" on cash_deposits
  for update
  using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));


-- ─────────────────────────────────────────────────────────────────────
-- 1. Rekening tujuan pada setoran tunai
-- ─────────────────────────────────────────────────────────────────────
-- Tanpa ini, "sudah disetor" tidak menyebut ke mana. Saat Finance
-- memeriksa mutasi bank, tidak ada yang bisa dicocokkan selain nominal.
alter table cash_deposits add column if not exists bank_name text;
alter table cash_deposits add column if not exists account_number text;
alter table cash_deposits add column if not exists account_holder text;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Approval top up petty cash
-- ─────────────────────────────────────────────────────────────────────
-- Kasir kini boleh mengajukan top up, tapi uangnya belum diakui masuk
-- petty cash sampai Finance menyetujui. Selama menunggu, nilainya
-- ditampung di GL Suspense Petty Cash — sengaja terpisah dari suspense
-- setoran bank, supaya Finance bisa melihat berapa yang tertahan pada
-- masing-masing alur tanpa harus memilahnya satu per satu.
alter table petty_cash_entries add column if not exists status text not null default 'approved';
alter table petty_cash_entries add column if not exists requested_by text;
alter table petty_cash_entries add column if not exists reviewed_by text;
alter table petty_cash_entries add column if not exists reviewed_at timestamptz;
alter table petty_cash_entries add column if not exists review_note text;

alter table petty_cash_entries drop constraint if exists petty_cash_entries_status_check;
alter table petty_cash_entries add constraint petty_cash_entries_status_check
  check (status in ('pending', 'approved', 'rejected'));

-- Baris lama dibuat oleh Finance sendiri, jadi memang sudah setara
-- disetujui — default kolomnya 'approved' supaya riwayat tidak
-- tiba-tiba minta persetujuan ulang.
create index if not exists idx_petty_cash_status on petty_cash_entries(resto_id, status);

-- Kasir boleh mengajukan dan melihat, tapi tidak boleh menyetujui —
-- persetujuan atas permintaannya sendiri tidak berarti apa-apa.
drop policy if exists "petty_cash_entries: kasir request" on petty_cash_entries;
create policy "petty_cash_entries: kasir request" on petty_cash_entries
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "petty_cash_entries: staff read" on petty_cash_entries;
create policy "petty_cash_entries: staff read" on petty_cash_entries
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

-- ─────────────────────────────────────────────────────────────────────
-- 3. GL Suspense Petty Cash
-- ─────────────────────────────────────────────────────────────────────
-- Daftarnya sengaja sama persis di semua berkas yang menyentuh batasan
-- ini, bukan hanya sepanjang yang dibutuhkan berkas ini sendiri.
--
-- Sebelumnya tiap berkas menuliskan daftar sepanjang zamannya, dan
-- itu berjalan baik tepat satu kali — saat dijalankan berurutan pada
-- database kosong. Menjalankan ulang berkas yang lebih tua sesudah
-- yang lebih baru berarti menyempitkan daftarnya lagi, dan barisan
-- akun yang terlanjur dibuat berkas yang lebih baru langsung
-- melanggarnya:
--
--   check constraint "gl_accounts_payment_method_check" is violated
--   by some row
--
-- Padahal tidak ada satu pun data yang salah. Yang salah adalah
-- batasannya yang mundur. Satu daftar untuk semua menutup itu.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- ─────────────────────────────────────────────────────────────────────
-- 4. Jurnal petty cash mengikuti statusnya
-- ─────────────────────────────────────────────────────────────────────
-- Saat diajukan: sumbernya berkurang, nilainya mengendap di Suspense
-- Petty Cash. Saat disetujui: berpindah dari suspense ke petty cash.
-- Saat ditolak: dikembalikan ke sumbernya semula.
create or replace function log_petty_cash_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petty_gl record;
  v_source_gl record;
  v_suspense_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_label text;
begin
  v_label := case new.source
    when 'cash_withdrawal' then 'Saldo Cash'
    when 'income_withdrawal' then 'Saldo Non Cash'
    else null
  end;

  -- Sumbernya berkurang begitu diajukan, apa pun statusnya: uangnya
  -- memang sudah diambil dari sana. Top up manual adalah modal dari
  -- luar, jadi tidak punya lawan akun.
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
        new.amount, 'debit', 'Dipindah ke Petty Cash #' || v_ref
      );
    end if;
  end if;

  if new.status = 'pending' then
    -- Menunggu persetujuan: berhenti dulu di suspense.
    select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense_petty');
    if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit', 'Titipan top up petty cash #' || v_ref
      );
    end if;
  else
    -- Dibuat langsung oleh Finance: tidak perlu singgah di suspense.
    select * into v_petty_gl from _gl_account_for(new.resto_id, 'petty_cash');
    if v_petty_gl.gl_code is not null and v_petty_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_petty_gl.gl_code, v_petty_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit',
        coalesce('Top Up Petty Cash dari ' || v_label, 'Top Up Petty Cash (Manual)')
      );
    end if;
  end if;

  return new;
end;
$$;

create or replace function log_petty_cash_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suspense_gl record;
  v_target_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense_petty');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'debit', 'Titipan top up #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    v_target := 'petty_cash';
    v_note := 'Top up petty cash #' || v_ref || ' disetujui';
  else
    -- Ditolak: uangnya kembali ke sumber asalnya.
    v_target := case when new.source = 'cash_withdrawal' then 'cash' else 'income_aggregate' end;
    v_note := 'Top up petty cash #' || v_ref || ' ditolak';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'credit', v_note
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_petty_cash_review on petty_cash_entries;
create trigger trg_log_petty_cash_review
  after update of status on petty_cash_entries
  for each row execute function log_petty_cash_review();

drop policy if exists "petty_cash_entries: finance review" on petty_cash_entries;
create policy "petty_cash_entries: finance review" on petty_cash_entries
  for update
  using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));

-- ─────────────────────────────────────────────────────────────────────
-- 5. Inbox pengumuman
-- ─────────────────────────────────────────────────────────────────────
-- Pengumumannya disimpan sekali, bukan disalin ke tiap penerima. Menyalin
-- berarti orang yang mendaftar besok tidak akan pernah melihat
-- pengumuman hari ini, dan setiap blast menambah ribuan baris kembar.
-- Yang per orang hanyalah keadaannya: sudah dibaca, atau sudah dihapus.
create table if not exists app_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  -- Versi aplikasi yang diumumkan. Dipakai layar tamu untuk tahu apakah
  -- aplikasinya sudah usang, tanpa perlu punya akun.
  version text,
  download_url text,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists idx_announcements_created on app_announcements(created_at desc);

alter table app_announcements enable row level security;

-- Boleh dibaca siapa saja, termasuk tamu: pemberitahuan versi baru justru
-- paling dibutuhkan orang yang belum punya akun.
drop policy if exists "announcements: public read" on app_announcements;
create policy "announcements: public read" on app_announcements
  for select using (true);

drop policy if exists "announcements: super_admin write" on app_announcements;
create policy "announcements: super_admin write" on app_announcements
  for all using (is_super_admin()) with check (is_super_admin());

create table if not exists inbox_states (
  email text not null,
  announcement_id uuid not null references app_announcements(id) on delete cascade,
  read_at timestamptz,
  deleted_at timestamptz,
  primary key (email, announcement_id)
);

alter table inbox_states enable row level security;

-- Setiap orang hanya menyentuh barisnya sendiri. Inbox milik orang lain
-- bukan urusan siapa pun, termasuk admin.
drop policy if exists "inbox_states: own rows" on inbox_states;
create policy "inbox_states: own rows" on inbox_states
  for all
  using (email = auth.jwt()->>'email')
  with check (email = auth.jwt()->>'email');

-- ─────────────────────────────────────────────────────────────────────
-- 6. Titik lokasi resto
-- ─────────────────────────────────────────────────────────────────────
-- Alamat berupa teks cukup untuk dicetak di struk, tapi tidak cukup
-- untuk mengantar orang ke sana. Koordinatnya disimpan terpisah supaya
-- alamat tetap bisa disunting sedetail yang dibutuhkan ("ruko blok C
-- no. 4") tanpa merusak titik petanya.
alter table restaurants add column if not exists latitude double precision;
alter table restaurants add column if not exists longitude double precision;

-- ─────────────────────────────────────────────────────────────────────
-- 7. Membetulkan baris jurnal yang terlanjur terbalik
-- ─────────────────────────────────────────────────────────────────────
-- Setoran dan top up petty cash yang sudah tercatat sebelum perbaikan di
-- atas memakai arah yang salah. Barisnya tidak dihapus — riwayat jurnal
-- tidak boleh hilang — hanya arahnya yang dibalik.
--
-- Dijaga supaya hanya berjalan sekali. Menjalankannya dua kali akan
-- mengembalikan keadaan yang justru sedang diperbaiki, dan file ini
-- memang dirancang untuk boleh dijalankan berulang kali.
create table if not exists applied_migrations (
  name text primary key,
  applied_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from applied_migrations where name = 'flip_transfer_journal_direction') then
    update gl_journal_entries
       set entry_type = case entry_type when 'debit' then 'credit' else 'debit' end
     where reference_type in ('cash_deposit', 'petty_cash');

    insert into applied_migrations (name) values ('flip_transfer_journal_direction');
  end if;
end $$;


commit;
