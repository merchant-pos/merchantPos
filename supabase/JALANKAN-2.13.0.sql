-- KaataGo — bagian 55, 56, dan 57.
-- Jalankan SETELAH bagian 53 (cashier_shift). Aman diulang.


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 55 — GL Selisih Kasir dan pelunasannya
-- ═══════════════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 56 — laporan penjualan untuk merchant
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — laporan penjualan untuk merchant sendiri.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Angka penjualan selama ini hanya bisa dibaca sebagai daftar transaksi
-- satu per satu. Itu cukup untuk mencocokkan uang, tapi tidak menjawab
-- pertanyaan yang benar-benar menentukan: menu mana yang sebaiknya
-- ditambah porsinya, menu mana yang sebaiknya dibuang dari daftar, dan
-- jam berapa orang harus disiapkan lebih banyak.
--
-- ── Kenapa dihitung di server ────────────────────────────────────────
--
-- Menghitungnya di aplikasi berarti mengunduh seluruh pesanan satu
-- merchant ke sebuah HP, lalu menguraikan `items` satu per satu. Batas
-- 1.000 baris PostgREST memotongnya diam-diam pada merchant yang ramai
-- — dan yang tampil di layar adalah peringkat yang salah tanpa satu pun
-- tanda ada yang hilang. Merchant yang paling butuh laporan ini justru
-- yang paling cepat melewati batas itu.
--
-- ── Siapa yang boleh membacanya ──────────────────────────────────────
--
-- Owner dan Admin saja. Syaratnya ditulis sebagai bagian WHERE, bukan
-- `raise`: yang tidak berhak menerima daftar kosong, karena pesan galat
-- justru mengonfirmasi bahwa datanya ada.
--
-- Kasir dan Chef sengaja tidak. Yang mereka butuhkan pesanan yang
-- sedang berjalan, bukan peringkat menu — dan omzet merchant bukan
-- angka yang perlu beredar di antara semua orang yang memegang HP.
--
-- ── Apa yang dihitung ────────────────────────────────────────────────
--
-- Hanya pesanan **lunas**. Pesanan batal pernah ada di layar kasir tapi
-- tidak pernah jadi uang; menghitungnya membuat menu yang sering
-- dibatalkan terlihat laris.

-- ─────────────────────────────────────────────────────────────────────
-- Menu terlaris
-- ─────────────────────────────────────────────────────────────────────
--
-- Nama menunya diambil dari baris pesanannya, bukan dari katalog. Menu
-- yang sudah dihapus tetap punya sejarah penjualan, dan laporan yang
-- menghilangkannya akan menyebut omzet yang lebih kecil daripada yang
-- benar-benar diterima.
create or replace function report_menu_sales(
  p_resto_id text,
  p_from date,
  p_to date,
  p_limit integer default 10)
returns table (
  product_id text,
  product_name text,
  qty bigint,
  omzet bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select item ->> 'productId',
         max(item ->> 'productName'),
         sum((item ->> 'quantity')::bigint),
         sum((item ->> 'price')::bigint * (item ->> 'quantity')::bigint)
  from orders o,
       lateral jsonb_array_elements(o.items) item
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and (o.created_at at time zone 'Asia/Jakarta')::date
        between p_from and p_to
  group by 1
  order by sum((item ->> 'quantity')::bigint) desc
  limit greatest(1, least(coalesce(p_limit, 10), 100));
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menu yang tidak laku
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang diam justru yang paling menyuruh melakukan sesuatu. Peringkat
-- teratas menyenangkan dilihat tapi tidak mengubah apa pun; menu yang
-- nol selama sebulan adalah bahan yang dibeli, tempat yang dipakai di
-- daftar, dan waktu pelanggan yang terpakai untuk melewatinya.
--
-- Dibaca dari katalog, bukan dari pesanan: menu yang tidak pernah
-- terjual memang tidak punya baris di `orders` sama sekali.
create or replace function report_idle_menus(
  p_resto_id text,
  p_from date,
  p_to date)
returns table (
  product_id text,
  product_name text,
  category text,
  price integer,
  qty bigint
)
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
      and o.payment_status = 'paid'
      and (o.created_at at time zone 'Asia/Jakarta')::date
          between p_from and p_to
    group by 1
  )
  select p.id, p.name, p.category, p.price, coalesce(t.qty, 0)
  from products p
  left join terjual t on t.pid = p.id
  where p.resto_id = p_resto_id
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and coalesce(t.qty, 0) = 0
  order by p.category, p.name;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Jam ramai
-- ─────────────────────────────────────────────────────────────────────
--
-- Jam WIB, bukan UTC. Jam ramai yang bergeser tujuh jam adalah jadwal
-- shift yang salah, dan yang menanggungnya kasir yang datang di jam
-- sepi lalu pulang saat antreannya mulai.
create or replace function report_busy_hours(
  p_resto_id text,
  p_from date,
  p_to date)
