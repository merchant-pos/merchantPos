-- KaataGo — voucher untuk pelanggan, dananya benar-benar berpindah.
--
-- Jalankan SETELAH product_toppings.sql. Aman diulang.
--
-- Voucher di sini bukan sekadar aturan potongan seperti diskon resto.
-- Ia dompet: Super Admin mengalokasikan sejumlah uang, uang itu berhenti
-- jadi saldo bebas, dan baru kembali kalau vouchernya hangus. Tiap
-- perpindahannya tercatat.
--
-- ── Empat keadaan uangnya ────────────────────────────────────────────
--
--   1. Diterbitkan   GL Total Saldo  →  GL Voucher
--      Super Admin mengalokasikan Rp 1.000.000 jadi 10 voucher @100.000.
--
--   2. Ditebus       GL Voucher      →  GL Voucher Redeem
--      Pelanggan memasukkan kodenya. Yang ke-11 ditolak: kuotanya habis.
--
--   3. Dipakai       GL Voucher Redeem  →  GL resto
--      Dipakai membayar di resto. Restonya menerima uangnya dari kami,
--      bukan kehilangan pendapatan.
--
--   4. Hangus        GL Voucher / Redeem  →  GL Total Saldo
--      Tidak ditebus sampai kedaluwarsa, atau ditebus tapi tidak dipakai.
--
-- Kenapa serepot ini, dan bukan sekadar mengurangi tagihan: tanpa
-- perpindahan yang tercatat, pertanyaan "berapa uang kami yang sedang
-- menggantung di tangan pelanggan" tidak punya jawaban di mana pun. Itu
-- uang yang sudah dijanjikan keluar tapi belum keluar, dan saldo yang
-- menghitungnya sebagai milik sendiri akan menyesatkan tiap keputusan
-- yang memakainya.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Bagan akun voucher
-- ─────────────────────────────────────────────────────────────────────
--
-- Sederet dengan GL Diskon Lain (1100072): keduanya sama-sama uang yang
-- diberikan, bukan uang yang dibelanjakan.

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values
  ('kaatago', 'voucher',        '1100073', 'GL Voucher'),
  ('kaatago', 'voucher_redeem', '1100074', 'GL Voucher Redeem')
on conflict (resto_id, payment_method) do nothing;

-- Nomor lama dari rancangan sebelumnya dipindahkan, bukan ditinggalkan
-- jadi akun kembar yang tidak pernah dipakai lagi.
update gl_accounts
set gl_code = '1100073', gl_name = 'GL Voucher'
where resto_id = 'kaatago' and payment_method = 'voucher'
  and gl_code = '1100080';

-- ─────────────────────────────────────────────────────────────────────
-- Batch voucher
-- ─────────────────────────────────────────────────────────────────────

