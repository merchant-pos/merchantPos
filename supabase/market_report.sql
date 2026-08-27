-- KaataGo — laporan pasar untuk Super Admin.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Empat pertanyaan yang selama ini hanya bisa dijawab dengan membuka
-- satu per satu resto: siapa pelanggan yang paling sering memakai
-- KaataGo, siapa yang mendaftar lalu tidak pernah memesan, resto mana
-- yang paling menghasilkan, dan resto mana yang belum menghasilkan
-- sama sekali.
--
-- ── Kenapa dihitung di server ────────────────────────────────────────
--
-- Menghitungnya di aplikasi berarti mengunduh seluruh pesanan seluruh
-- resto ke sebuah HP. Batas 1.000 baris PostgREST akan memotongnya
-- diam-diam, dan yang muncul di layar adalah peringkat yang salah tanpa
-- satu pun tanda bahwa ada yang hilang.
--
-- ── Apa yang dihitung sebagai transaksi ──────────────────────────────
--
-- Hanya pesanan yang benar-benar dibayar. Pesanan yang batal atau
-- kedaluwarsa pernah ada di layar kasir, tapi tidak pernah jadi uang —
-- memasukkannya membuat resto yang banyak pesanan batal terlihat lebih
-- besar daripada resto yang benar-benar berjualan.
--
-- Resto platform (KaataGo sendiri) dan resto yang sudah dihapus tidak
-- ikut: keduanya bukan pasar.

-- Layar ini menampilkan lima teratas, tapi fungsinya menerima batas
-- sendiri — angka yang dipatok di dalam fungsi memaksa penulisan ulang
-- di server hanya untuk mengubah tampilan.
create or replace function report_top_customers(p_limit integer default 5)
returns table (
  customer_label text,
  customer_name text,
  orders_count bigint,
  total_amount bigint
)
language sql
security definer
set search_path = public
as $$
  select o.customer_label,
         coalesce(c.name, o.customer_label),
         count(*),
         coalesce(sum(o.total), 0)::bigint
  from orders o
  join restaurants r on r.id = o.resto_id
  left join customers c on c.email = o.customer_label
  where is_super_admin()
    and o.payment_status = 'paid'
    and coalesce(r.is_platform, false) = false
    and coalesce(r.is_deleted, false) = false
    -- Hanya akun terdaftar. Pesanan kasir memakai nama tamu yang
    -- diketik di tempat, dan dua tamu bernama "Budi" di dua resto
    -- berbeda bukan satu orang — memeringkatnya sebagai satu orang
    -- adalah angka yang salah, bukan angka yang kasar.
    and exists (select 1 from customers c2 where c2.email = o.customer_label)
  group by o.customer_label, c.name
  order by coalesce(sum(o.total), 0) desc, count(*) desc
  limit greatest(1, least(coalesce(p_limit, 5), 100));
$$;

-- Pelanggan yang mendaftar tapi belum pernah memesan.
--
-- Ini yang paling berguna dari keempatnya: orang yang sudah memasang
-- aplikasinya dan berhenti di situ. Mereka sudah melewati bagian
-- tersulit dan cuma belum punya alasan untuk kembali.
create or replace function report_idle_customers(p_limit integer default 100)
returns table (
  email text,
  customer_name text,
  phone text
)
language sql
security definer
set search_path = public
as $$
  select c.email, c.name, c.phone
  from customers c
  where is_super_admin()
    and not exists (
      select 1 from orders o
      where o.customer_label = c.email and o.payment_status = 'paid'
    )
  order by c.name
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

create or replace function report_top_restos(p_limit integer default 5)
returns table (
  resto_id text,
  resto_name text,
  orders_count bigint,
  total_amount bigint
)
language sql
security definer
set search_path = public
as $$
  select r.id, r.name, count(o.id),
         coalesce(sum(o.total), 0)::bigint
  from restaurants r
  join orders o on o.resto_id = r.id and o.payment_status = 'paid'
  where is_super_admin()
    and coalesce(r.is_platform, false) = false
    and coalesce(r.is_deleted, false) = false
  group by r.id, r.name
  order by coalesce(sum(o.total), 0) desc
  limit greatest(1, least(coalesce(p_limit, 5), 100));
$$;

-- Resto yang belum menghasilkan sama sekali.
--
-- Dipakai LEFT JOIN, bukan NOT IN: resto yang seluruh pesanannya batal
-- punya baris di orders tapi nol rupiah, dan itu justru yang paling
-- perlu ditengok — mereka mencoba memakainya dan gagal menyelesaikan.
create or replace function report_idle_restos(p_limit integer default 200)
returns table (
  resto_id text,
  resto_name text,
  orders_count bigint
)
language sql
security definer
set search_path = public
as $$
  select r.id, r.name,
         count(o.id) filter (where o.id is not null)
  from restaurants r
  left join orders o on o.resto_id = r.id and o.payment_status = 'paid'
  where is_super_admin()
    and coalesce(r.is_platform, false) = false
    and coalesce(r.is_deleted, false) = false
  group by r.id, r.name
  having coalesce(sum(o.total), 0) = 0
  order by r.name
  limit greatest(1, least(coalesce(p_limit, 200), 500));
$$;

revoke all on function report_top_customers(integer) from public, anon;
revoke all on function report_idle_customers(integer) from public, anon;
revoke all on function report_top_restos(integer) from public, anon;
revoke all on function report_idle_restos(integer) from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- Catatan
-- ─────────────────────────────────────────────────────────────────────
--
-- Keempatnya SECURITY DEFINER, jadi `is_super_admin()` di klausa WHERE
-- bukan hiasan — tanpa itu fungsinya membocorkan seluruh pasar KaataGo
-- ke siapa pun yang bisa memanggil RPC. Ditulis sebagai syarat WHERE,
-- bukan RAISE, supaya yang bukan Super Admin menerima daftar kosong
-- alih-alih pesan yang mengonfirmasi bahwa datanya ada.