returns table (
  jam integer,
  orders_count bigint,
  omzet bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select extract(hour from (o.created_at at time zone 'Asia/Jakarta'))::integer,
         count(*),
         coalesce(sum(o.total), 0)::bigint
  from orders o
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and (o.created_at at time zone 'Asia/Jakarta')::date
        between p_from and p_to
  group by 1
  order by 1;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Ringkasan
-- ─────────────────────────────────────────────────────────────────────
--
-- Empat angka yang menjadi pembanding seluruh isi laporan. Tanpa
-- pembanding, "Nasi Goreng terjual 43" adalah angka yang tidak bisa
-- dinilai bagus atau buruk oleh siapa pun.
create or replace function report_sales_summary(
  p_resto_id text,
  p_from date,
  p_to date)
returns table (
  orders_count bigint,
  omzet bigint,
  rata_transaksi bigint,
  menu_terjual bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with pesanan as (
    select o.total, o.items
    from orders o
    where o.resto_id = p_resto_id
      and o.payment_status = 'paid'
      and is_resto_employee(p_resto_id, array['owner', 'admin'])
      and (o.created_at at time zone 'Asia/Jakarta')::date
          between p_from and p_to
  )
  select count(*),
         coalesce(sum(total), 0)::bigint,
         -- Dibulatkan ke bawah supaya sejalan dengan seluruh angka
         -- rupiah di aplikasi ini, yang tidak pernah mengenal sen.
         coalesce(floor(avg(total)), 0)::bigint,
         coalesce((
           select sum((item ->> 'quantity')::bigint)
           from pesanan p2, lateral jsonb_array_elements(p2.items) item
         ), 0)
  from pesanan;
$$;

grant execute on function report_menu_sales(text, date, date, integer) to authenticated;
grant execute on function report_idle_menus(text, date, date) to authenticated;
grant execute on function report_busy_hours(text, date, date) to authenticated;
grant execute on function report_sales_summary(text, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from report_sales_summary('<resto_id>', '2026-08-01', '2026-08-31');
--   select * from report_menu_sales('<resto_id>', '2026-08-01', '2026-08-31', 10);
--   select * from report_idle_menus('<resto_id>', '2026-08-01', '2026-08-31');
--   select * from report_busy_hours('<resto_id>', '2026-08-01', '2026-08-31');
--
--   -- Sebagai Kasir, keempatnya harus mengembalikan daftar kosong —
--   -- bukan pesan galat.


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 57 — perkiraan modal awal saat shift dibuka
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — perkiraan modal awal saat shift dibuka.
--
-- Jalankan SETELAH cashier_shift.sql. Aman diulang.
--
-- Menutup shift sudah punya pembanding: uang yang dihitung tangan
-- dibandingkan dengan yang seharusnya ada. Membuka shift belum punya
-- apa-apa — modal awal diketik apa adanya, dan tidak ada yang
-- memeriksanya.
--
-- Akibatnya selisih bisa lahir sebelum jualan dimulai. Kasir yang salah
-- ketik modal awal — atau menerima laci yang isinya sudah tidak sesuai
-- sejak semalam — baru mengetahuinya delapan jam kemudian, saat shiftnya
-- ditutup dan selisihnya sudah jadi tanggung jawabnya sendiri.

-- Berapa yang seharusnya ada di laci sekarang, sebelum shift dibuka.
--
-- Titik awalnya uang yang DIHITUNG pada penutupan terakhir, bukan yang
-- seharusnya ada saat itu. Kalau shift kemarin kurang Rp 10.000, yang
-- betul-betul tertinggal di laci memang jumlah yang kurang itu — dan
-- kekurangannya sudah punya tagihannya sendiri di `cash_variances`.
-- Memakai angka "seharusnya" berarti menagihkan kekurangan yang sama dua
-- kali, kepada dua orang yang berbeda.
--
-- Lalu ditambah-kurangi apa pun yang terjadi sesudah penutupan itu:
-- penjualan tunai di sela-sela shift, setoran, dan penarikan petty cash.
-- Biasanya kosong — tapi "biasanya" bukan alasan untuk tidak
-- menghitungnya.
create or replace function expected_opening_cash(p_resto_id text)
returns table (ada boolean, jumlah bigint)
language sql
stable
security definer
set search_path = public
as $$
  with terakhir as (
    select s.counted_cash, s.closed_at
    from cashier_shifts s
    where s.resto_id = p_resto_id
      and s.closed_at is not null
      and s.counted_cash is not null
    order by s.closed_at desc
    limit 1
  )
  select
    exists (select 1 from terakhir),
    coalesce((
      select t.counted_cash
           + coalesce((
               select sum(o.total)
               from orders o
               where o.resto_id = p_resto_id
                 and o.payment_status = 'paid'
                 and o.payment_method = 'cash'
                 and o.created_at >= t.closed_at
             ), 0)
           - coalesce((
               select sum(d.amount)
               from cash_deposits d
               where d.resto_id = p_resto_id
                 and d.status <> 'rejected'
                 and d.created_at >= t.closed_at
             ), 0)
           - coalesce((
               select sum(p.amount)
               from petty_cash_entries p
               where p.resto_id = p_resto_id
                 and p.source = 'cash_withdrawal'
                 and p.status <> 'rejected'
                 and p.created_at >= t.closed_at
             ), 0)
      from terakhir t
    ), 0)::bigint
  from terakhir
  -- Merchant yang belum pernah menutup shift sekali pun tetap dapat satu
  -- baris, dengan `ada` = false. Daftar kosong akan terbaca aplikasi
  -- sebagai "gagal", padahal artinya "belum ada pembandingnya".
  right join (select 1) satu on true;
$$;

grant execute on function expected_opening_cash(text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from expected_opening_cash('<resto_id>');
--
--   -- Pada merchant yang belum pernah menutup shift, hasilnya
--   -- (false, 0) — bukan daftar kosong.
