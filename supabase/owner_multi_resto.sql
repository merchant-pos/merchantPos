-- KaataGo — peran Owner + satu orang mengelola banyak resto
-- (jalankan SETELAH semua migrasi sebelumnya; ini satu-satunya yang
-- perlu dijalankan untuk rilis ini).
--
-- Tiga hal sekaligus:
--
--   1. Peran baru 'owner' yang memegang semua menu Chef, Kasir, Admin,
--      dan Finance.
--   2. Satu email boleh terdaftar di lebih dari satu resto. Sebelumnya
--      `employees.email` adalah kunci utama, jadi satu orang hanya bisa
--      menjadi karyawan di satu tempat — pemilik dua cabang terpaksa
--      punya dua alamat email.
--   3. Owner otomatis lolos setiap pemeriksaan peran, tanpa perlu
--      menyebutkan 'owner' di puluhan policy satu per satu.
--
-- Aman dijalankan berulang kali.

begin;

-- ── 1. Peran owner ───────────────────────────────────────────────────
alter table employees drop constraint if exists employees_role_check;
alter table employees add constraint employees_role_check
  check (role in ('admin', 'kasir', 'chef', 'super_admin', 'finance', 'owner'));

-- ── 2. Satu email, banyak resto ──────────────────────────────────────
-- Keanggotaan seseorang melekat pada restonya, bukan pada dirinya semata,
-- jadi yang harus unik adalah pasangan (email, resto_id).
--
-- Pasangan itu TIDAK dijadikan kunci utama, karena baris super_admin
-- sengaja punya resto_id NULL — mereka memang tidak terikat satu resto —
-- dan kunci utama menolak NULL. Sebagai gantinya dipakai unique index,
-- yang mengizinkan NULL sekaligus tetap mencegah baris kembar.
--
-- NULLS NOT DISTINCT membuat dua baris super_admin dengan email sama
-- tetap dianggap bentrok; tanpa itu, Postgres menganggap setiap NULL
-- berbeda dan email yang sama bisa masuk dua kali. Klausa itu baru ada
-- sejak Postgres 15, jadi ada jalan mundurnya.
alter table employees drop constraint if exists employees_pkey;

do $$
begin
  begin
    create unique index if not exists employees_email_resto_uidx
      on employees (email, resto_id) nulls not distinct;
  exception when syntax_error or feature_not_supported then
    create unique index if not exists employees_email_resto_uidx
      on employees (email, resto_id);
  end;
end $$;

-- Pencarian karyawan selalu lewat email, dan sekarang bisa mengembalikan
-- beberapa baris sekaligus.
create index if not exists idx_employees_email on employees(email);

-- ── 3. Owner lolos setiap pemeriksaan peran ──────────────────────────
-- Diletakkan di dalam is_resto_employee, bukan disebar ke tiap policy.
-- Menambahkan 'owner' ke puluhan array peran berarti setiap policy baru
-- di masa depan berpeluang lupa menyertakannya — dan lupa di sini
-- bentuknya adalah Owner yang tiba-tiba kehilangan akses ke satu layar
-- tanpa sebab yang jelas.
create or replace function is_resto_employee(
  p_resto_id text,
  p_roles text[] default array['admin','kasir','chef']
)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from employees e
    where e.email = auth.jwt()->>'email'
      and e.resto_id = p_resto_id
      and e.active = true
      and (e.role = any(p_roles) or e.role = 'owner')
  );
$$;

-- ── 4. Policy `employees` tidak perlu disentuh ───────────────────────
-- Aturan yang ada (lihat super_admin.sql) sudah mengizinkan seseorang
-- membaca barisnya sendiri — itulah yang dipakai aplikasi untuk mengetahui
-- resto mana saja yang dia pegang — serta memberi admin dan super_admin
-- hak mengelola. Owner ikut lolos lewat perubahan is_resto_employee di
-- atas, jadi menambah policy baru di sini hanya akan menduplikasi aturan
-- yang sudah benar.

commit;
