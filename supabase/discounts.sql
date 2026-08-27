-- KaataGo — diskon: per menu (termasuk bundling) atau minimum belanja.
--
-- Jalankan SETELAH gl_journal.sql dan orders_gl_code.sql. Aman diulang.
--
-- Diskon bukan sekadar angka yang dikurangi di layar kasir. Uang yang
-- tidak jadi diterima tetap harus terlihat di pembukuan — kalau tidak,
-- Penghasilan resto tercatat sebesar harga daftar sementara uang yang
-- masuk lebih kecil, dan selisihnya muncul sebagai kas yang hilang
-- tanpa sebab. Karena itu diskon punya GL-nya sendiri sebagai pengurang
-- pendapatan.

begin;

create table if not exists discounts (
  id text primary key,
  resto_id text not null references restaurants (id) on delete cascade,
  name text not null,

  -- 'products'     → berlaku untuk menu yang disebut di product_ids
  -- 'min_purchase' → berlaku untuk seluruh tagihan yang mencapai ambang
  basis text not null default 'products'
    check (basis in ('products', 'min_purchase')),

  -- 'percent' → value 1..100, 'amount' → value dalam rupiah
  kind text not null default 'percent'
    check (kind in ('percent', 'amount')),
  value integer not null check (value > 0),

  -- Lebih dari satu menu dalam satu aturan: itulah cara bundling
  -- dinyatakan. Potongannya dihitung dari jumlah seluruh menu yang ikut,
  -- bukan per baris — kalau per baris, diskon rupiah tetap akan
  -- terkalikan sebanyak menu yang ikut promo.
  product_ids jsonb not null default '[]'::jsonb,

  min_purchase bigint not null default 0,

  -- '>' atau '>='. Dipilih sendiri karena keduanya berbeda di telinga
  -- pelanggan, dan transaksi yang nilainya pas di batas adalah yang
  -- paling sering jadi perselisihan di meja kasir.
  compare_mode text not null default 'at_least'
    check (compare_mode in ('at_least', 'more_than')),

  -- Masa berlaku. Tanggal, bukan timestamp: resto berpikir dalam hari,
  -- dan "sampai 31 Agustus" berarti sampai tutup toko tanggal 31.
  starts_on date,
  ends_on date,

  active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now(),

  -- Yang berakhir sebelum dimulai bukan promo, itu salah ketik. Ditolak
  -- di sini juga, bukan hanya di formulirnya: aturan yang cuma dijaga
  -- aplikasi akan bocor lewat jalan lain suatu hari.
  constraint discounts_period_check
    check (ends_on is null or starts_on is null or ends_on > starts_on),

  -- Diskon berbasis menu tanpa satu pun menu tidak pernah mengenai apa
  -- pun; diskon minimum belanja dengan ambang nol mengenai semuanya,
  -- termasuk tagihan seribu rupiah.
  constraint discounts_target_check check (
    (basis = 'products' and jsonb_array_length(product_ids) > 0)
    or (basis = 'min_purchase' and min_purchase > 0)
  ),

  constraint discounts_percent_check
    check (kind <> 'percent' or value between 1 and 100)
);

create index if not exists idx_discounts_resto on discounts (resto_id, active);

alter table discounts enable row level security;

-- Dibaca siapa saja termasuk pelanggan tamu: promonya harus terlihat di
-- layar pesan, bukan baru muncul di struk.
drop policy if exists "discounts: public read" on discounts;
create policy "discounts: public read" on discounts for select using (true);

-- Ditulis kasir, admin, dan owner — sesuai menunya.
drop policy if exists "discounts: staff write" on discounts;
create policy "discounts: staff write" on discounts
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['admin', 'kasir', 'owner'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['admin', 'kasir', 'owner'])
  );

-- ─────────────────────────────────────────────────────────────────────
-- Diskon pada pesanan
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan di barisnya sendiri, bukan dihitung ulang saat dibaca.
-- Aturan diskonnya bisa diubah atau dihapus besok, sementara struk
-- pesanan hari ini harus tetap menyebut potongan yang benar-benar
-- diberikan saat itu.

alter table orders add column if not exists discount_amount bigint not null default 0;
alter table orders add column if not exists discount_id text;
alter table orders add column if not exists discount_name text;

-- ─────────────────────────────────────────────────────────────────────
-- GL Diskon
-- ─────────────────────────────────────────────────────────────────────
--
-- Sebagai pengurang pendapatan, bukan sebagai biaya. Diskon tidak
-- pernah menjadi uang yang keluar dari resto — ia adalah uang yang
-- tidak pernah masuk. Mencatatnya sebagai biaya membuat Pengeluaran
-- terlihat naik pada bulan promo, padahal tidak ada satu rupiah pun
-- yang berpindah.

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'discount', '2200002', 'GL Diskon Penjualan'
from restaurants r
on conflict (resto_id, payment_method) do nothing;

-- Jenis rujukan baru. Daftarnya ditulis lengkap di tiap berkas yang
-- menyentuhnya — sama alasannya dengan gl_accounts: berkas lama yang
-- dijalankan ulang sesudah yang baru akan menyempitkan daftarnya lagi
-- dan menolak baris yang sudah terlanjur ada.
alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

-- Jurnal diskon.
--
-- Ditambahkan sebagai pemicu terpisah, bukan dengan menulis ulang
-- log_order_paid_journal(): fungsi itu sudah ditimpa oleh empat berkas
-- berbeda sepanjang umur proyek ini, dan menimpanya sekali lagi dari
-- sini berarti urutan menjalankan berkas menentukan versi mana yang
-- akhirnya berlaku. Pemicu sendiri tidak punya masalah itu.
--
-- Didebit, bukan dikredit. Kesepakatan aplikasi ini: kredit = uang
-- masuk ke akun itu, debit = uang keluar. Diskon adalah pendapatan yang
-- tidak jadi diterima, jadi ia mengurangi — dan panah di layar Jurnal
-- GL akan menunjuk arah yang sama dengan yang dilihat Finance.
create or replace function log_order_discount_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  if new.payment_status <> 'paid' or coalesce(new.discount_amount, 0) <= 0 then
    return new;
  end if;

  -- Sudah pernah dicatat? Pesanan bisa berpindah status lebih dari
  -- sekali — dilunasi di kasir, lalu diperbaiki cara bayarnya — dan
  -- tiap perpindahan tidak boleh menambah satu baris diskon lagi.
  if exists (
    select 1 from gl_journal_entries
    where reference_type = 'order_discount' and reference_id = new.id::text
  ) then
    return new;
  end if;

  select * into v_gl from _gl_account_for(new.resto_id, 'discount');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id,
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'order_discount', new.id::text, new.discount_amount, 'debit',
      coalesce(nullif(new.discount_name, ''), 'Diskon') || ' — pesanan #' || v_ref
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_order_discount_insert on orders;
create trigger trg_log_order_discount_insert
  after insert on orders
  for each row execute function log_order_discount_journal();

drop trigger if exists trg_log_order_discount_update on orders;
create trigger trg_log_order_discount_update
  after update of payment_status on orders
  for each row execute function log_order_discount_journal();

commit;
