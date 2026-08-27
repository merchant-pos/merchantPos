-- KaataGo — dua bagian baru untuk 2.10.0.
-- Salin seluruhnya ke SQL Editor Supabase, jalankan. Aman diulang.


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 52 — label menu, penilaian menu, angka terjual
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — label menu, penilaian menu, dan angka terjualnya.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Tiga hal yang selama ini hanya diketahui merchant sendiri: menu mana
-- yang baru, menu mana yang paling laku, dan apa kata orang yang sudah
-- memesannya. Ketiganya adalah yang paling menentukan orang jadi
-- memesan atau tidak, dan tidak satu pun sampai ke layar pelanggan.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Label menu
-- ─────────────────────────────────────────────────────────────────────
--
-- Daftar teks bebas, bukan kolom boolean satu per label. Labelnya akan
-- bertambah — "halal", "pedas", "menu anak" — dan tiap penambahan tidak
-- boleh berarti migrasi kolom baru di tabel yang dibaca setiap layar.
--
-- Yang tersimpan di sini hanya label yang DINYATAKAN merchant: 'new',
-- 'best_seller', 'recommended'. Label diskon tidak ikut disimpan; itu
-- fakta yang sudah dimiliki tabel `discounts`, dan menyalinnya ke sini
-- berarti label yang tetap terpasang seminggu setelah promonya habis.
alter table products
  add column if not exists badges jsonb not null default '[]'::jsonb;

-- ─────────────────────────────────────────────────────────────────────
-- Penilaian menu
-- ─────────────────────────────────────────────────────────────────────

create table if not exists product_reviews (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,
  product_id text not null references products (id) on delete cascade,

  -- Menempel pada orang, bukan pada perangkat — sama seperti penilaian
  -- merchant.
  customer_email text not null,
  customer_name text not null,

  rating smallint not null check (rating between 1 and 5),
  comment text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Satu orang satu penilaian per menu. Yang memesan nasi goreng
  -- sepuluh kali tetap punya satu suara.
  unique (product_id, customer_email)
);

create index if not exists product_reviews_product_idx
  on product_reviews (product_id, created_at desc);
create index if not exists product_reviews_resto_idx
  on product_reviews (resto_id);

alter table product_reviews enable row level security;

-- Dibaca siapa saja, termasuk tamu yang belum punya akun — itu justru
-- yang paling membutuhkannya sebelum memutuskan.
drop policy if exists "product_reviews: public read" on product_reviews;
create policy "product_reviews: public read" on product_reviews
  for select using (true);

