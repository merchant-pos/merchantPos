-- KaataGo — GL Selisih Kasir, dan pelunasannya.
--
-- Jalankan SETELAH cashier_shift.sql dan default_gl_accounts.sql.
-- Aman diulang.
--
-- Sampai sekarang selisih shift cuma tercatat di barisnya sendiri. Ia
-- terlihat di riwayat, lalu berhenti di situ — tidak memotong GL mana
-- pun, tidak ditagih kepada siapa pun, dan Saldo Cash tetap menyebut
-- angka yang lebih besar daripada uang yang benar-benar ada di laci.
-- Fitur yang memperlihatkan selisih tapi tidak menindaklanjutinya lebih
-- berbahaya daripada tidak ada sama sekali: orang jadi mengira sudah
-- tertangani.
--
-- Selisih kurang sekarang jadi **outstanding** atas nama kasir yang
-- memegang lacinya, dan tetap terbuka sampai dilunasi dengan uang tunai.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Akunnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Nomornya di rentang 21xxxxx bersama Suspense, bukan 195xxxx bersama
-- pemasukan. Selisih kurang bukan penjualan dan bukan biaya — ia uang
-- yang sedang ditagihkan, dan tempatnya di sisi titipan sampai jelas
-- jadi apa.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

-- Untuk resto yang sudah ada.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'cash_variance', '2100003', 'GL Selisih Kasir'
from restaurants r
where coalesce(r.is_platform, false) = false
on conflict (resto_id, payment_method) do nothing;

-- Dan untuk resto yang dibuat sesudah ini.
create or replace function _default_gl_accounts()
returns table (payment_method text, gl_code text, gl_name text)
language sql
immutable
as $$
  values
    -- Pemasukan
    ('cash',             '1950001', 'GL Kas Tunai'),
    ('qris',             '1950002', 'GL Penerimaan QRIS'),
    ('transfer',         '1950003', 'GL Penerimaan Transfer'),
    ('income_aggregate', '1950000', 'GL Pemasukan'),
    -- Pajak & service
    ('ppn',              '1960001', 'GL PPN Keluaran'),
    ('service',          '1960002', 'GL Biaya Service'),
    -- Petty cash
    ('petty_cash',       '1980001', 'GL Petty Cash'),
    -- Total saldo
    ('total_balance',    '1990001', 'GL Total Saldo'),
    -- Suspense — titipan yang belum diakui masuk ke mana pun
    ('suspense',         '2100001', 'GL Suspense Setoran'),
    ('suspense_petty',   '2100002', 'GL Suspense Petty Cash'),
    ('cash_variance',    '2100003', 'GL Selisih Kasir'),
    -- Payment gateway & diskon
    ('gateway_fee',      '2200001', 'GL Biaya Payment Gateway'),
    ('discount',         '2200002', 'GL Diskon Penjualan');
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Outstanding-nya
-- ─────────────────────────────────────────────────────────────────────

create table if not exists cash_variances (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  -- Satu shift paling banyak melahirkan satu tagihan.
  shift_id uuid not null unique
    references cashier_shifts (id) on delete cascade,

  -- Siapa yang memegang laci saat selisihnya terjadi. Disalin, bukan
  -- dibaca ulang dari shiftnya — tagihan yang berganti nama penanggung
  -- jawab adalah tagihan yang tidak bisa ditagihkan.
  employee_email text not null,
  employee_name text,

  -- Selalu positif: sebesar itulah uang yang kurang.
  amount bigint not null check (amount > 0),

  status text not null default 'open' check (status in ('open', 'settled')),

  note text,

  created_at timestamptz not null default now(),
  settled_at timestamptz,
  settled_by text,
  settle_note text
);

create index if not exists cash_variances_resto_idx
  on cash_variances (resto_id, status, created_at desc);

alter table cash_variances enable row level security;

-- Dibaca seluruh pegawai merchant, termasuk kasir.
--
-- Kasir berhak melihat tagihan atas namanya sendiri. Tagihan yang hanya
-- bisa dilihat atasannya adalah tuduhan yang tidak bisa dijawab.
drop policy if exists "cash_variances: read" on cash_variances;
create policy "cash_variances: read" on cash_variances
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin', 'kasir'])
  );

