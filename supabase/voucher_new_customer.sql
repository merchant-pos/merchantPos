-- KaataGo — voucher khusus pengguna baru.
--
-- Jalankan SETELAH voucher_manage.sql. Aman dijalankan berulang kali.
--
-- Voucher promosi paling mahal adalah yang ditebus orang yang memang
-- sudah pasti memesan. Batasan ini membuat anggarannya jatuh ke orang
-- yang belum pernah mencoba sama sekali.

begin;

alter table vouchers
  add column if not exists new_customers_only boolean not null default false;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Siapa yang terhitung "pengguna baru"
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang belum pernah punya pesanan **terbayar** di resto mana pun.
--
-- Pesanan batal tidak dihitung: orang yang memesan lalu membatalkannya
-- belum pernah benar-benar memakai KaataGo, dan menutup pintu untuknya
-- justru menutup pintu bagi orang yang paling ingin dibujuk kembali.
--
-- Batasnya seluruh KaataGo, bukan per resto. Voucher ini promo KaataGo,
-- dan orang yang sudah rutin memesan di resto sebelah bukan pengguna
-- baru hanya karena belum pernah masuk resto ini.
create or replace function _pelanggan_baru(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from orders
    where customer_label = p_email
      and payment_status = 'paid'
  );
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Penebusan memeriksanya
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

  -- Diperiksa sebelum kuota. Orang yang tidak berhak menebusnya sama
  -- sekali tidak boleh menghabiskan jatah orang yang berhak — dan
  -- alasan penolakannya harus yang sebenarnya, bukan "sudah habis".
  if v.new_customers_only and not _pelanggan_baru(v_email) then
    return query select null::text, 0::bigint,
      'Voucher ini hanya untuk pengguna baru KaataGo';
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
-- Menerbitkannya
-- ─────────────────────────────────────────────────────────────────────

create or replace function generate_voucher_batch(
  p_code text,
  p_name text,
  p_total bigint,
  p_quantity integer,
  p_expires_on date,
  p_min_purchase bigint default 0,
  p_resto_ids jsonb default '[]'::jsonb,
  p_banner text default null,
  p_new_customers_only boolean default false
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
  v_nilai text;
  v_syarat text;
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
    min_purchase, resto_ids, banner_base64, new_customers_only, created_by
  ) values (
    v_id, v_code, p_name,
    -- Yang dicatat keluar adalah yang benar-benar bisa ditebus. Sisa
    -- pembagian tidak pernah jadi voucher, jadi mencatatnya sebagai uang
    -- yang keluar berarti saldo berkurang untuk sesuatu yang tidak ada.
    v_amount * p_quantity,
    p_quantity, v_amount, p_expires_on,
    p_min_purchase, coalesce(p_resto_ids, '[]'::jsonb),
    nullif(p_banner, ''), coalesce(p_new_customers_only, false),
    auth.jwt() ->> 'email'
  );

  perform _jurnal_kaatago('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_kaatago('voucher', v_id, v_amount * p_quantity,
    'credit', 'Alokasi voucher ' || v_code);

  v_nilai := 'Rp ' || to_char(v_amount, 'FM999G999G999G999');

  -- Syaratnya disebutkan di pengumumannya, bukan disimpan sampai orang
  -- menekan Tebus. Ditolak sesudah bersemangat lebih menjengkelkan
  -- daripada tahu sejak awal bahwa ini bukan untuk dirinya.
  v_syarat := case
    when coalesce(p_new_customers_only, false)
      then ' Khusus pengguna baru yang belum pernah memesan lewat KaataGo.'
    else '' end;

  insert into app_announcements (
    title, body, category, audience, image_base64, created_by
  ) values (
    'Voucher ' || v_nilai || ' dari KaataGo',
    'Buruan tebus, kuotanya cuma ' || p_quantity || ' dan siapa cepat dia dapat! ' ||
    'Kode voucher: ' || v_code || E'\n\n' ||
    'Tiap voucher bernilai ' || v_nilai ||
    case when p_min_purchase > 0
      then ', minimal belanja Rp ' || to_char(p_min_purchase, 'FM999G999G999G999')
      else '' end ||
    '. Berlaku sampai ' || to_char(p_expires_on, 'DD Mon YYYY') || '.' ||
    v_syarat || ' ' ||
    'Tebus di menu Voucher Saya — satu akun cuma bisa sekali, jadi jangan sampai keduluan.',
    'general',
    'customers',
    nullif(p_banner, ''),
    auth.jwt() ->> 'email'
  );

  return v_id;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select code, new_customers_only, quantity from vouchers
--   order by created_at desc limit 5;
--
--   select _pelanggan_baru('orang@contoh.com');