-- Ditulis hanya oleh orang yang benar-benar pernah memesan menu itu,
-- dan pesanannya lunas.
--
-- Syaratnya ditegakkan di sini, bukan di aplikasi. Aplikasi memang
-- hanya menawarkan tombol nilai pada menu di riwayat pesanannya
-- sendiri, tapi aturan yang hanya ada di aplikasi bukan aturan — ia
-- cuma tampilan. Tanpa baris ini, satu permintaan HTTP polos sudah
-- cukup untuk memberi bintang lima pada menu yang tidak pernah dibeli.
drop policy if exists "product_reviews: own write" on product_reviews;
create policy "product_reviews: own write" on product_reviews
  for all
  using (customer_email = auth.jwt() ->> 'email')
  with check (
    customer_email = auth.jwt() ->> 'email'
    and exists (
      select 1
      from orders o
      where o.customer_label = auth.jwt() ->> 'email'
        and o.payment_status = 'paid'
        and o.items @> jsonb_build_array(
              jsonb_build_object('productId', product_reviews.product_id))
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Bintang dan angka terjual, sekaligus
-- ─────────────────────────────────────────────────────────────────────
--
-- Satu panggilan untuk seluruh menu satu merchant. Layar menu
-- menampilkan puluhan kartu sekaligus; satu panggilan per kartu berarti
-- puluhan permintaan tiap kali kategori dibuka.
--
-- `security definer` karena angkanya harus terbaca tamu yang belum
-- masuk juga, sedangkan `orders` tertutup bagi mereka — dan memang
-- seharusnya tertutup. Yang keluar dari fungsi ini hanya angka
-- ringkasan: tidak ada nama pemesan, nilai transaksi, maupun isi
-- pesanan siapa pun.
create or replace function product_stats(p_resto_id text)
returns table (product_id text, rata numeric, jumlah bigint, terjual bigint)
language sql
stable
security definer
set search_path = public
as $$
  with terjual as (
    select item ->> 'productId' as pid,
           sum((item ->> 'quantity')::bigint) as qty
    from orders o,
         lateral jsonb_array_elements(o.items) item
    where o.resto_id = p_resto_id
      -- Hanya yang lunas. Pesanan yang batal atau hangus bukan
      -- penjualan, dan menghitungnya berarti angka "terjual" yang
      -- dipajang ke pelanggan bisa dinaikkan dengan memesan lalu tidak
      -- membayar.
      and o.payment_status = 'paid'
    group by 1
  ),
  nilai as (
    select r.product_id as pid,
           round(avg(r.rating)::numeric, 1) as rata,
           count(*) as jumlah
    from product_reviews r
    where r.resto_id = p_resto_id
    group by 1
  )
  select coalesce(t.pid, n.pid),
         coalesce(n.rata, 0),
         coalesce(n.jumlah, 0),
         coalesce(t.qty, 0)
  from terjual t
  full outer join nilai n on n.pid = t.pid
  where coalesce(t.pid, n.pid) is not null;
$$;

grant execute on function product_stats(text) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select p.name, s.rata, s.jumlah, s.terjual
--   from product_stats('<resto_id>') s
--   join products p on p.id = s.product_id
--   order by s.terjual desc;
--
--   select p.name, p.badges from products p where p.badges <> '[]'::jsonb;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 53 — buka dan tutup shift kasir
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — buka dan tutup shift kasir.
--
-- Jalankan setelah cash_deposit.sql dan petty_cash.sql. Aman diulang.
--
-- Selama ini tidak pernah ada satu momen pun yang berbunyi "uang di laci
-- dihitung sekarang, dan segini isinya". Saldo Cash dihitung dari
-- penjualan dikurangi setoran dan petty cash — angka yang benar secara
-- pembukuan, tapi tidak seorang pun pernah membandingkannya dengan uang
-- yang benar-benar ada di laci. Selisih baru ketahuan saat rekonsiliasi
-- bulanan, dan pada saat itu sudah tidak ada yang ingat hari mana, apalagi
-- siapa yang sedang memegang lacinya.

begin;

create table if not exists cashier_shifts (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  -- Siapa yang memegang laci. Emailnya kunci, namanya disalin saat
  -- membuka — pegawai yang berhenti dan barisnya dihapus tidak boleh
  -- membuat shift lamanya kehilangan penanggung jawab.
  employee_email text not null,
  employee_name text,

  opened_at timestamptz not null default now(),

  -- Uang yang sudah ada di laci sebelum jualan dimulai. Biasanya uang
  -- kembalian yang ditinggal dari shift sebelumnya.
  opening_cash bigint not null default 0 check (opening_cash >= 0),

  closed_at timestamptz,

  -- Yang benar-benar dihitung tangan saat tutup.
  counted_cash bigint check (counted_cash >= 0),

  -- Yang seharusnya ada menurut pembukuan. Dihitung server saat tutup,
  -- bukan dikirim aplikasi — angka yang menilai seseorang tidak boleh
  -- berasal dari perangkat orang itu.
  expected_cash bigint,

  -- counted - expected. Negatif berarti kurang.
  --
  -- Disimpan, bukan dihitung ulang tiap dibaca: `expected_cash` adalah
  -- keadaan pada saat penutupan, dan setoran yang dicatat menyusul
  -- setelahnya tidak boleh mengubah angka yang sudah ditandatangani.
  difference bigint,

  note text,

  closed_by text,

  created_at timestamptz not null default now()
);

create index if not exists cashier_shifts_resto_idx
  on cashier_shifts (resto_id, opened_at desc);

-- Satu laci, satu shift terbuka.
--
-- Bukan satu shift per kasir: yang dihitung isi laci, dan lacinya cuma
-- ada satu. Dua shift terbuka bersamaan akan menghitung penjualan tunai
-- yang sama dua kali, lalu keduanya sama-sama terlihat kelebihan uang.
create unique index if not exists cashier_shifts_satu_terbuka
  on cashier_shifts (resto_id)
  where closed_at is null;

alter table cashier_shifts enable row level security;

-- Dibaca seluruh pegawai merchant. Kasir berhak tahu shiftnya sendiri
-- ditutup dengan angka berapa — selisih yang hanya bisa dilihat atasannya
-- adalah tuduhan yang tidak bisa dijawab.
drop policy if exists "cashier_shifts: read" on cashier_shifts;
create policy "cashier_shifts: read" on cashier_shifts
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin', 'kasir'])
  );

-- Tidak ada policy insert/update/delete sama sekali. Membuka dan menutup
-- shift hanya lewat fungsi di bawah — kalau barisnya bisa disunting
-- langsung, `expected_cash` bisa ditulis sendiri oleh yang sedang diukur,
-- dan seluruh gunanya hilang.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Membuka shift
-- ─────────────────────────────────────────────────────────────────────

create or replace function open_shift(p_resto_id text, p_opening_cash bigint)
returns cashier_shifts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_nama text;
  v_row cashier_shifts;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
        array['owner', 'finance', 'admin', 'kasir']) then
    raise exception 'Tidak berhak membuka shift di merchant ini.';
  end if;

  if p_opening_cash is null or p_opening_cash < 0 then
    raise exception 'Modal awal tidak boleh minus.';
  end if;

  -- Diperiksa lebih dulu supaya pesannya bisa dibaca orang. Tanpa ini
  -- yang muncul adalah galat unique index — benar, tapi tidak memberi
  -- tahu apa pun kepada kasir yang sedang berdiri di depan antrean.
  if exists (
    select 1 from cashier_shifts s
    where s.resto_id = p_resto_id and s.closed_at is null
  ) then
    raise exception 'Masih ada shift yang belum ditutup di merchant ini.';
  end if;

  select e.name into v_nama
  from employees e
  where e.email = v_email and e.resto_id = p_resto_id
  limit 1;

  insert into cashier_shifts (
    resto_id, employee_email, employee_name, opening_cash)
  values (p_resto_id, v_email, v_nama, p_opening_cash)
  returning * into v_row;

  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Berapa yang seharusnya ada di laci
