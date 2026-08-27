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
