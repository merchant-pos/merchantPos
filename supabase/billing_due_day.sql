-- KaataGo — tanggal tagih 29, 30, 31, dan jatuh tempo berikutnya.
--
-- Jalankan SETELAH billing.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang `billing_day` dibatasi 1–28. Batas itu memang
-- menghindari pertanyaan "tanggal 31 di bulan Februari itu kapan",
-- tapi menghindarinya dengan cara melarang resto memilih tanggal
-- tagihnya sendiri — dan resto yang siklus kasnya jatuh di akhir bulan
-- terpaksa menagih di tanggal yang bukan tanggalnya.
--
-- Sekarang pertanyaannya dijawab, bukan dilarang: tanggal yang melebihi
-- umur bulannya jatuh di hari terakhir bulan itu. Tanggal 31 jadi 30 di
-- April, 28 di Februari biasa, dan 29 di Februari kabisat — bulannya
-- yang dilihat, bukan angka yang dipatok.

begin;

alter table resto_billing drop constraint if exists resto_billing_billing_day_check;
alter table resto_billing add constraint resto_billing_billing_day_check
  check (billing_day between 1 and 31);

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Jatuh tempo, dengan tanggal yang menyesuaikan umur bulannya
-- ─────────────────────────────────────────────────────────────────────

-- Tanggal tagih di dalam sebuah bulan.
--
-- Dipotong ke hari terakhir kalau bulannya lebih pendek. Perhitungannya
-- dari awal bulan + 1 bulan − 1 hari, bukan daftar panjang hari per
-- bulan: tabel semacam itu benar sampai seseorang lupa tahun kabisat.
create or replace function _billing_day_in_month(p_day smallint, p_month date)
returns date
language sql
immutable
as $$
  select make_date(
    extract(year from p_month)::int,
    extract(month from p_month)::int,
    least(
      greatest(coalesce(p_day, 1), 1),
      extract(day from (date_trunc('month', p_month)
                        + interval '1 month - 1 day'))::int
    )
  );
$$;

-- Jatuh tempo berikutnya bagi sebuah tanggal.
--
-- Kalau tanggal tagihnya belum lewat bulan ini, ya bulan ini. Kalau
-- sudah lewat, bulan depan — dan tanggalnya dihitung ulang di bulan
-- depan itu, bukan digeser sekian hari. 31 Januari yang digeser satu
-- bulan bukan 28 Februari di semua penanggalan.
create or replace function _billing_due_on(p_day smallint, p_from date)
returns date
language sql
immutable
as $$
  select case
    when p_from <= _billing_day_in_month(p_day, p_from)
      then _billing_day_in_month(p_day, p_from)
    else _billing_day_in_month(
           p_day, (date_trunc('month', p_from) + interval '1 month')::date)
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Kapan tagihan berikutnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Ditambahkan sebagai kolom baru, bukan dihitung di aplikasi. Aturan
-- pemotongan tanggal di atas ada di satu tempat; menyalinnya ke Dart
-- berarti dua perhitungan yang suatu saat berpisah, dan yang terlihat
-- adalah layar yang menjanjikan tanggal berbeda dari yang benar-benar
-- ditagih.

drop function if exists resto_billing_state(text);

create or replace function resto_billing_state(p_resto_id text)
returns table (
  locked boolean,
  due_date date,
  days_left integer,
  amount bigint,
  invoice_id text,
  invoice_status text,
  monthly_price bigint,
  billing_day smallint,
  active boolean,
  next_due_date date
)
language sql
security definer
set search_path = public
stable
as $$
  with setelan as (
    select * from resto_billing where resto_id = p_resto_id
  ),
  tertunggak as (
    select i.* from billing_invoices i
    where i.resto_id = p_resto_id
      and i.status in ('unpaid', 'review')
    order by i.due_date
    limit 1
  )
  select
    coalesce(
      s.active
      and s.monthly_price > 0
      and t.id is not null
      and t.status = 'unpaid'
      and current_date > t.due_date + s.grace_days,
      false
    ),
    t.due_date,
    (t.due_date - current_date)::integer,
    t.amount,
    t.id,
    t.status,
    coalesce(s.monthly_price, 0),
    coalesce(s.billing_day, 1::smallint),
    coalesce(s.active, false),
    -- Yang masih menunggak: tagihan berikutnya adalah sebulan sesudah
    -- yang belum dibayar itu. Menyebut tanggal yang lebih jauh sementara
    -- ada yang belum lunas membuat resto mengira dia punya waktu sampai
    -- tanggal itu.
    case
      when not coalesce(s.active, false) or coalesce(s.monthly_price, 0) = 0
        then null
      when t.id is not null
        then _billing_day_in_month(
               s.billing_day,
               (date_trunc('month', t.due_date) + interval '1 month')::date)
      else _billing_due_on(s.billing_day, current_date + 1)
    end
  from setelan s
  left join tertunggak t on true;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select _billing_due_on(31::smallint, date '2026-01-31');  -- 2026-01-31
--   select _billing_due_on(31::smallint, date '2026-02-01');  -- 2026-02-28
--   select _billing_due_on(31::smallint, date '2028-02-01');  -- 2028-02-29
--   select _billing_due_on(31::smallint, date '2026-04-01');  -- 2026-04-30
--   select _billing_due_on(18::smallint, date '2026-08-19');  -- 2026-09-18