-- ─────────────────────────────────────────────────────────────────────
--
-- Aturannya sama persis dengan Saldo Cash di layar Saldo & Pengeluaran —
-- penjualan tunai, dikurangi yang sudah keluar laci lewat setoran dan
-- penarikan petty cash — hanya saja dibatasi rentang waktu shiftnya dan
-- dimulai dari modal awal.
--
-- Setoran dan petty cash yang DITOLAK tidak dikurangkan: uangnya
-- dikembalikan ke laci, jadi ia kembali jadi tanggung jawab shift ini.
-- Yang masih menunggu persetujuan tetap dikurangkan, karena fisik
-- uangnya memang sudah tidak ada di laci.
--
-- Waktu yang dipakai `created_at` pesanan, bukan waktu lunasnya. Untuk
-- tunai keduanya memang satu momen: kasir memasukkan pesanannya justru
-- pada saat menerima uangnya.
create or replace function shift_expected_cash(
  p_shift_id uuid,
  p_until timestamptz default now())
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select s.opening_cash
       + coalesce((
           select sum(o.total)
           from orders o
           where o.resto_id = s.resto_id
             and o.payment_status = 'paid'
             and o.payment_method = 'cash'
             and o.created_at >= s.opened_at
             and o.created_at < p_until
         ), 0)
       - coalesce((
           select sum(d.amount)
           from cash_deposits d
           where d.resto_id = s.resto_id
             and d.status <> 'rejected'
             and d.created_at >= s.opened_at
             and d.created_at < p_until
         ), 0)
       - coalesce((
           select sum(p.amount)
           from petty_cash_entries p
           where p.resto_id = s.resto_id
             and p.source = 'cash_withdrawal'
             and p.status <> 'rejected'
             and p.created_at >= s.opened_at
             and p.created_at < p_until
         ), 0)
  from cashier_shifts s
  where s.id = p_shift_id;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menutup shift
-- ─────────────────────────────────────────────────────────────────────

create or replace function close_shift(
  p_shift_id uuid,
  p_counted_cash bigint,
  p_note text default null)
returns cashier_shifts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_shift cashier_shifts;
  v_expected bigint;
  v_saat timestamptz := now();
  v_row cashier_shifts;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  select * into v_shift from cashier_shifts where id = p_shift_id;
  if v_shift is null then
    raise exception 'Shiftnya tidak ditemukan.';
  end if;

  if v_shift.closed_at is not null then
    raise exception 'Shift ini sudah ditutup.';
  end if;

  -- Yang membuka boleh menutup shiftnya sendiri. Selain itu harus
  -- atasan — kasir yang kebetulan sedang login tidak boleh menutup
  -- shift orang lain lalu meninggalkan selisihnya atas nama orang itu.
  if v_email <> v_shift.employee_email
     and not is_resto_employee(v_shift.resto_id,
           array['owner', 'finance', 'admin']) then
    raise exception 'Hanya yang membuka shift ini, atau atasannya, yang '
                    'boleh menutupnya.';
  end if;

  if p_counted_cash is null or p_counted_cash < 0 then
    raise exception 'Uang yang dihitung tidak boleh minus.';
  end if;

  v_expected := shift_expected_cash(p_shift_id, v_saat);

  update cashier_shifts
     set closed_at = v_saat,
         counted_cash = p_counted_cash,
         expected_cash = v_expected,
         difference = p_counted_cash - v_expected,
         note = nullif(btrim(coalesce(p_note, '')), ''),
         closed_by = v_email
   where id = p_shift_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function open_shift(text, bigint) to authenticated;
grant execute on function close_shift(uuid, bigint, text) to authenticated;
grant execute on function shift_expected_cash(uuid, timestamptz) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select employee_name, opened_at, closed_at, opening_cash,
--          expected_cash, counted_cash, difference, note
--   from cashier_shifts
--   where resto_id = '<resto_id>'
--   order by opened_at desc;
--
--   -- Shift yang masih terbuka di semua merchant:
--   select resto_id, employee_email, opened_at
--   from cashier_shifts where closed_at is null;