-- Tidak ada policy tulis sama sekali. Tagihannya lahir dari pemicu saat
-- shift ditutup, dan lunasnya lewat fungsi di bawah — kasir tidak boleh
-- punya jalan menutup tagihan atas namanya sendiri.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Lahirnya tagihan, dan jurnalnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Ditulis pemicu, bukan oleh `close_shift`. Seluruh jurnal di KaataGo
-- lahir dari pemicu supaya tidak pernah ada jalan menutup shift tanpa
-- jurnalnya ikut tertulis — lihat catatan di gl_journal.sql.
--
-- Arah jurnalnya mengikuti kesepakatan yang sama dengan seluruh buku
-- ini: credit = uang masuk, debit = uang keluar.
--
--   Kurang  → debit GL Selisih Kasir. Uangnya memang tidak ada di laci.
--   Lebih   → credit GL Selisih Kasir, dan berhenti di situ.
--
-- Yang lebih tidak jadi tagihan. Tidak ada yang bisa ditagih dari uang
-- yang justru berlebih — yang perlu dilakukan menelusuri penjualan yang
-- belum diinput, dan itu pekerjaan Finance, bukan utang kasir.
create or replace function journal_cash_variance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_selisih bigint := coalesce(new.difference, 0);
  v_saat timestamptz := coalesce(new.closed_at, now());
  v_nama text := coalesce(nullif(btrim(coalesce(new.employee_name, '')), ''),
                          split_part(new.employee_email, '@', 1));
begin
  -- Hanya saat shiftnya baru ditutup, dan hanya kalau ada selisihnya.
  if new.closed_at is null or old.closed_at is not null then
    return new;
  end if;
  if v_selisih = 0 then
    return new;
  end if;

  select * into v_gl from _gl_account_for(new.resto_id, 'cash_variance');
  if v_gl.gl_code is null or v_gl.gl_code = '' then
    -- GL-nya belum dipetakan. Shiftnya tetap ditutup — menahan
    -- penutupan shift karena pemetaan GL berarti kasir tidak bisa
    -- pulang gara-gara urusan pembukuan.
    return new;
  end if;

  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    new.resto_id,
    (v_saat at time zone 'Asia/Jakarta')::date,
    (v_saat at time zone 'Asia/Jakarta')::time,
    v_gl.gl_code, v_gl.gl_name, 'cash_variance', new.id::text,
    abs(v_selisih),
    case when v_selisih < 0 then 'debit' else 'credit' end,
    case when v_selisih < 0
      then 'Selisih kurang shift ' || v_nama
      else 'Selisih lebih shift ' || v_nama
    end
  );

  if v_selisih < 0 then
    insert into cash_variances (
      resto_id, shift_id, employee_email, employee_name, amount, note)
    values (
      new.resto_id, new.id, new.employee_email, new.employee_name,
      abs(v_selisih), new.note)
    on conflict (shift_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_journal_cash_variance on cashier_shifts;
create trigger trg_journal_cash_variance
  after update of closed_at on cashier_shifts
  for each row execute function journal_cash_variance();

-- ─────────────────────────────────────────────────────────────────────
-- Bayar Selisih
-- ─────────────────────────────────────────────────────────────────────
--
-- Kasir menyerahkan uang tunai sebesar kekurangannya, dan uang itu masuk
-- kembali ke laci. Karena itu jurnalnya credit: uang masuk, dan GL
-- Selisih Kasir kembali nol untuk tagihan itu.
--
-- Yang boleh menekan tombolnya hanya Owner, Finance, dan Admin. Kasir
-- melihat tagihannya, tapi tidak menutup tagihan atas namanya sendiri —
-- kalau boleh, angka yang menilai seseorang bisa dihapus oleh orang itu
-- juga.
create or replace function settle_cash_variance(
  p_id uuid,
  p_note text default null)
returns cash_variances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row cash_variances;
  v_gl record;
  v_saat timestamptz := now();
  v_hasil cash_variances;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  select * into v_row from cash_variances where id = p_id;
  if v_row is null then
    raise exception 'Tagihan selisihnya tidak ditemukan.';
  end if;

  if not is_resto_employee(v_row.resto_id, array['owner', 'finance', 'admin']) then
    raise exception 'Hanya Owner, Finance, dan Admin yang boleh mencatat '
                    'pembayaran selisih.';
  end if;

  if v_row.status = 'settled' then
    raise exception 'Selisih ini sudah dilunasi.';
  end if;

  update cash_variances
     set status = 'settled',
         settled_at = v_saat,
         settled_by = v_email,
         settle_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id
  returning * into v_hasil;

  select * into v_gl from _gl_account_for(v_row.resto_id, 'cash_variance');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      v_row.resto_id,
      (v_saat at time zone 'Asia/Jakarta')::date,
      (v_saat at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name, 'cash_variance', v_row.id::text,
      v_row.amount, 'credit',
      'Pelunasan selisih kasir ' ||
        coalesce(nullif(btrim(coalesce(v_row.employee_name, '')), ''),
                 split_part(v_row.employee_email, '@', 1))
    );
  end if;

  return v_hasil;
end;
$$;

grant execute on function settle_cash_variance(uuid, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   -- Tagihan yang masih terbuka:
--   select employee_name, amount, created_at
--   from cash_variances where resto_id = '<resto_id>' and status = 'open';
--
--   -- Jurnalnya:
--   select entry_date, gl_name, entry_type, amount, description
--   from gl_journal_entries
--   where reference_type = 'cash_variance' order by entry_date desc;