create table if not exists vouchers (
  id text primary key,

  -- Satu kode untuk seluruh batch, dan sengaja begitu: kodenya diumumkan
  -- ke banyak orang sekaligus lewat pengumuman, dan kode yang berbeda per
  -- orang tidak bisa diumumkan.
  code text not null unique,
  name text not null,

  -- Yang dialokasikan, dan dipecah jadi berapa.
  total_amount bigint not null check (total_amount > 0),
  quantity integer not null check (quantity > 0),

  -- Nilai tiap voucher. Disimpan, bukan dihitung ulang tiap dibaca:
  -- total dibagi jumlah bisa menyisakan pecahan, dan pembagian yang
  -- diulang di dua tempat akan membulatkannya berbeda.
  amount bigint not null check (amount > 0),

  expires_on date not null,

  min_purchase bigint not null default 0 check (min_purchase >= 0),

  -- Resto tempat voucher ini bisa dipakai. Kosong berarti semua resto.
  resto_ids jsonb not null default '[]'::jsonb,

  active boolean not null default true,

  -- Sisa yang belum ditebus sudah dikembalikan ke saldo.
  settled_at timestamptz,

  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists idx_vouchers_kadaluarsa
  on vouchers (expires_on) where settled_at is null;

-- ─────────────────────────────────────────────────────────────────────
-- Voucher yang sudah ditebus pelanggan
-- ─────────────────────────────────────────────────────────────────────

create table if not exists voucher_claims (
  id text primary key,
  voucher_id text not null references vouchers (id) on delete cascade,

  -- Email pelanggan. Voucher menempel pada orang, bukan pada perangkat:
  -- yang menebusnya di HP lama harus tetap menemukannya di HP baru.
  customer_label text not null,
  amount bigint not null check (amount > 0),

  -- claimed → ditebus, belum dipakai
  -- used    → sudah dipakai membayar
  -- expired → kedaluwarsa tanpa dipakai, dananya sudah dikembalikan
  status text not null default 'claimed'
    check (status in ('claimed', 'used', 'expired')),

  order_id uuid,
  resto_id text references restaurants (id) on delete set null,
  used_at timestamptz,
  expired_at timestamptz,
  created_at timestamptz not null default now(),

  -- Satu orang satu voucher per batch. Tanpa ini, orang pertama yang
  -- membaca pengumumannya bisa menebus kesepuluhnya sekaligus.
  constraint voucher_claims_sekali unique (voucher_id, customer_label)
);

create index if not exists idx_claims_pemilik
  on voucher_claims (customer_label, status);
create index if not exists idx_claims_voucher
  on voucher_claims (voucher_id);

alter table orders add column if not exists voucher_claim_id text;
alter table orders add column if not exists voucher_code text;
alter table orders add column if not exists voucher_amount bigint not null default 0;

-- Kolom dari rancangan sebelumnya, dilepas dari pemakaian tapi tidak
-- dibuang: aplikasi versi lama masih menulisinya, dan kolom yang hilang
-- membuat pesanannya gagal tersimpan sama sekali.
alter table orders add column if not exists voucher_id text;

-- ─────────────────────────────────────────────────────────────────────
-- Alat bantu jurnal
-- ─────────────────────────────────────────────────────────────────────

create or replace function _jurnal_kaatago(
  p_method text,
  p_ref_id text,
  p_amount bigint,
  p_type text,
  p_desc text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
begin
  select * into v_gl from _gl_account_for('kaatago', p_method);
  if v_gl.gl_code is null or v_gl.gl_code = '' then
    return;
  end if;
  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    'kaatago',
    (v_now at time zone 'Asia/Jakarta')::date,
    (v_now at time zone 'Asia/Jakarta')::time,
    v_gl.gl_code, v_gl.gl_name,
    'voucher', p_ref_id, p_amount, p_type, p_desc
  );
end;
$$;

alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

-- ─────────────────────────────────────────────────────────────────────
-- 1. Menerbitkan batch
-- ─────────────────────────────────────────────────────────────────────

create or replace function generate_voucher_batch(
  p_code text,
  p_name text,
  p_total bigint,
  p_quantity integer,
  p_expires_on date,
  p_min_purchase bigint default 0,
  p_resto_ids jsonb default '[]'::jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_amount bigint;
  v_code text := upper(trim(p_code));
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menerbitkan voucher';
  end if;

  if p_quantity <= 0 or p_total <= 0 then
    raise exception 'Nominal dan jumlah voucher harus lebih dari nol';
  end if;

  v_amount := p_total / p_quantity;
  if v_amount <= 0 then
    raise exception 'Nominal per voucher jadi nol — kurangi jumlahnya';
  end if;

  if p_expires_on <= current_date then
    raise exception 'Tanggal kedaluwarsa minimal besok';
  end if;

  v_id := 'VC-' || upper(substr(md5(v_code || now()::text), 1, 10));

  insert into vouchers (
    id, code, name, total_amount, quantity, amount, expires_on,
    min_purchase, resto_ids, created_by
  ) values (
    v_id, v_code, p_name,
    -- Yang dicatat keluar adalah yang benar-benar bisa ditebus. Sisa
    -- pembagian tidak pernah jadi voucher, jadi mencatatnya sebagai uang
    -- yang keluar berarti saldo berkurang untuk sesuatu yang tidak ada.
    v_amount * p_quantity,
    p_quantity, v_amount, p_expires_on,
    p_min_purchase, coalesce(p_resto_ids, '[]'::jsonb),
    auth.jwt() ->> 'email'
  );

  -- Uang berpindah dari saldo bebas ke kantong voucher.
  perform _jurnal_kaatago('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_kaatago('voucher', v_id, v_amount * p_quantity,
    'credit', 'Alokasi voucher ' || v_code);

  return v_id;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Menebus
-- ─────────────────────────────────────────────────────────────────────

create or replace function claim_voucher(p_code text)
returns table (claim_id text, amount bigint, reason text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v vouchers;
  v_email text := auth.jwt() ->> 'email';
  v_terpakai integer;
  v_id text;
begin
  if coalesce(v_email, '') = '' then
    return query select null::text, 0::bigint,
      'Masuk dulu dengan akun supaya vouchernya tersimpan';
    return;
  end if;

  select * into v from vouchers where vouchers.code = upper(trim(p_code));

  if v.id is null then
    return query select null::text, 0::bigint, 'Kode voucher tidak ditemukan';
    return;
  end if;
  if not v.active then
    return query select null::text, 0::bigint, 'Voucher ini sudah ditutup';
    return;
  end if;
  if v.expires_on < current_date then
    return query select null::text, 0::bigint, 'Voucher ini sudah kedaluwarsa';
    return;
  end if;

  if exists (
    select 1 from voucher_claims
    where voucher_id = v.id and customer_label = v_email
  ) then
    return query select null::text, 0::bigint, 'Voucher ini sudah kamu tebus';
    return;
  end if;

  -- Dihitung di dalam transaksi yang sama dengan penyisipannya, dan
  -- baris uniknya jadi penjaga terakhir: dua orang yang menekan tombol
  -- di detik yang sama tidak boleh sama-sama lolos sebagai penebus
  -- terakhir.
  select count(*) into v_terpakai
  from voucher_claims where voucher_id = v.id;

  if v_terpakai >= v.quantity then
    return query select null::text, 0::bigint, 'Voucher ini sudah habis';
    return;
  end if;

  v_id := 'VCL-' || upper(substr(md5(v.id || v_email), 1, 12));

  insert into voucher_claims (id, voucher_id, customer_label, amount)
  values (v_id, v.id, v_email, v.amount);

  perform _jurnal_kaatago('voucher', v_id, v.amount,
    'debit', 'Ditebus ' || v.code || ' — ' || v_email);
  perform _jurnal_kaatago('voucher_redeem', v_id, v.amount,
    'credit', 'Voucher ditebus ' || v.code);

  return query select v_id, v.amount, null::text;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Dipakai membayar
-- ─────────────────────────────────────────────────────────────────────
--
-- Lewat pemicu pada pesanan, bukan panggilan terpisah: panggilan
-- terpisah bisa gagal atau tidak pernah dikirim, dan yang tertinggal
-- adalah voucher yang memotong tagihan tanpa pernah berpindah akun.

create or replace function log_voucher_use()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim voucher_claims;
  v_gl record;
  v_now timestamptz := now();
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  if new.voucher_claim_id is null or coalesce(new.voucher_amount, 0) <= 0 then
    return new;
  end if;

  select * into v_claim from voucher_claims where id = new.voucher_claim_id;
  if v_claim.id is null or v_claim.status <> 'claimed' then
    return new;
  end if;

  update voucher_claims
  set status = 'used', order_id = new.id, resto_id = new.resto_id,
      used_at = v_now
  where id = v_claim.id;

  -- Uangnya keluar dari kantong voucher yang sudah ditebus.
  perform _jurnal_kaatago('voucher_redeem', v_claim.id, new.voucher_amount,
    'debit', 'Voucher dipakai di pesanan #' || v_ref);

  -- Dan masuk ke resto: bagi mereka ini uang masuk, bukan pendapatan
  -- yang hilang. Restonya tidak menanggung promo yang tidak dia buat.
  select * into v_gl from _gl_account_for(new.resto_id, 'transfer');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id,
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'voucher', v_claim.id, new.voucher_amount, 'credit',
      'Voucher KaataGo ' || coalesce(new.voucher_code, '') ||
        ' — pesanan #' || v_ref
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_voucher_redemption on orders;
drop trigger if exists trg_log_voucher_use on orders;
create trigger trg_log_voucher_use
  after insert on orders
  for each row execute function log_voucher_use();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Hangus — dananya pulang
-- ─────────────────────────────────────────────────────────────────────

create or replace function expire_vouchers()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  c record;
  v record;
  v_sisa bigint;
begin
  -- Yang sudah ditebus tapi tidak pernah dipakai.
  for c in
    select cl.* from voucher_claims cl
    join vouchers vc on vc.id = cl.voucher_id
    where cl.status = 'claimed' and vc.expires_on < current_date
  loop
    update voucher_claims
    set status = 'expired', expired_at = now()
    where id = c.id;

    perform _jurnal_kaatago('voucher_redeem', c.id, c.amount,
      'debit', 'Voucher hangus tanpa dipakai');
    perform _jurnal_kaatago('total_balance', c.id, c.amount,
      'credit', 'Dana voucher hangus kembali ke saldo');
    v_count := v_count + 1;
  end loop;

  -- Sisa yang tidak pernah ditebus sama sekali. Dihitung sekali per
  -- batch — `settled_at` yang menjaganya, bukan ingatan penjadwal.
  for v in
    select * from vouchers
    where expires_on < current_date and settled_at is null
  loop
    select v.amount * (v.quantity - count(*)) into v_sisa
    from voucher_claims where voucher_id = v.id;

    if v_sisa > 0 then
      perform _jurnal_kaatago('voucher', v.id, v_sisa,
        'debit', 'Sisa voucher ' || v.code || ' tidak ditebus');
      perform _jurnal_kaatago('total_balance', v.id, v_sisa,
        'credit', 'Sisa voucher ' || v.code || ' kembali ke saldo');
    end if;

    update vouchers set settled_at = now() where id = v.id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

select cron.unschedule('expire-vouchers')
where exists (select 1 from cron.job where jobname = 'expire-vouchers');

-- Sekali sehari lewat tengah malam WIB.
select cron.schedule('expire-vouchers', '10 17 * * *',
  $$select expire_vouchers();$$);

-- ─────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────

alter table vouchers enable row level security;
alter table voucher_claims enable row level security;

-- Batch-nya dibaca siapa saja: pelanggan perlu melihat nominal dan masa
-- berlakunya sebelum menebus.
drop policy if exists "vouchers: public read" on vouchers;
create policy "vouchers: public read" on vouchers for select using (true);

drop policy if exists "vouchers: super admin write" on vouchers;
create policy "vouchers: super admin write" on vouchers
  for all using (is_super_admin()) with check (is_super_admin());

-- Penebusan hanya terlihat oleh pemiliknya, Super Admin, dan resto tempat
-- ia dipakai.
drop policy if exists "voucher_claims: read" on voucher_claims;
create policy "voucher_claims: read" on voucher_claims
  for select using (
    customer_label = auth.jwt() ->> 'email'
    or is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

-- Tidak ada kebijakan tulis untuk siapa pun. Menebus lewat RPC, memakai
-- lewat pemicu — tangan yang bisa menulis langsung ke sini adalah tangan
-- yang bisa membuat voucher dari udara.

commit;
