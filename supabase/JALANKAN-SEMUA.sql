-- MerchantPOS — seluruh skema, dari database kosong.
--
-- Dibangkitkan scripts/gabung_sql_lengkap.sh. Jangan disunting
-- langsung; sunting berkas sumbernya di supabase/ lalu jalankan
-- skripnya lagi.
--
-- JANGAN dijalankan di proyek Supabase KaataGo.


-- ═══════════════════════════════════════════════════════════
-- 1. schema.sql
-- ═══════════════════════════════════════════════════════════

-- Kaata POS — Supabase schema (replaces Firestore collections)
-- Run this in Supabase Dashboard > SQL Editor.

create extension if not exists pgcrypto;

-- Restaurants: display name + address shown to customers after scanning
create table if not exists restaurants (
  id text primary key,
  name text not null,
  address text not null default ''
);

-- Employees: role + which restaurant they work at
create table if not exists employees (
  email text primary key,
  role text not null check (role in ('admin', 'kasir', 'chef')),
  resto_id text not null references restaurants(id),
  active boolean not null default true
);

-- Products: local SQLite is the cashier's source of truth; this table is
-- the mirror the customer app reads from (see FirestoreProductRepository
-- equivalent).
create table if not exists products (
  id text primary key,
  resto_id text not null references restaurants(id),
  name text not null,
  category text not null,
  price integer not null,
  stock integer not null
);
create index if not exists idx_products_resto on products(resto_id);

-- Orders: both Kasir walk-in sales and customer self-orders, unified
create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  session_id text,
  table_number text,
  source text not null check (source in ('customer', 'kasir')),
  payment_status text not null check (payment_status in ('pending', 'paid', 'expired', 'cancelled')),
  payment_method text,
  kitchen_status text not null default 'waiting'
    check (kitchen_status in ('waiting', 'onProgress', 'done')),
  customer_label text not null,
  total integer not null,
  items jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_orders_resto on orders(resto_id);
create index if not exists idx_orders_session on orders(session_id);
create index if not exists idx_orders_customer_label on orders(customer_label);

-- Table sessions: the "parent" grouping a customer's orders, plus the
-- active/lastOrderAt fields the auto-end scheduled job checks
create table if not exists sessions (
  id text primary key,
  resto_id text not null references restaurants(id),
  table_number text not null,
  active boolean not null default true,
  last_order_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Payment settings (QRIS/bank info) per restaurant
create table if not exists settings (
  resto_id text primary key references restaurants(id),
  merchant_name text not null default 'Toko Kamu',
  qris_id text not null default '',
  bank_name text not null default '',
  account_number text not null default '',
  account_holder text not null default ''
);

-- Customer profiles (name/phone/photo), keyed by email
create table if not exists customers (
  email text primary key,
  name text not null,
  phone text,
  photo_base64 text
);

-- Queued "send receipt by email" requests, processed by an Edge Function
create table if not exists mail_requests (
  id uuid primary key default gen_random_uuid(),
  to_email text not null,
  order_id uuid not null references orders(id),
  resto_id text not null,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  error text,
  created_at timestamptz not null default now()
);

-- Row Level Security: enabled with permissive policies for now (same
-- "open" posture as the earlier Firestore test-mode rules) so the app
-- keeps working end-to-end. Tighten these before real production launch
-- — e.g. restrict employees-table writes to service-role only, restrict
-- customers-table rows to their own auth.uid(), etc.
alter table restaurants enable row level security;
alter table employees enable row level security;
alter table products enable row level security;
alter table orders enable row level security;
alter table sessions enable row level security;
alter table settings enable row level security;
alter table customers enable row level security;
alter table mail_requests enable row level security;

create policy "public read/write restaurants" on restaurants for all using (true) with check (true);
create policy "public read/write employees" on employees for all using (true) with check (true);
create policy "public read/write products" on products for all using (true) with check (true);
create policy "public read/write orders" on orders for all using (true) with check (true);
create policy "public read/write sessions" on sessions for all using (true) with check (true);
create policy "public read/write settings" on settings for all using (true) with check (true);
create policy "public read/write customers" on customers for all using (true) with check (true);
create policy "public read/write mail_requests" on mail_requests for all using (true) with check (true);

-- Enable realtime (Firestore-style live streams) on the tables the app
-- watches with .stream()/.channel() subscriptions.
--
-- Dibungkus penangkap galat: tabel yang sudah terdaftar membuat
-- perintahnya gagal, dan galat itu menghentikan sisa berkasnya.
do $$
begin
  alter publication supabase_realtime add table orders;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table sessions;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table products;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table restaurants;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table settings;
exception when duplicate_object then null;
end $$;


-- ═══════════════════════════════════════════════════════════
-- 2. functions.sql
-- ═══════════════════════════════════════════════════════════

-- Additional Postgres function(s) — run this in Supabase SQL Editor
-- AFTER schema.sql.

-- Atomically decrements a product's stock (a single UPDATE ... SET
-- stock = stock - qty is inherently atomic per row in Postgres, so this
-- safely handles two simultaneous orders without oversell — the same
-- guarantee the old Firestore transaction gave us).
create or replace function decrement_stock(p_id text, qty int)
returns void
language sql
as $$
  update products set stock = stock - qty where id = p_id;
$$;


-- ═══════════════════════════════════════════════════════════
-- 3. categories.sql
-- ═══════════════════════════════════════════════════════════

-- Product categories — run this in Supabase SQL Editor after schema.sql.

create table if not exists categories (
  id text primary key,
  resto_id text not null references restaurants(id),
  name text not null
);
create index if not exists idx_categories_resto on categories(resto_id);

alter table categories enable row level security;
create policy "public read/write categories" on categories for all using (true) with check (true);


-- ═══════════════════════════════════════════════════════════
-- 4. cron.sql
-- ═══════════════════════════════════════════════════════════

-- Auto-end idle sessions — pure SQL + pg_cron, no Edge Function needed.
-- Run this in Supabase SQL Editor AFTER schema.sql and functions.sql.
--
-- First enable the pg_cron extension: Dashboard > Database > Extensions
-- > search "pg_cron" > Enable. Then run this file.

create extension if not exists pg_cron with schema extensions;

create or replace function auto_end_idle_sessions()
returns void
language plpgsql
as $$
begin
  update sessions s
  set active = false
  where s.active = true
    and s.last_order_at is not null
    and s.last_order_at <= now() - interval '5 minutes'
    -- has at least one order
    and exists (select 1 from orders o where o.session_id = s.id)
    -- and every order in it is done
    and not exists (
      select 1 from orders o
      where o.session_id = s.id and o.kitchen_status <> 'done'
    );
end;
$$;

-- Runs every 5 minutes, forever, entirely inside the free Supabase plan.
select cron.schedule(
  'auto-end-idle-sessions',
  '*/5 * * * *',
  $$select auto_end_idle_sessions();$$
);


-- ═══════════════════════════════════════════════════════════
-- 5. product_level_groups.sql
-- ═══════════════════════════════════════════════════════════

-- Adds the "level/varian" tagging to products (e.g. which products offer
-- a spice level, sugar level, etc.), plus optional per-option price
-- deltas (e.g. "Ukuran: Large" adds Rp 5.000 on top of the base price).
-- Group/option names themselves are hardcoded in the app (kLevelGroups) —
-- only which groups apply, and each option's price delta, are stored here.
alter table products add column if not exists level_groups text;
alter table products add column if not exists level_prices text; -- JSON: {"Ukuran": {"Regular": 0, "Large": 5000}}


-- ═══════════════════════════════════════════════════════════
-- 6. product_photo_desc.sql
-- ═══════════════════════════════════════════════════════════

-- Adds description + photo_base64 columns to products — run in Supabase SQL Editor.
alter table products add column if not exists description text;
alter table products add column if not exists photo_base64 text;


-- ═══════════════════════════════════════════════════════════
-- 7. restaurant_category.sql
-- ═══════════════════════════════════════════════════════════

-- Adds a category column to restaurants — run in Supabase SQL Editor.
alter table restaurants add column if not exists category text;


-- ═══════════════════════════════════════════════════════════
-- 8. seed_products.sql
-- ═══════════════════════════════════════════════════════════

-- Seeds realistic Indonesian F&B categories + products.
-- IMPORTANT: replace 'resto-1' below with YOUR actual resto_id
-- (the same value used in your employees table's resto_id column)
-- before running this in Supabase SQL Editor.
--
-- After running, open the app as Admin/Kasir once — it automatically
-- pulls any new products/categories from Supabase into the local
-- device database (see ProductProvider.pullNewProductsFromFirestore /
-- CategoryProvider.pullNewFromSupabase).

do $$
declare
  v_resto_id text := 'resto-1'; -- <-- change this
begin

insert into categories (id, resto_id, name) values
  (gen_random_uuid()::text, v_resto_id, 'Makanan Utama'),
  (gen_random_uuid()::text, v_resto_id, 'Ayam & Bebek'),
  (gen_random_uuid()::text, v_resto_id, 'Seafood'),
  (gen_random_uuid()::text, v_resto_id, 'Mie & Bakmi'),
  (gen_random_uuid()::text, v_resto_id, 'Cemilan'),
  (gen_random_uuid()::text, v_resto_id, 'Dessert'),
  (gen_random_uuid()::text, v_resto_id, 'Kopi & Teh'),
  (gen_random_uuid()::text, v_resto_id, 'Minuman')
on conflict do nothing;

insert into products (id, resto_id, name, category, price, stock, description) values
  (gen_random_uuid()::text, v_resto_id, 'Nasi Goreng Spesial', 'Makanan Utama', 25000, 20, 'Nasi goreng dengan telur, ayam suwir, dan kerupuk.'),
  (gen_random_uuid()::text, v_resto_id, 'Nasi Uduk Komplit', 'Makanan Utama', 22000, 15, 'Nasi uduk gurih dengan ayam goreng, tempe, dan sambal.'),
  (gen_random_uuid()::text, v_resto_id, 'Nasi Campur Bali', 'Makanan Utama', 28000, 12, 'Nasi dengan lauk pauk khas Bali, ayam sisit, dan sambal matah.'),
  (gen_random_uuid()::text, v_resto_id, 'Gado-Gado', 'Makanan Utama', 20000, 18, 'Sayuran segar dengan siraman bumbu kacang khas.'),
  (gen_random_uuid()::text, v_resto_id, 'Soto Ayam', 'Makanan Utama', 23000, 15, 'Soto ayam kuah bening dengan suwiran ayam dan telur.'),

  (gen_random_uuid()::text, v_resto_id, 'Ayam Geprek Sambal Bawang', 'Ayam & Bebek', 24000, 25, 'Ayam goreng crispy digeprek dengan sambal bawang pedas.'),
  (gen_random_uuid()::text, v_resto_id, 'Ayam Bakar Madu', 'Ayam & Bebek', 27000, 15, 'Ayam bakar dengan bumbu madu manis gurih.'),
  (gen_random_uuid()::text, v_resto_id, 'Bebek Goreng Sambal Ijo', 'Ayam & Bebek', 32000, 10, 'Bebek goreng renyah dengan sambal ijo khas Minang.'),
  (gen_random_uuid()::text, v_resto_id, 'Ayam Penyet', 'Ayam & Bebek', 23000, 18, 'Ayam goreng penyet dengan sambal terasi pedas.'),

  (gen_random_uuid()::text, v_resto_id, 'Cumi Goreng Tepung', 'Seafood', 30000, 12, 'Cumi segar digoreng garing dengan bumbu spesial.'),
  (gen_random_uuid()::text, v_resto_id, 'Udang Saus Padang', 'Seafood', 35000, 10, 'Udang segar dimasak dengan saus padang pedas manis.'),
  (gen_random_uuid()::text, v_resto_id, 'Ikan Bakar Kecap', 'Seafood', 33000, 10, 'Ikan segar dibakar dengan bumbu kecap manis.'),

  (gen_random_uuid()::text, v_resto_id, 'Mie Ayam Bakso', 'Mie & Bakmi', 20000, 20, 'Mie ayam dengan topping bakso dan pangsit.'),
  (gen_random_uuid()::text, v_resto_id, 'Mie Goreng Jawa', 'Mie & Bakmi', 21000, 15, 'Mie goreng dengan bumbu rempah khas Jawa.'),
  (gen_random_uuid()::text, v_resto_id, 'Kwetiau Goreng', 'Mie & Bakmi', 23000, 12, 'Kwetiau goreng dengan telur, ayam, dan sayuran.'),

  (gen_random_uuid()::text, v_resto_id, 'Tahu Isi', 'Cemilan', 10000, 25, 'Tahu goreng isi sayuran, disajikan dengan cabai rawit.'),
  (gen_random_uuid()::text, v_resto_id, 'Pisang Goreng Coklat Keju', 'Cemilan', 15000, 20, 'Pisang goreng crispy dengan topping coklat dan keju.'),
  (gen_random_uuid()::text, v_resto_id, 'Kentang Goreng', 'Cemilan', 15000, 25, 'Kentang goreng renyah dengan saus sambal/mayones.'),
  (gen_random_uuid()::text, v_resto_id, 'Tempe Mendoan', 'Cemilan', 10000, 22, 'Tempe goreng tepung khas Banyumas, gurih dan renyah.'),

  (gen_random_uuid()::text, v_resto_id, 'Es Krim Goreng', 'Dessert', 18000, 12, 'Es krim vanilla dibalut roti crispy, disajikan dingin.'),
  (gen_random_uuid()::text, v_resto_id, 'Puding Coklat', 'Dessert', 12000, 15, 'Puding coklat lembut dengan saus vanilla.'),
  (gen_random_uuid()::text, v_resto_id, 'Klepon', 'Dessert', 10000, 20, 'Klepon isi gula merah dengan taburan kelapa parut.'),

  (gen_random_uuid()::text, v_resto_id, 'Kopi Susu Gula Aren', 'Kopi & Teh', 18000, 30, 'Kopi susu dengan gula aren asli, creamy dan manis.'),
  (gen_random_uuid()::text, v_resto_id, 'Es Teh Manis', 'Kopi & Teh', 8000, 40, 'Teh manis segar disajikan dingin.'),
  (gen_random_uuid()::text, v_resto_id, 'Americano', 'Kopi & Teh', 15000, 25, 'Kopi hitam americano, cocok untuk yang suka rasa kopi murni.'),
  (gen_random_uuid()::text, v_resto_id, 'Matcha Latte', 'Kopi & Teh', 20000, 15, 'Matcha premium dengan susu creamy.'),

  (gen_random_uuid()::text, v_resto_id, 'Es Jeruk Peras', 'Minuman', 12000, 20, 'Jeruk peras segar tanpa pengawet.'),
  (gen_random_uuid()::text, v_resto_id, 'Es Campur', 'Minuman', 17000, 15, 'Es campur dengan buah-buahan segar dan sirup.'),
  (gen_random_uuid()::text, v_resto_id, 'Jus Alpukat', 'Minuman', 16000, 15, 'Jus alpukat creamy dengan coklat.'),
  (gen_random_uuid()::text, v_resto_id, 'Air Mineral', 'Minuman', 5000, 50, 'Air mineral dalam kemasan botol.')
on conflict do nothing;

end $$;


-- ═══════════════════════════════════════════════════════════
-- 9. rls_hardening.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — RLS hardening (run in Supabase SQL Editor AFTER schema.sql,
-- functions.sql, categories.sql, and the other supabase/*.sql files).
--
-- Replaces the permissive `using (true) with check (true)` policies with
-- ones scoped to: (a) each resto's own active employees for management
-- writes, and (b) each customer's own row for profile data — while
-- keeping the guest self-order flow (no login required) fully working,
-- since that flow never carries a Supabase Auth session.
--
-- IMPORTANT — bootstrapping: because `employees` writes now require an
-- existing active admin, you must add your FIRST admin manually via the
-- Supabase Dashboard (Table Editor > employees > Insert row), or via the
-- SQL Editor:
--   insert into employees (email, role, resto_id, active)
--   values ('you@gmail.com', 'admin', 'your-resto-id', true);
-- The dashboard/SQL editor runs as the Postgres owner, which bypasses
-- RLS — every admin after that first one can be added from inside the
-- app as normal.

-- ── Helper: is the currently-authenticated user an active employee of
-- ── [p_resto_id] with one of [p_roles]? SECURITY DEFINER so it can read
-- ── the employees table internally without re-triggering that table's
-- ── own RLS policy (which would otherwise recurse).
create or replace function is_resto_employee(p_resto_id text, p_roles text[] default array['admin','kasir','chef'])
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
      and e.role = any(p_roles)
  );
$$;

-- Make the stock-decrement RPC bypass RLS (SECURITY DEFINER) so guest
-- self-orders (no auth session) can still decrement stock even though
-- direct UPDATEs on products are now restricted to employees below.
create or replace function decrement_stock(p_id text, qty int)
returns void
language sql
security definer
set search_path = public
as $$
  update products set stock = greatest(stock - qty, 0) where id = p_id;
$$;

-- ── restaurants ──────────────────────────────────────────────────────
drop policy if exists "public read/write restaurants" on restaurants;
create policy "restaurants: public read" on restaurants
  for select using (true);
create policy "restaurants: admin update own" on restaurants
  for update using (is_resto_employee(id, array['admin']))
  with check (is_resto_employee(id, array['admin']));
-- No insert policy: creating a new restaurant row must be done via the
-- Dashboard/SQL Editor (service role) — there's no "admin of it" yet.

-- ── employees ────────────────────────────────────────────────────────
drop policy if exists "public read/write employees" on employees;
create policy "employees: read own or admin of resto" on employees
  for select using (
    email = auth.jwt()->>'email'
    or is_resto_employee(resto_id, array['admin'])
  );
create policy "employees: admin insert" on employees
  for insert with check (is_resto_employee(resto_id, array['admin']));
create policy "employees: admin update" on employees
  for update using (is_resto_employee(resto_id, array['admin']))
  with check (is_resto_employee(resto_id, array['admin']));
create policy "employees: admin delete" on employees
  for delete using (is_resto_employee(resto_id, array['admin']));

-- ── products ─────────────────────────────────────────────────────────
drop policy if exists "public read/write products" on products;
create policy "products: public read" on products
  for select using (true);
create policy "products: employees insert" on products
  for insert with check (is_resto_employee(resto_id, array['admin','kasir']));
create policy "products: employees update" on products
  for update using (is_resto_employee(resto_id, array['admin','kasir']))
  with check (is_resto_employee(resto_id, array['admin','kasir']));
create policy "products: employees delete" on products
  for delete using (is_resto_employee(resto_id, array['admin','kasir']));
-- Guest self-order stock decrements go through decrement_stock() above
-- (SECURITY DEFINER), so they still work without an employees insert/
-- update policy covering anonymous requests.

-- ── orders ───────────────────────────────────────────────────────────
drop policy if exists "public read/write orders" on orders;
-- Reads stay public: the Chef/Admin dashboard needs to see every order
-- for its resto, and the guest order-status screen watches by
-- session_id (an unguessable UUID) without any auth session to scope
-- against. This is a deliberate trade-off of this app's "no login
-- required to order" design — treat session_id like a bearer token.
create policy "orders: public read" on orders
  for select using (true);
-- Inserts stay public: guest checkout has no auth session either.
create policy "orders: public insert" on orders
  for insert with check (true);
-- Updates (kitchen_status, payment_status, ...) are now employee-only —
-- this is the fix for guests being able to mark their own order "paid"
-- by hitting the API directly instead of actually paying.
create policy "orders: employees update" on orders
  for update using (is_resto_employee(resto_id, array['admin','kasir','chef']))
  with check (is_resto_employee(resto_id, array['admin','kasir','chef']));
create policy "orders: admin delete" on orders
  for delete using (is_resto_employee(resto_id, array['admin']));

-- ── sessions ─────────────────────────────────────────────────────────
drop policy if exists "public read/write sessions" on sessions;
-- Reads/inserts/updates stay public: scanning a table QR (creating/
-- resuming a session) and the idle-timer "touch" both happen with no
-- auth session, same trade-off as orders above.
create policy "sessions: public read" on sessions
  for select using (true);
create policy "sessions: public insert" on sessions
  for insert with check (true);
create policy "sessions: public update" on sessions
  for update using (true) with check (true);
create policy "sessions: employees delete" on sessions
  for delete using (is_resto_employee(resto_id, array['admin','kasir']));

-- ── settings (QRIS/bank info) ───────────────────────────────────────
drop policy if exists "public read/write settings" on settings;
create policy "settings: public read" on settings
  for select using (true);
create policy "settings: admin insert" on settings
  for insert with check (is_resto_employee(resto_id, array['admin']));
create policy "settings: admin update" on settings
  for update using (is_resto_employee(resto_id, array['admin']))
  with check (is_resto_employee(resto_id, array['admin']));

-- ── customers (profile: name/phone/photo) ───────────────────────────
drop policy if exists "public read/write customers" on customers;
create policy "customers: own row only" on customers
  for all using (email = auth.jwt()->>'email')
  with check (email = auth.jwt()->>'email');

-- ── mail_requests (email-receipt queue) ─────────────────────────────
drop policy if exists "public read/write mail_requests" on mail_requests;
-- Insert-only from the client; the send-receipt Edge Function processes
-- the queue using the service role key, which bypasses RLS entirely —
-- so no select/update/delete policy is needed (and none is granted).
create policy "mail_requests: public insert" on mail_requests
  for insert with check (true);


-- ═══════════════════════════════════════════════════════════
-- 10. super_admin.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Super Admin role (run AFTER rls_hardening.sql).
--
-- Adds a 'super_admin' role that isn't tied to any single restaurant —
-- it can manage employees for ANY resto and create new restos from
-- inside the app (regular Admins can only manage their own resto's
-- employees, and can't create new restos at all).
--
-- BOOTSTRAPPING: just like the first regular Admin, the first Super
-- Admin must be inserted manually via the Dashboard/SQL Editor (which
-- runs as the Postgres owner and bypasses RLS):
--   insert into employees (email, role, resto_id, active)
--   values ('you@gmail.com', 'super_admin', null, true);

-- Allow resto_id to be null (a Super Admin isn't scoped to one resto)
-- and allow the new role value.
alter table employees alter column resto_id drop not null;
alter table employees drop constraint if exists employees_role_check;
alter table employees add constraint employees_role_check
  check (role in ('admin', 'kasir', 'chef', 'super_admin', 'finance', 'owner'));

-- ── Helper: is the currently-authenticated user an active super_admin?
create or replace function is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from employees e
    where e.email = auth.jwt()->>'email'
      and e.role = 'super_admin'
      and e.active = true
  );
$$;

-- ── employees: let super_admin manage any resto's employees ─────────
drop policy if exists "employees: read own or admin of resto" on employees;
create policy "employees: read own, resto admin, or super_admin" on employees
  for select using (
    email = auth.jwt()->>'email'
    or is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

drop policy if exists "employees: admin insert" on employees;
create policy "employees: admin or super_admin insert" on employees
  for insert with check (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

drop policy if exists "employees: admin update" on employees;
create policy "employees: admin or super_admin update" on employees
  for update using (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  )
  with check (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

drop policy if exists "employees: admin delete" on employees;
create policy "employees: admin or super_admin delete" on employees
  for delete using (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

-- ── restaurants: let super_admin create new restos + edit any resto ──
create policy "restaurants: super_admin insert" on restaurants
  for insert with check (is_super_admin());

drop policy if exists "restaurants: admin update own" on restaurants;
create policy "restaurants: admin or super_admin update" on restaurants
  for update using (is_super_admin() or is_resto_employee(id, array['admin']))
  with check (is_super_admin() or is_resto_employee(id, array['admin']));


-- ═══════════════════════════════════════════════════════════
-- 11. finance.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Finance role (run AFTER rls_hardening.sql and super_admin.sql).
--
-- Adds:
--   - 'finance' as an allowed employees.role (scoped to one resto, like
--     admin/kasir/chef — NOT global like super_admin).
--   - gl_accounts: per-resto GL account code/name mapping for each of the
--     3 payment methods (cash/qris/transfer), so income can be booked to
--     the right account.
--   - expenses: per-resto expense entries (reduces the balance shown in
--     the Finance app).
--
-- Balance is computed on the fly (sum of paid orders − sum of expenses)
-- rather than stored, so it's always consistent with the underlying data.

alter table employees drop constraint if exists employees_role_check;
alter table employees add constraint employees_role_check
  check (role in ('admin', 'kasir', 'chef', 'super_admin', 'finance', 'owner'));

create table if not exists gl_accounts (
  resto_id text not null references restaurants(id),
  payment_method text not null check (payment_method in ('cash', 'qris', 'transfer')),
  gl_code text not null,
  gl_name text not null,
  primary key (resto_id, payment_method)
);

create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  amount integer not null check (amount > 0),
  description text not null,
  gl_code text,
  created_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_expenses_resto on expenses(resto_id);

alter table gl_accounts enable row level security;
alter table expenses enable row level security;

-- Finance (and Admin, who oversees Finance) can read/write their own
-- resto's GL mapping and expenses. Nobody else (including other
-- employee roles or the public) has any access — no policy means denied
-- by default once RLS is enabled.
create policy "gl_accounts: finance/admin read" on gl_accounts
  for select using (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "gl_accounts: finance/admin write" on gl_accounts
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "gl_accounts: finance/admin update" on gl_accounts
  for update using (is_resto_employee(resto_id, array['admin', 'finance']))
  with check (is_resto_employee(resto_id, array['admin', 'finance']));

create policy "expenses: finance/admin read" on expenses
  for select using (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "expenses: finance/admin insert" on expenses
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "expenses: finance/admin delete" on expenses
  for delete using (is_resto_employee(resto_id, array['admin', 'finance']));


-- ═══════════════════════════════════════════════════════════
-- 12. customer_browse_resto.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — lets a customer browse a resto's menu by picking it from a
-- list (instead of only via table QR scan). No table is known yet in
-- that case, so `sessions.table_number` must be nullable — it gets
-- filled in later, mandatorily, at checkout.
alter table sessions alter column table_number drop not null;


-- ═══════════════════════════════════════════════════════════
-- 13. expense_gl_accounts.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — GL account chart for EXPENSES (run AFTER finance.sql).
--
-- Separate from `gl_accounts` (which maps each of the 3 fixed payment
-- methods — cash/qris/transfer — to exactly one GL code each, for
-- INCOME). Expenses commonly need many categories (Sewa, Gaji, Bahan
-- Baku, ...), so this is its own list Finance can add/remove from,
-- offered as the GL dropdown when recording an expense.
create table if not exists expense_gl_accounts (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  gl_code text not null,
  gl_name text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_expense_gl_accounts_resto on expense_gl_accounts(resto_id);

alter table expense_gl_accounts enable row level security;

create policy "expense_gl_accounts: finance/admin read" on expense_gl_accounts
  for select using (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "expense_gl_accounts: finance/admin insert" on expense_gl_accounts
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "expense_gl_accounts: finance/admin delete" on expense_gl_accounts
  for delete using (is_resto_employee(resto_id, array['admin', 'finance']));


-- ═══════════════════════════════════════════════════════════
-- 14. order_type.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — adds Dine In / Take Away to orders, chosen at checkout by
-- both the customer app and the Kasir.
alter table orders add column if not exists order_type text not null default 'dine_in'
  check (order_type in ('dine_in', 'take_away'));


-- ═══════════════════════════════════════════════════════════
-- 15. employee_name_nip.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — adds Nama (name) and NIP (employee ID number) to employees.
alter table employees add column if not exists name text;
alter table employees add column if not exists nip text;


-- ═══════════════════════════════════════════════════════════
-- 16. restaurant_active.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — lets Super Admin activate/deactivate a restaurant.
-- Inactive restos: hidden from the customer's "Pilih Resto" list, and
-- their employees are blocked from logging in (see AuthProvider).
alter table restaurants add column if not exists active boolean not null default true;


-- ═══════════════════════════════════════════════════════════
-- 17. mark_order_paid.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — fixes customer QRIS "Simulasikan: Sudah Dibayar" silently
-- failing after rls_hardening.sql restricted orders UPDATE to employees
-- only. This RPC lets a guest (no auth session) flip THEIR OWN pending
-- self-order to paid, without reopening the door rls_hardening.sql
-- closed — the guardrails are baked into the function itself:
--   - only source = 'customer' orders (never a Kasir-rung sale)
--   - only from 'pending' to 'paid' (can't touch an order some other way)
-- SECURITY DEFINER so it bypasses the orders UPDATE RLS policy (which
-- still correctly blocks direct table updates from anon/guest clients).
create or replace function mark_order_paid(p_order_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update orders
  set payment_status = 'paid'
  where id = p_order_id
    and source = 'customer'
    and payment_status = 'pending';
$$;


-- ═══════════════════════════════════════════════════════════
-- 18. order_customer_name.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — customer name for pickup, required for Take Away orders
-- (dine-in doesn't need it — the table number identifies them instead).
alter table orders add column if not exists customer_name text;


-- ═══════════════════════════════════════════════════════════
-- 19. settings_finance_access.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — lets Finance edit payment settings too (previously admin-only).
-- Admin's own "Pengaturan Pembayaran" screen is now view-only in the
-- app; Finance is the one who actually edits it.
drop policy if exists "settings: admin insert" on settings;
create policy "settings: admin or finance insert" on settings
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance']));

drop policy if exists "settings: admin update" on settings;
create policy "settings: admin or finance update" on settings
  for update using (is_resto_employee(resto_id, array['admin', 'finance']))
  with check (is_resto_employee(resto_id, array['admin', 'finance']));


-- ═══════════════════════════════════════════════════════════
-- 20. backfill_journal.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Backfill jurnal untuk transaksi yang sudah ada
-- (run AFTER journal_integrity.sql).
--
-- The journal triggers only fire on new activity, so everything recorded
-- before those triggers existed has no journal rows at all. This script
-- generates them retroactively.
--
-- Two things make it safe to run more than once:
--   - every insert is guarded by a NOT EXISTS on the same
--     (reference_type, reference_id, entry_type), so nothing doubles up;
--   - entry_date/entry_time come from each record's own created_at (in
--     WIB), not now() — so the backfilled history lands on the day it
--     actually happened instead of the day you ran this.
--
-- Rows whose GL account isn't mapped yet are simply skipped (the JOIN
-- finds nothing). Set the mapping in Mapping GL Account first, then
-- re-run this — the guards make that harmless.

-- ---------------------------------------------------------------------
-- 1. Paid orders → credit the income GL for their payment method
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  o.resto_id,
  (o.created_at at time zone 'Asia/Jakarta')::date,
  (o.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'order', o.id::text, o.total, 'credit',
  'Pemasukan pesanan #' || upper(substr(o.id::text, 1, 8))
from orders o
join gl_accounts g
  on g.resto_id = o.resto_id
 and g.payment_method = _normalize_payment_method(o.source, o.payment_method)
where o.payment_status = 'paid'
  and coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'order'
      and j.reference_id = o.id::text
      and j.entry_type = 'credit'
  );

-- ---------------------------------------------------------------------
-- 2. Expenses → debit their own GL category
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  e.resto_id,
  (e.created_at at time zone 'Asia/Jakarta')::date,
  (e.created_at at time zone 'Asia/Jakarta')::time,
  e.gl_code, eg.gl_name,
  'expense', e.id::text, e.amount, 'debit', e.description
from expenses e
join expense_gl_accounts eg
  on eg.resto_id = e.resto_id
 and eg.gl_code = e.gl_code
where coalesce(e.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'expense'
      and j.reference_id = e.id::text
      and j.entry_type = 'debit'
  );

-- ---------------------------------------------------------------------
-- 3. Expenses → credit GL Petty Cash (the balance that funded them)
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  e.resto_id,
  (e.created_at at time zone 'Asia/Jakarta')::date,
  (e.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'expense', e.id::text, e.amount, 'credit', 'Dana dari Petty Cash'
from expenses e
join gl_accounts g
  on g.resto_id = e.resto_id
 and g.payment_method = 'petty_cash'
where coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'expense'
      and j.reference_id = e.id::text
      and j.entry_type = 'credit'
  );

-- ---------------------------------------------------------------------
-- 4. Petty Cash top-ups → debit GL Petty Cash
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  p.resto_id,
  (p.created_at at time zone 'Asia/Jakarta')::date,
  (p.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'petty_cash', p.id::text, p.amount, 'debit',
  case
    when p.source = 'income_withdrawal' then 'Withdraw dari Penghasilan ke Petty Cash'
    else 'Top Up Petty Cash (Manual)'
  end
from petty_cash_entries p
join gl_accounts g
  on g.resto_id = p.resto_id
 and g.payment_method = 'petty_cash'
where coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'petty_cash'
      and j.reference_id = p.id::text
      and j.entry_type = 'debit'
  );

-- ---------------------------------------------------------------------
-- 5. Petty Cash withdrawals → credit GL Penghasilan
--    (manual top-ups are outside capital, so they have no counter-account)
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  p.resto_id,
  (p.created_at at time zone 'Asia/Jakarta')::date,
  (p.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'petty_cash', p.id::text, p.amount, 'credit', 'Withdraw ke Petty Cash'
from petty_cash_entries p
join gl_accounts g
  on g.resto_id = p.resto_id
 and g.payment_method = 'income_aggregate'
where p.source = 'income_withdrawal'
  and coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'petty_cash'
      and j.reference_id = p.id::text
      and j.entry_type = 'credit'
  );

-- ---------------------------------------------------------------------
-- Ringkasan hasil backfill
-- ---------------------------------------------------------------------

select
  reference_type as "Jenis",
  entry_type as "Debit/Kredit",
  count(*) as "Jumlah Baris",
  sum(amount) as "Total"
from gl_journal_entries
where is_reversal = false
group by reference_type, entry_type
order by reference_type, entry_type;


-- ═══════════════════════════════════════════════════════════
-- 21. claim_guest_orders.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — mengalihkan riwayat pesanan tamu ke email yang baru login
-- (run AFTER rls_hardening.sql).
--
-- A guest's orders are labelled 'Tamu' and only tracked by ids saved on
-- their own device (see lib/db/guest_order_store.dart). When that person
-- later signs in, those orders should follow them — but only when the
-- email is genuinely new to MerchantPOS. If the email already has history,
-- the two are left completely separate: the account keeps its own
-- orders, and the guest list stays on the device so it's still there
-- after logging out again.
--
-- Needs SECURITY DEFINER because rls_hardening.sql restricts UPDATE on
-- `orders` to employees — a customer has no such privilege. The
-- guardrails that make that safe are all inside the function:
--
--   - the target email is read from the caller's own JWT, never passed
--     in, so nobody can claim orders into someone else's account;
--   - only rows still labelled 'Tamu' are touched, so an order already
--     belonging to an account can't be stolen;
--   - only source = 'customer' rows, never a Kasir-rung sale;
--   - nothing happens at all if the email already has any orders.
--
-- Returns how many orders were claimed (0 when the email already had
-- history), which is what the app uses to decide whether to clear its
-- local guest list.
create or replace function claim_guest_orders(p_order_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_claimed integer;
begin
  if v_email is null or v_email = '' then
    raise exception 'Harus login untuk mengklaim riwayat pesanan';
  end if;

  if p_order_ids is null or array_length(p_order_ids, 1) is null then
    return 0;
  end if;

  -- Existing account: leave both histories exactly as they are.
  if exists (select 1 from orders where customer_label = v_email) then
    return 0;
  end if;

  update orders
  set customer_label = v_email
  where id = any(p_order_ids)
    and source = 'customer'
    and customer_label = 'Tamu';

  get diagnostics v_claimed = row_count;
  return v_claimed;
end;
$$;


-- ═══════════════════════════════════════════════════════════
-- 22. expense_receipt.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — bukti pengeluaran (run AFTER finance.sql).
--
-- Optional photo of the receipt/nota backing an expense, stored as a
-- base64 string in the row itself — the same approach products already
-- use for their photos, so there's no storage bucket to provision or
-- keep permissions in sync with.
--
-- The app downsizes to 900px wide at 70% JPEG before encoding (see
-- FinanceBalanceScreen), which keeps a receipt readable while landing
-- well inside Postgres' row limits. Nullable because attaching one is
-- entirely optional.
alter table expenses add column if not exists receipt_base64 text;


-- ═══════════════════════════════════════════════════════════
-- 23. gl_journal.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — GL Journal (run AFTER finance.sql; petty_cash.sql not required).
--
-- One table capturing every real money movement, written automatically
-- by triggers rather than the app deciding when to log it — so it stays
-- consistent no matter which flow marks an order paid (Kasir sale,
-- customer QRIS "Simulasikan: Sudah Dibayar", the mark_order_paid RPC),
-- and no matter which screen records an expense.
--
-- Only orders/expenses that actually resolve to a configured GL account
-- get journaled (Mapping GL Account for orders, an expense's own
-- optional GL tag for expenses) — nothing to book against otherwise.
create table if not exists gl_journal_entries (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  entry_date date not null,
  entry_time time not null,
  gl_code text not null,
  reference_type text not null check (reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));
create index if not exists idx_gl_journal_entries_resto on gl_journal_entries(resto_id);
create index if not exists idx_gl_journal_entries_ref on gl_journal_entries(reference_type, reference_id);

alter table gl_journal_entries enable row level security;

create policy "gl_journal_entries: finance/admin read" on gl_journal_entries
  for select using (is_resto_employee(resto_id, array['admin', 'finance']));
-- Deliberately no insert/update/delete policy for any role — every row
-- is written only by the SECURITY DEFINER trigger functions below, never
-- directly by the app, so the journal can't drift from what actually
-- happened on `orders`/`expenses`.

-- Normalizes an order into 'cash' | 'qris' | 'transfer', matching the
-- Dart-side `_methodKey()` in finance_income_screen.dart: customer
-- self-orders never set payment_method (always QRIS in practice), and
-- Kasir sales store the display label ('QRIS'/'Transfer'/'Tunai'), not
-- the lowercase key `gl_accounts` is keyed on.
create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_source = 'customer' then 'qris'
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    else 'cash'
  end;
$$;

create or replace function log_order_paid_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl_code text;
  v_now timestamptz := now();
  v_method text;
begin
  if new.payment_status = 'paid' then
    v_method := _normalize_payment_method(new.source, new.payment_method);
    select gl_code into v_gl_code
    from gl_accounts
    where resto_id = new.resto_id and payment_method = v_method
    limit 1;

    if v_gl_code is not null and v_gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id,
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl_code, 'order', new.id::text, new.total, 'credit',
        'Pemasukan pesanan #' || upper(substr(new.id::text, 1, 8))
      );
    end if;
  end if;
  return new;
end;
$$;

-- Covers both: an order inserted already-paid (Kasir sales always are),
-- and one that starts pending and flips to paid later (customer QRIS).
drop trigger if exists trg_log_order_paid_journal_insert on orders;
create trigger trg_log_order_paid_journal_insert
  after insert on orders
  for each row execute function log_order_paid_journal();

drop trigger if exists trg_log_order_paid_journal_update on orders;
create trigger trg_log_order_paid_journal_update
  after update of payment_status on orders
  for each row
  when (new.payment_status = 'paid' and old.payment_status is distinct from 'paid')
  execute function log_order_paid_journal();

create or replace function log_expense_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  if new.gl_code is not null and new.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id,
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      new.gl_code, 'expense', new.id::text, new.amount, 'debit', new.description
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_expense_journal on expenses;
create trigger trg_log_expense_journal
  after insert on expenses
  for each row execute function log_expense_journal();


-- ═══════════════════════════════════════════════════════════
-- 24. petty_cash.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Petty Cash ledger (run AFTER finance.sql).
--
-- Splits the Finance "Saldo & Pengeluaran" screen's single balance into
-- three named balances that sum to the total:
--   Saldo Total = Saldo Penghasilan + Saldo Petty Cash − Saldo Pengeluaran
--
--   - Saldo Penghasilan: sum of paid orders, minus whatever's been
--     withdrawn out of it into Petty Cash (an internal transfer, not a
--     real gain/loss, so it doesn't touch Saldo Total on its own).
--   - Saldo Petty Cash: a small manually-managed cash float. Funded either
--     by withdrawing from Saldo Penghasilan, or a manual top-up entry (for
--     day one, before any income has come in yet).
--   - Saldo Pengeluaran: sum of all recorded expenses (unchanged from
--     before — this table already existed, this migration just adds the
--     new petty_cash_entries table alongside it).
create table if not exists petty_cash_entries (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  amount integer not null check (amount > 0),
  source text not null check (source in ('manual', 'income_withdrawal')),
  description text,
  created_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_petty_cash_entries_resto on petty_cash_entries(resto_id);

alter table petty_cash_entries enable row level security;

create policy "petty_cash_entries: finance/admin read" on petty_cash_entries
  for select using (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "petty_cash_entries: finance/admin insert" on petty_cash_entries
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance']));
create policy "petty_cash_entries: finance/admin delete" on petty_cash_entries
  for delete using (is_resto_employee(resto_id, array['admin', 'finance']));


-- ═══════════════════════════════════════════════════════════
-- 25. journal_integrity.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Journal integrity (run AFTER orders_gl_code.sql and
-- petty_cash_journal.sql — this is the last finance migration).
--
-- Closes five gaps that made the GL journal untrustworthy:
--
--   1. DELETE wasn't journaled at all. Finance can delete an expense or a
--      petty cash entry from the app, which changed the computed balance
--      but left the original journal row untouched forever — so Saldo and
--      Jurnal silently diverged. Now every delete writes a REVERSAL row
--      (is_reversal = true) instead of erasing history.
--   2. The journal stored only gl_code, so the Jurnal GL screen showed a
--      bare number, and renaming/deleting a GL made old rows unreadable.
--      gl_name is now snapshotted onto each row at write time.
--   3. expenses.gl_code was free text with no relation to
--      expense_gl_accounts. Now a real FK — which also gives Finance the
--      validation they asked for: a GL Pengeluaran that already has
--      expenses booked against it can no longer be deleted (RESTRICT).
--   4. GL Total Saldo had no mapping slot. Added as another gl_accounts
--      payment_method row ('total_balance'), reported as a header summary
--      on the Jurnal GL screen rather than duplicating every row.
--   5. Expenses only ever wrote one side of the entry. Every expense is
--      paid out of Petty Cash, so the trigger now writes a balanced pair:
--      debit the expense category, credit GL Petty Cash.
--
-- DEBIT/CREDIT CONVENTION (standard double-entry, applied consistently):
--   revenue account  → credit when it grows (an order gets paid)
--   expense account  → debit when it grows (money spent on that category)
--   asset account    → debit when it grows, credit when it shrinks
-- This also FIXES petty_cash_journal.sql, which had the top-up pair
-- backwards (it credited the petty cash asset and debited the source).

-- ---------------------------------------------------------------------
-- 1. New columns
-- ---------------------------------------------------------------------

alter table gl_journal_entries add column if not exists gl_name text;
alter table gl_journal_entries add column if not exists is_reversal boolean not null default false;

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- ---------------------------------------------------------------------
-- 2. expenses.gl_code → expense_gl_accounts FK
-- ---------------------------------------------------------------------

-- Collapse any duplicate (resto_id, gl_code) rows in the chart first —
-- they'd block the unique constraint the FK needs. Keeps the oldest row
-- of each code and repoints nothing (expenses reference gl_code, not id).
delete from expense_gl_accounts a
using expense_gl_accounts b
where a.resto_id = b.resto_id
  and a.gl_code = b.gl_code
  and a.created_at > b.created_at;

alter table expense_gl_accounts drop constraint if exists expense_gl_accounts_resto_code_key;
alter table expense_gl_accounts add constraint expense_gl_accounts_resto_code_key
  unique (resto_id, gl_code);

-- Any expense pointing at a GL that was deleted from the chart earlier
-- would fail the FK. Restore those chart entries rather than nulling the
-- expense's gl_code — the historical link is real data worth keeping.
insert into expense_gl_accounts (resto_id, gl_code, gl_name)
select distinct e.resto_id, e.gl_code, 'GL ' || e.gl_code || ' (dipulihkan)'
from expenses e
where e.gl_code is not null
  and e.gl_code <> ''
  and not exists (
    select 1 from expense_gl_accounts g
    where g.resto_id = e.resto_id and g.gl_code = e.gl_code
  );

-- Empty-string gl_codes aren't a real reference — normalize to null so
-- the FK skips them (MATCH SIMPLE ignores rows with a null column).
update expenses set gl_code = null where gl_code = '';

alter table expenses drop constraint if exists expenses_gl_code_fkey;
alter table expenses add constraint expenses_gl_code_fkey
  foreign key (resto_id, gl_code)
  references expense_gl_accounts (resto_id, gl_code)
  on update cascade
  on delete restrict;

-- ---------------------------------------------------------------------
-- 3. Shared helper: resolve a GL code + name for a resto
-- ---------------------------------------------------------------------

-- Income/petty-cash/total GLs live in gl_accounts keyed by "payment
-- method"; expense GLs live in their own chart. Two lookups, one shape.
create or replace function _gl_account_for(p_resto_id text, p_payment_method text)
returns table (gl_code text, gl_name text)
language sql
stable
as $$
  select g.gl_code, g.gl_name
  from gl_accounts g
  where g.resto_id = p_resto_id and g.payment_method = p_payment_method
  limit 1;
$$;

create or replace function _expense_gl_account_for(p_resto_id text, p_gl_code text)
returns table (gl_code text, gl_name text)
language sql
stable
as $$
  select g.gl_code, g.gl_name
  from expense_gl_accounts g
  where g.resto_id = p_resto_id and g.gl_code = p_gl_code
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- 4. Order journaling — now also stores gl_name
-- ---------------------------------------------------------------------

create or replace function log_order_paid_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
  v_method text;
begin
  if new.payment_status = 'paid' then
    v_method := _normalize_payment_method(new.source, new.payment_method);
    select * into v_gl from _gl_account_for(new.resto_id, v_method);

    if v_gl.gl_code is not null and v_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id,
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl.gl_code, v_gl.gl_name, 'order', new.id::text, new.total, 'credit',
        'Pemasukan pesanan #' || upper(substr(new.id::text, 1, 8))
      );
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Expense journaling — balanced pair, always funded by Petty Cash
-- ---------------------------------------------------------------------

create or replace function log_expense_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense_gl record;
  v_petty_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
begin
  -- Debit side: the expense category itself grows.
  if new.gl_code is not null and new.gl_code <> '' then
    select * into v_expense_gl from _expense_gl_account_for(new.resto_id, new.gl_code);
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      new.gl_code, v_expense_gl.gl_name, 'expense', new.id::text,
      new.amount, 'debit', new.description
    );
  end if;

  -- Credit side: every expense is paid out of Petty Cash, so that asset
  -- shrinks by the same amount.
  select * into v_petty_gl from _gl_account_for(new.resto_id, 'petty_cash');
  if v_petty_gl.gl_code is not null and v_petty_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_petty_gl.gl_code, v_petty_gl.gl_name, 'expense', new.id::text,
      new.amount, 'credit', 'Dana dari Petty Cash'
    );
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. Petty cash journaling — direction corrected
-- ---------------------------------------------------------------------

create or replace function log_petty_cash_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petty_gl record;
  v_income_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
begin
  -- Petty cash is an asset: topping it up makes it grow → debit.
  select * into v_petty_gl from _gl_account_for(new.resto_id, 'petty_cash');
  if v_petty_gl.gl_code is not null and v_petty_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_petty_gl.gl_code, v_petty_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'debit',
      case
        when new.source = 'income_withdrawal' then 'Withdraw dari Penghasilan ke Petty Cash'
        else 'Top Up Petty Cash (Manual)'
      end
    );
  end if;

  -- A withdrawal drains the income balance → credit. A manual top-up is
  -- fresh capital from outside, so it has no counter-account here.
  if new.source = 'income_withdrawal' then
    select * into v_income_gl from _gl_account_for(new.resto_id, 'income_aggregate');
    if v_income_gl.gl_code is not null and v_income_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_income_gl.gl_code, v_income_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit', 'Withdraw ke Petty Cash'
      );
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. Reversals on delete
-- ---------------------------------------------------------------------

-- Mirrors every non-reversal row already booked against the deleted
-- record, with debit/credit flipped. History stays intact and the
-- running totals go back to where they were.
create or replace function _reverse_journal_for(p_reference_type text, p_reference_id text, p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description, is_reversal
  )
  select
    j.resto_id,
    (now() at time zone 'Asia/Jakarta')::date,
    (now() at time zone 'Asia/Jakarta')::time,
    j.gl_code, j.gl_name,
    j.reference_type, j.reference_id, j.amount,
    case when j.entry_type = 'debit' then 'credit' else 'debit' end,
    p_note, true
  from gl_journal_entries j
  where j.reference_type = p_reference_type
    and j.reference_id = p_reference_id
    and j.is_reversal = false
    -- Skip anything already reversed, so a re-run can't double-count.
    and not exists (
      select 1 from gl_journal_entries r
      where r.reference_type = j.reference_type
        and r.reference_id = j.reference_id
        and r.gl_code = j.gl_code
        and r.is_reversal = true
    );
end;
$$;

create or replace function log_expense_delete_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform _reverse_journal_for(
    'expense', old.id::text,
    'Pembatalan pengeluaran: ' || coalesce(old.description, '-')
  );
  return old;
end;
$$;

drop trigger if exists trg_log_expense_delete_journal on expenses;
create trigger trg_log_expense_delete_journal
  after delete on expenses
  for each row execute function log_expense_delete_journal();

create or replace function log_petty_cash_delete_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform _reverse_journal_for(
    'petty_cash', old.id::text,
    'Pembatalan Top Up Petty Cash'
  );
  return old;
end;
$$;

drop trigger if exists trg_log_petty_cash_delete_journal on petty_cash_entries;
create trigger trg_log_petty_cash_delete_journal
  after delete on petty_cash_entries
  for each row execute function log_petty_cash_delete_journal();

-- ---------------------------------------------------------------------
-- 8. Backfill gl_name onto rows written before this migration
-- ---------------------------------------------------------------------

update gl_journal_entries j
set gl_name = g.gl_name
from gl_accounts g
where j.gl_name is null
  and g.resto_id = j.resto_id
  and g.gl_code = j.gl_code;

update gl_journal_entries j
set gl_name = g.gl_name
from expense_gl_accounts g
where j.gl_name is null
  and g.resto_id = j.resto_id
  and g.gl_code = j.gl_code;


-- ═══════════════════════════════════════════════════════════
-- 26. kasir_balance_access.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Kasir bisa lihat saldo & catat pengeluaran
-- (run AFTER petty_cash.sql).
--
-- The Kasir holds the physical petty cash, so paying for small things
-- (galon, parkir, plastik) and writing them down is part of their shift.
-- This opens exactly that much and no more:
--
--   READ   expenses, expense_gl_accounts, petty_cash_entries
--   INSERT expenses
--
-- Deliberately NOT granted:
--   - inserting petty_cash_entries — topping the float up means moving
--     money out of income, which stays a Finance/Admin decision;
--   - deleting anything — a correction should go through Finance, and a
--     delete here would also write a reversal into the GL journal;
--   - gl_accounts — the GL mapping itself is none of the Kasir's
--     business, and the balance screen never reads it.
--
-- `settings` needs nothing: rls_hardening.sql already allows public read
-- (the customer app shows the QRIS details from it).

drop policy if exists "expenses: finance/admin read" on expenses;
create policy "expenses: finance/admin/kasir read" on expenses
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "expenses: finance/admin insert" on expenses;
create policy "expenses: finance/admin/kasir insert" on expenses
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "expense_gl_accounts: finance/admin read" on expense_gl_accounts;
create policy "expense_gl_accounts: finance/admin/kasir read" on expense_gl_accounts
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "petty_cash_entries: finance/admin read" on petty_cash_entries;
create policy "petty_cash_entries: finance/admin/kasir read" on petty_cash_entries
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));


-- ═══════════════════════════════════════════════════════════
-- 27. order_cashier_name.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — nama kasir/admin pada pesanan (run AFTER schema.sql).
--
-- Records who entered an order placed through the Kasir/Admin screen, so
-- a receipt and Riwayat Transaksi can name the person on shift.
--
-- Separate from `customer_label`, which for a Kasir sale holds that
-- employee's *email*. An email identifies the account but reads poorly on
-- a printed receipt, and it's the wrong thing to show a customer.
--
-- Null for customer self-orders — nobody entered those on their behalf.
alter table orders add column if not exists cashier_name text;


-- ═══════════════════════════════════════════════════════════
-- 28. orders_gl_code.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — orders.gl_code (run AFTER gl_journal.sql — reuses its
-- _normalize_payment_method() helper).
--
-- Adds a `gl_code` column directly on `orders`, kept in sync by trigger
-- rather than looked up ad hoc each time: the moment an order's
-- payment_method is known (or it's a customer self-order, always QRIS),
-- its gl_code is filled in from that resto's Mapping GL Account
-- (`gl_accounts.gl_code`, joined on the normalized payment_method) —
-- e.g. an order with payment_method = 'qris' gets whatever gl_code this
-- resto has mapped to QRIS. Stays null if that GL isn't configured yet.
--
-- This is the "flat" per-order record (handy for exports/filtering
-- directly on `orders`); gl_journal_entries (see gl_journal.sql) is the
-- append-only ledger of the same fact, journaled only once payment_status
-- actually reaches 'paid'. The two don't conflict: this column reflects
-- the *intended* GL as soon as it's knowable, the journal reflects money
-- that's *actually* moved.

alter table orders add column if not exists gl_code text;

-- Fixes _normalize_payment_method() (originally from gl_journal.sql):
-- orders.payment_method is now written as the lowercase gl_accounts key
-- directly ('cash'/'qris'/'transfer' — see cart_provider.dart and
-- customer_cart_provider.dart) instead of the display label, but the
-- old function only recognized the capitalized labels and silently
-- mapped any lowercase 'qris'/'transfer' to 'cash'. This still honors
-- the old capitalized labels too, for orders recorded before that
-- change. Safe to rerun even if gl_journal.sql already defined this.
create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_source = 'customer' then 'qris'
    when p_payment_method in ('cash', 'qris', 'transfer') then p_payment_method
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    else 'cash'
  end;
$$;

create or replace function order_set_gl_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_method text;
begin
  v_method := _normalize_payment_method(new.source, new.payment_method);
  select gl_code into new.gl_code
  from gl_accounts
  where resto_id = new.resto_id and payment_method = v_method
  limit 1;
  return new;
end;
$$;

drop trigger if exists trg_order_set_gl_code_insert on orders;
create trigger trg_order_set_gl_code_insert
  before insert on orders
  for each row execute function order_set_gl_code();

drop trigger if exists trg_order_set_gl_code_update on orders;
create trigger trg_order_set_gl_code_update
  before update of payment_method, payment_status on orders
  for each row execute function order_set_gl_code();

-- Backfill every existing order with whatever GL is mapped today.
update orders o
set gl_code = (
  select g.gl_code
  from gl_accounts g
  where g.resto_id = o.resto_id
    and g.payment_method = _normalize_payment_method(o.source, o.payment_method)
  limit 1
)
where o.gl_code is null;


-- ═══════════════════════════════════════════════════════════
-- 29. petty_cash_journal.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Petty Cash journal mapping (run AFTER petty_cash.sql and
-- gl_journal.sql).
--
-- Adds the two GL codes needed to journal Petty Cash movements, reusing
-- the existing `gl_accounts` table/screen (Mapping GL Account) instead
-- of a new one — just two more `payment_method` values alongside
-- cash/qris/transfer:
--   - 'petty_cash'       — GL Petty Cash itself (credited on every top-up)
--   - 'income_aggregate' — GL Penghasilan (debited only when the top-up's
--     source is a withdrawal FROM income — a manual top-up has no
--     income to debit against, it's fresh capital)
--
-- Journal convention stays the same as gl_journal.sql: a 'credit' row
-- means money arriving into that GL, a 'debit' row means money leaving
-- it — this app logs each account's movements individually rather than
-- full double-entry pairs, so a withdrawal produces two independent rows
-- (one debit, one credit) both pointing at the same petty_cash_entries
-- reference_id.

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

create or replace function log_petty_cash_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petty_cash_gl text;
  v_income_gl text;
  v_now timestamptz := now();
  v_desc text;
begin
  select gl_code into v_petty_cash_gl
  from gl_accounts
  where resto_id = new.resto_id and payment_method = 'petty_cash'
  limit 1;

  if v_petty_cash_gl is not null and v_petty_cash_gl <> '' then
    v_desc := case
      when new.source = 'income_withdrawal' then 'Withdraw dari Penghasilan ke Petty Cash'
      else 'Top Up Petty Cash (Manual)'
    end;

    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id,
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_petty_cash_gl, 'petty_cash', new.id::text, new.amount, 'credit', v_desc
    );
  end if;

  if new.source = 'income_withdrawal' then
    select gl_code into v_income_gl
    from gl_accounts
    where resto_id = new.resto_id and payment_method = 'income_aggregate'
    limit 1;

    if v_income_gl is not null and v_income_gl <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id,
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_income_gl, 'petty_cash', new.id::text, new.amount, 'debit',
        'Withdraw ke Petty Cash'
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_petty_cash_journal on petty_cash_entries;
create trigger trg_log_petty_cash_journal
  after insert on petty_cash_entries
  for each row execute function log_petty_cash_journal();


-- ═══════════════════════════════════════════════════════════
-- 30. rejournal.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Jurnal ulang (run AFTER journal_integrity.sql).
--
-- Rebuilds gl_journal_entries from scratch so every row follows the
-- current rules. Needed because two corrections landed after some
-- entries had already been written, and neither could be applied to
-- rows already in the table:
--
--   1. Petty Cash top-ups were journaled with debit and credit the wrong
--      way round (the asset was credited when it grew). journal_
--      integrity.sql fixed the trigger, but left existing rows as they
--      were.
--   2. Expenses only ever wrote their debit leg; the matching credit to
--      GL Petty Cash came later.
--
-- Re-running backfill_journal.sql does NOT repair (1): its guards skip a
-- record that already has a row for that entry_type, and a backwards
-- pair has both — so the wrong rows survive untouched and the fix looks
-- like it worked. Clearing the table first is what actually corrects it.
--
-- Safe to do: every row here is derived from orders / expenses /
-- petty_cash_entries and is regenerated below from those same tables,
-- with each entry's original created_at (in WIB) preserved, so dates and
-- times stay exactly where they were.
--
-- One thing does not come back: reversal pairs belonging to expenses or
-- Petty Cash entries that were deleted. Their source records are gone,
-- and the original plus its reversal summed to zero anyway, so no figure
-- changes — only those two audit lines disappear.
--
-- Must be run from the Supabase SQL Editor. The app itself has no delete
-- privilege on this table by design.

delete from gl_journal_entries;

-- ---------------------------------------------------------------------
-- 1. Paid orders → credit the income GL for their payment method
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  o.resto_id,
  (o.created_at at time zone 'Asia/Jakarta')::date,
  (o.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'order', o.id::text, o.total, 'credit',
  'Pemasukan pesanan #' || upper(substr(o.id::text, 1, 8))
from orders o
join gl_accounts g
  on g.resto_id = o.resto_id
 and g.payment_method = _normalize_payment_method(o.source, o.payment_method)
where o.payment_status = 'paid'
  and coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'order'
      and j.reference_id = o.id::text
      and j.entry_type = 'credit'
  );

-- ---------------------------------------------------------------------
-- 2. Expenses → debit their own GL category
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  e.resto_id,
  (e.created_at at time zone 'Asia/Jakarta')::date,
  (e.created_at at time zone 'Asia/Jakarta')::time,
  e.gl_code, eg.gl_name,
  'expense', e.id::text, e.amount, 'debit', e.description
from expenses e
join expense_gl_accounts eg
  on eg.resto_id = e.resto_id
 and eg.gl_code = e.gl_code
where coalesce(e.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'expense'
      and j.reference_id = e.id::text
      and j.entry_type = 'debit'
  );

-- ---------------------------------------------------------------------
-- 3. Expenses → credit GL Petty Cash (the balance that funded them)
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  e.resto_id,
  (e.created_at at time zone 'Asia/Jakarta')::date,
  (e.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'expense', e.id::text, e.amount, 'credit', 'Dana dari Petty Cash'
from expenses e
join gl_accounts g
  on g.resto_id = e.resto_id
 and g.payment_method = 'petty_cash'
where coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'expense'
      and j.reference_id = e.id::text
      and j.entry_type = 'credit'
  );

-- ---------------------------------------------------------------------
-- 4. Petty Cash top-ups → debit GL Petty Cash
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  p.resto_id,
  (p.created_at at time zone 'Asia/Jakarta')::date,
  (p.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'petty_cash', p.id::text, p.amount, 'debit',
  case
    when p.source = 'income_withdrawal' then 'Withdraw dari Penghasilan ke Petty Cash'
    else 'Top Up Petty Cash (Manual)'
  end
from petty_cash_entries p
join gl_accounts g
  on g.resto_id = p.resto_id
 and g.payment_method = 'petty_cash'
where coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'petty_cash'
      and j.reference_id = p.id::text
      and j.entry_type = 'debit'
  );

-- ---------------------------------------------------------------------
-- 5. Petty Cash withdrawals → credit GL Penghasilan
--    (manual top-ups are outside capital, so they have no counter-account)
-- ---------------------------------------------------------------------

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  p.resto_id,
  (p.created_at at time zone 'Asia/Jakarta')::date,
  (p.created_at at time zone 'Asia/Jakarta')::time,
  g.gl_code, g.gl_name,
  'petty_cash', p.id::text, p.amount, 'credit', 'Withdraw ke Petty Cash'
from petty_cash_entries p
join gl_accounts g
  on g.resto_id = p.resto_id
 and g.payment_method = 'income_aggregate'
where p.source = 'income_withdrawal'
  and coalesce(g.gl_code, '') <> ''
  and not exists (
    select 1 from gl_journal_entries j
    where j.reference_type = 'petty_cash'
      and j.reference_id = p.id::text
      and j.entry_type = 'credit'
  );

-- ---------------------------------------------------------------------
-- Ringkasan hasil backfill
-- ---------------------------------------------------------------------

select
  reference_type as "Jenis",
  entry_type as "Debit/Kredit",
  count(*) as "Jumlah Baris",
  sum(amount) as "Total"
from gl_journal_entries
where is_reversal = false
group by reference_type, entry_type
order by reference_type, entry_type;


-- ═══════════════════════════════════════════════════════════
-- 31. restaurant_logo.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — logo resto (run AFTER schema.sql).
--
-- Optional store logo, base64-encoded in the row itself — the same
-- approach product photos, customer photos and expense receipts already
-- use, so there's no storage bucket to provision.
--
-- Deliberately one shared column rather than per-role copies: whoever
-- uploads it (Super Admin when creating/editing the resto, or the Admin
-- from Info Resto) writes the same field, and either can clear it.
alter table restaurants add column if not exists logo_base64 text;


-- ═══════════════════════════════════════════════════════════
-- 32. restaurant_phone.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — nomor HP resto (run AFTER schema.sql).
--
-- Printed on the receipt under the address, so a customer has a way to
-- reach the shop about their order. Optional: a resto that hasn't set one
-- just prints without that line.
alter table restaurants add column if not exists phone text;


-- ═══════════════════════════════════════════════════════════
-- 33. table_number_text.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — nomor meja jadi teks (run AFTER customer_browse_resto.sql).
--
-- Table "numbers" aren't numbers in practice: restaurants label tables
-- A01, B07, VIP-2 and so on. Storing them as integer silently made those
-- impossible to enter.
--
-- Converting integer → text preserves every existing value ("7" stays
-- "7"), and QR stickers already printed keep working — the scanner's
-- parser no longer insists on digits, so an old `TABLE:7` payload reads
-- as the string "7" and matches the migrated row.
alter table orders alter column table_number type text using table_number::text;
alter table sessions alter column table_number type text using table_number::text;


-- ═══════════════════════════════════════════════════════════
-- 34. tax_and_service.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — PPN & biaya service (run AFTER restaurant_phone.sql and
-- orders_gl_code.sql).
--
-- Products store their ORIGINAL (pre-tax) price. The bill is built up
-- from it in the order Indonesian restaurants actually use — service
-- charge on the base, then PPN on base + service, because service
-- charge is itself subject to PPN:
--
--     service = base × service%
--     ppn     = (base + service) × ppn%
--     total   = base + service + ppn
--
-- The menu price shown to the customer carries PPN only. Service is a
-- per-bill Dine In charge and is added at checkout, so the same dish
-- never shows two different prices depending on how it's ordered.
--
-- Rates live on the restaurant (a tax rate is set by the state and by
-- house policy, not per dish), with per-product opt-outs for the items
-- that genuinely differ.

-- Rates, as percentages: 11 means 11%.
alter table restaurants add column if not exists ppn_percent numeric(5,2) not null default 0;
alter table restaurants add column if not exists service_percent numeric(5,2) not null default 0;

-- Per-product opt-outs. Default false: everything is taxed unless a
-- product is deliberately excluded.
alter table products add column if not exists ppn_exempt boolean not null default false;
alter table products add column if not exists service_exempt boolean not null default false;

-- The split, stored on the order so a receipt reprinted months later
-- shows the same figures even if the resto has changed its rates since.
-- base + service + ppn always equals total exactly (see the Dart
-- calculator rounds per line and sums, so the three always tie out).
alter table orders add column if not exists base_amount integer;
alter table orders add column if not exists service_amount integer;
alter table orders add column if not exists ppn_amount integer;

-- PPN and service collected are liabilities owed onward, not revenue, so
-- they get their own GL accounts rather than being folded into the
-- income mapping.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- Journalling a paid order now credits up to three accounts instead of
-- one: the payment method's income GL gets the base, and PPN/service go
-- to theirs. Falls back to crediting the whole total to income when the
-- order predates this split (base_amount null) or the rates were zero.
create or replace function log_order_paid_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_ppn_gl record;
  v_service_gl record;
  v_now timestamptz := now();
  v_date date;
  v_time time;
  v_method text;
  v_ref text;
  v_base integer;
begin
  if new.payment_status <> 'paid' then
    return new;
  end if;

  v_date := (v_now at time zone 'Asia/Jakarta')::date;
  v_time := (v_now at time zone 'Asia/Jakarta')::time;
  v_ref := upper(substr(new.id::text, 1, 8));
  v_base := coalesce(new.base_amount, new.total);

  v_method := _normalize_payment_method(new.source, new.payment_method);
  select * into v_gl from _gl_account_for(new.resto_id, v_method);
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time, v_gl.gl_code, v_gl.gl_name,
      'order', new.id::text, v_base, 'credit',
      'Pemasukan pesanan #' || v_ref
    );
  end if;

  if coalesce(new.service_amount, 0) > 0 then
    select * into v_service_gl from _gl_account_for(new.resto_id, 'service');
    if v_service_gl.gl_code is not null and v_service_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time, v_service_gl.gl_code, v_service_gl.gl_name,
        'order', new.id::text, new.service_amount, 'credit',
        'Biaya service pesanan #' || v_ref
      );
    end if;
  end if;

  if coalesce(new.ppn_amount, 0) > 0 then
    select * into v_ppn_gl from _gl_account_for(new.resto_id, 'ppn');
    if v_ppn_gl.gl_code is not null and v_ppn_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time, v_ppn_gl.gl_code, v_ppn_gl.gl_name,
        'order', new.id::text, new.ppn_amount, 'credit',
        'PPN pesanan #' || v_ref
      );
    end if;
  end if;

  return new;
end;
$$;


-- ═══════════════════════════════════════════════════════════
-- 35. tax_rates_finance.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — tarif PPN & biaya service dipindah ke Finance
-- (run AFTER tax_and_service.sql).
--
-- The rates sit on `restaurants`, but setting them is a Finance job, not
-- an Admin one: they belong with the GL accounts the tax is booked to,
-- which is why the app now edits them from Mapping GL Account.
--
-- Rather than widening the restaurants UPDATE policy to Finance — which
-- would also let them rename the resto, change its address or flip it
-- inactive — this exposes exactly the two columns through a definer
-- function that checks the role itself.

-- restaurants.id is text, not uuid, and so is is_resto_employee's first
-- argument. An earlier uuid-typed version of this function failed at
-- call time because Postgres won't implicitly cast uuid to text.
drop function if exists set_tax_rates(uuid, numeric, numeric);

create or replace function set_tax_rates(
  p_resto_id text,
  p_ppn_percent numeric,
  p_service_percent numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['finance', 'admin'])) then
    raise exception 'Tidak punya akses mengubah tarif PPN/service';
  end if;

  -- A negative rate would silently produce negative tax on every bill;
  -- the upper bound is a typo guard (entering 110 instead of 11).
  if p_ppn_percent < 0 or p_ppn_percent > 100
     or p_service_percent < 0 or p_service_percent > 100 then
    raise exception 'Tarif harus antara 0 dan 100';
  end if;

  update restaurants
     set ppn_percent = p_ppn_percent,
         service_percent = p_service_percent
   where id = p_resto_id;
end;
$$;

revoke all on function set_tax_rates(text, numeric, numeric) from public;
grant execute on function set_tax_rates(text, numeric, numeric) to authenticated;


-- ═══════════════════════════════════════════════════════════
-- 36. cash_deposit.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — Setoran Saldo Cash + pemisahan Cash / Non Cash
-- (run AFTER journal_integrity.sql dan tax_and_service.sql).
--
-- Sampai sekarang semua pemasukan dianggap satu kantong. Padahal uang
-- tunai berbeda sifatnya: ia benar-benar ada di laci kasir dan harus
-- disetorkan, sedangkan QRIS dan transfer sudah langsung mendarat di
-- rekening. Menyatukan keduanya membuat "Saldo Penghasilan" tidak bisa
-- dipakai untuk menjawab satu pertanyaan yang paling sering ditanyakan
-- pemilik resto: berapa uang tunai yang seharusnya ada di laci sekarang?
--
-- Karena itu:
--   Saldo Cash     = pemasukan tunai − setoran − top up petty cash dari tunai
--   Saldo Non Cash = pemasukan QRIS/transfer − top up petty cash dari situ
--
-- Setoran memindahkan uang, bukan menghabiskannya: GL Cash berkurang,
-- GL Total Saldo bertambah. Saldo Total resto tidak berubah karenanya.

-- ── 1. Tabel setoran ─────────────────────────────────────────────────
create table if not exists cash_deposits (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  amount integer not null check (amount > 0),
  -- Bukti transfer/setor, disimpan langsung sebagai base64 di barisnya —
  -- pendekatan yang sama dengan foto produk dan nota pengeluaran, jadi
  -- tidak ada storage bucket baru yang perlu disiapkan dan dijaga
  -- izinnya.
  proof_base64 text,
  note text,
  -- Email penyetor. Kasir yang menyetor uang laci adalah orang yang
  -- bertanggung jawab atas selisihnya, jadi ini bukan sekadar audit.
  created_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_cash_deposits_resto on cash_deposits(resto_id);

alter table cash_deposits enable row level security;

-- Kasir memegang uang lacinya, jadi merekalah yang menyetor. Finance dan
-- admin ikut melihat, tapi pembatalan setoran hanya untuk mereka —
-- menghapus setoran menulis ulang jurnal.
drop policy if exists "cash_deposits: staff read" on cash_deposits;
create policy "cash_deposits: staff read" on cash_deposits
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "cash_deposits: staff insert" on cash_deposits;
create policy "cash_deposits: staff insert" on cash_deposits
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "cash_deposits: finance delete" on cash_deposits;
create policy "cash_deposits: finance delete" on cash_deposits
  for delete using (is_resto_employee(resto_id, array['admin', 'finance']));

-- ── 2. Petty cash boleh bersumber dari saldo tunai ───────────────────
-- Nilai lama 'income_withdrawal' dipertahankan apa adanya dan kini
-- dibaca sebagai "dari Non Cash"; menulis ulang baris lama akan
-- memalsukan riwayat yang saat itu memang belum membedakan keduanya.
alter table petty_cash_entries drop constraint if exists petty_cash_entries_source_check;
alter table petty_cash_entries add constraint petty_cash_entries_source_check
  check (source in ('manual', 'income_withdrawal', 'cash_withdrawal'));

-- ── 3. Jurnal setoran: GL Cash keluar, GL Total Saldo masuk ──────────
alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

create or replace function log_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_gl record;
  v_total_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  -- Uang tunai meninggalkan laci → kredit GL Cash.
  select * into v_cash_gl from _gl_account_for(new.resto_id, 'cash');
  if v_cash_gl.gl_code is not null and v_cash_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_cash_gl.gl_code, v_cash_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', 'Setor tunai #' || v_ref
    );
  end if;

  -- Dan mendarat di rekening → debit GL Total Saldo.
  select * into v_total_gl from _gl_account_for(new.resto_id, 'total_balance');
  if v_total_gl.gl_code is not null and v_total_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_total_gl.gl_code, v_total_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Terima setoran tunai #' || v_ref
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_cash_deposit_journal on cash_deposits;
create trigger trg_log_cash_deposit_journal
  after insert on cash_deposits
  for each row execute function log_cash_deposit_journal();

-- Pembatalan setoran dibalik, bukan dihapus — sama seperti pengeluaran
-- dan petty cash, supaya riwayat jurnalnya utuh.
create or replace function reverse_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform _reverse_journal_for('cash_deposit', old.id::text, 'Pembatalan setoran tunai');
  return old;
end;
$$;

drop trigger if exists trg_reverse_cash_deposit_journal on cash_deposits;
create trigger trg_reverse_cash_deposit_journal
  before delete on cash_deposits
  for each row execute function reverse_cash_deposit_journal();

-- ── 4. Jurnal petty cash: sumber tunai memotong GL Cash ──────────────
-- Sebelumnya hanya ada satu lawan akun ('income_aggregate'). Sekarang
-- sumbernya menentukan akun mana yang berkurang, supaya saldo tunai di
-- laci ikut turun saat dipakai mengisi petty cash.
create or replace function log_petty_cash_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petty_gl record;
  v_source_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_label text;
begin
  v_label := case new.source
    when 'cash_withdrawal' then 'Saldo Cash'
    when 'income_withdrawal' then 'Saldo Non Cash'
    else null
  end;

  -- Petty cash adalah aset: bertambah → debit.
  select * into v_petty_gl from _gl_account_for(new.resto_id, 'petty_cash');
  if v_petty_gl.gl_code is not null and v_petty_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_petty_gl.gl_code, v_petty_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'debit',
      coalesce('Top Up Petty Cash dari ' || v_label, 'Top Up Petty Cash (Manual)')
    );
  end if;

  -- Top up manual adalah modal dari luar, jadi tidak punya lawan akun.
  if v_label is not null then
    select * into v_source_gl from _gl_account_for(
      new.resto_id,
      case when new.source = 'cash_withdrawal' then 'cash' else 'income_aggregate' end
    );
    if v_source_gl.gl_code is not null and v_source_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_source_gl.gl_code, v_source_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit', 'Dipindah ke Petty Cash'
      );
    end if;
  end if;

  return new;
end;
$$;

-- Tidak ada perubahan hak baca `orders`: policy "orders: public read"
-- yang sudah ada sudah cukup untuk layar Setor Saldo menghitung berapa
-- tunai yang seharusnya ada di laci.


-- ═══════════════════════════════════════════════════════════
-- 37. kitchen_checklist.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — checklist dapur per menu (run AFTER schema.sql).
--
-- Sebelumnya menyelesaikan pesanan cuma satu tombol: dari "dimasak"
-- langsung "selesai". Pada pesanan berisi lima menu, satu yang terlewat
-- tetap membuat pesanannya tercatat selesai, dan baru ketahuan waktu
-- customer bertanya.
--
-- Sekarang tiap menu dicentang satu per satu. Menyimpan nomor barisnya,
-- bukan productId: satu produk bisa muncul beberapa kali sebagai baris
-- terpisah (nasi goreng pedas dan tidak pedas), jadi productId tidak
-- membedakan keduanya. Urutan `items` tidak pernah berubah setelah
-- pesanan dibuat, sehingga nomor barisnya aman dijadikan penanda.
alter table orders add column if not exists items_done jsonb not null default '[]'::jsonb;

-- Chef sudah punya hak update pada `orders` lewat policy
-- "orders: employees update" (lihat rls_hardening.sql), jadi tidak ada
-- policy baru yang perlu ditambahkan di sini.


-- ═══════════════════════════════════════════════════════════
-- 38. owner_multi_resto.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — peran Owner + satu orang mengelola banyak resto
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


-- ═══════════════════════════════════════════════════════════
-- 39. rilis_setor_petty_inbox.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — setoran & top up petty cash berjenjang, GL Suspense, dan
-- kotak masuk pengumuman.
--
-- SATU file untuk seluruh rilis ini; menggantikan deposit_approval.sql
-- dan inbox_and_petty_approval.sql yang sebelumnya terpisah. Aman
-- dijalankan berulang kali.
--
-- Alurnya:
--   Kasir/Admin mencatat  → status 'pending', uang ditampung di GL
--                           Suspense (setoran dan petty cash punya
--                           akun suspense masing-masing).
--   Finance mengonfirmasi → dipindah dari suspense ke akun tujuannya.
--   Finance menolak       → dikembalikan ke akun asalnya.
--
-- Mengonfirmasi hanya milik Finance (dan Owner, yang lolos setiap
-- pemeriksaan peran). Admin disamakan dengan kasir: keduanya mengajukan,
-- bukan memutuskan — persetujuan atas permintaan sendiri tidak berarti
-- apa-apa.

-- ARAH JURNAL. Aplikasi ini memakai satu kesepakatan di seluruh
-- layarnya: **kredit = uang masuk ke akun itu, debit = uang keluar**.
-- Penjualan mengkredit akun pemasukan, dan panah di layar Jurnal GL
-- mengikuti aturan yang sama.
--
-- Kesepakatan akuntansi aset yang biasa (aset bertambah = debit) adalah
-- kebalikannya, dan sempat terpakai di sini — akibatnya setoran tunai
-- menambah sisi yang sama dengan penjualan alih-alih menguranginya, dan
-- di layar terbaca seolah GL Suspense yang mengeluarkan uang.

begin;


-- ── 1. Status persetujuan ────────────────────────────────────────────
alter table cash_deposits add column if not exists status text not null default 'pending';
alter table cash_deposits add column if not exists reviewed_by text;
alter table cash_deposits add column if not exists reviewed_at timestamptz;
alter table cash_deposits add column if not exists review_note text;

alter table cash_deposits drop constraint if exists cash_deposits_status_check;
alter table cash_deposits add constraint cash_deposits_status_check
  check (status in ('pending', 'approved', 'rejected'));

-- Setoran yang sudah terlanjur tercatat sebelum alur ini ada memang sudah
-- masuk GL Total Saldo, jadi statusnya disamakan dengan 'approved' —
-- menandainya 'pending' akan meminta Finance menyetujui sesuatu yang
-- uangnya sudah lama diakui.
update cash_deposits set status = 'approved' where status = 'pending' and created_at < now() - interval '1 second';

create index if not exists idx_cash_deposits_status on cash_deposits(resto_id, status);

-- ── 2. GL Suspense ───────────────────────────────────────────────────
-- Batasan payment_method dipasang sekali saja, di bagian GL Suspense
-- Petty Cash di bawah — daftarnya sudah memuat 'suspense' sekaligus
-- 'suspense_petty'. Memasang daftar yang lebih pendek lebih dulu membuat
-- file ini menolak dirinya sendiri saat dijalankan ulang, karena baris
-- 'suspense_petty' yang dibuatnya sudah ada.

-- ── 3. Jurnal saat setoran diajukan ──────────────────────────────────
-- Uang meninggalkan laci, tapi berhenti dulu di Suspense.
create or replace function log_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_gl record;
  v_suspense_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  select * into v_cash_gl from _gl_account_for(new.resto_id, 'cash');
  if v_cash_gl.gl_code is not null and v_cash_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_cash_gl.gl_code, v_cash_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Setor tunai #' || v_ref || ' (menunggu approval)'
    );
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', 'Titipan setoran #' || v_ref
    );
  end if;

  return new;
end;
$$;

-- ── 4. Jurnal saat disetujui / ditolak ───────────────────────────────
-- Dipicu oleh perubahan status, dan hanya untuk baris yang berubah, jadi
-- setoran lain yang masih menunggu tidak ikut terbawa.
create or replace function log_cash_deposit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suspense_gl record;
  v_target_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Titipan setoran #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    v_target := 'total_balance';
    v_note := 'Setoran #' || v_ref || ' disetujui';
  else
    -- Ditolak: uangnya kembali menjadi tanggung jawab laci kasir.
    v_target := 'cash';
    v_note := 'Setoran #' || v_ref || ' ditolak, kembali ke kas';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', v_note
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_cash_deposit_review on cash_deposits;
create trigger trg_log_cash_deposit_review
  after update of status on cash_deposits
  for each row execute function log_cash_deposit_review();

-- ── 5. Hanya Finance/Admin/Owner yang boleh menyetujui ───────────────
-- Kasir dan Admin tetap boleh menambah setoran, tapi tidak boleh
-- mengubah statusnya sendiri. Owner ikut lolos lewat klausa 'owner' di
-- dalam is_resto_employee.
drop policy if exists "cash_deposits: finance review" on cash_deposits;
create policy "cash_deposits: finance review" on cash_deposits
  for update
  using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));


-- ─────────────────────────────────────────────────────────────────────
-- 1. Rekening tujuan pada setoran tunai
-- ─────────────────────────────────────────────────────────────────────
-- Tanpa ini, "sudah disetor" tidak menyebut ke mana. Saat Finance
-- memeriksa mutasi bank, tidak ada yang bisa dicocokkan selain nominal.
alter table cash_deposits add column if not exists bank_name text;
alter table cash_deposits add column if not exists account_number text;
alter table cash_deposits add column if not exists account_holder text;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Approval top up petty cash
-- ─────────────────────────────────────────────────────────────────────
-- Kasir kini boleh mengajukan top up, tapi uangnya belum diakui masuk
-- petty cash sampai Finance menyetujui. Selama menunggu, nilainya
-- ditampung di GL Suspense Petty Cash — sengaja terpisah dari suspense
-- setoran bank, supaya Finance bisa melihat berapa yang tertahan pada
-- masing-masing alur tanpa harus memilahnya satu per satu.
alter table petty_cash_entries add column if not exists status text not null default 'approved';
alter table petty_cash_entries add column if not exists requested_by text;
alter table petty_cash_entries add column if not exists reviewed_by text;
alter table petty_cash_entries add column if not exists reviewed_at timestamptz;
alter table petty_cash_entries add column if not exists review_note text;

alter table petty_cash_entries drop constraint if exists petty_cash_entries_status_check;
alter table petty_cash_entries add constraint petty_cash_entries_status_check
  check (status in ('pending', 'approved', 'rejected'));

-- Baris lama dibuat oleh Finance sendiri, jadi memang sudah setara
-- disetujui — default kolomnya 'approved' supaya riwayat tidak
-- tiba-tiba minta persetujuan ulang.
create index if not exists idx_petty_cash_status on petty_cash_entries(resto_id, status);

-- Kasir boleh mengajukan dan melihat, tapi tidak boleh menyetujui —
-- persetujuan atas permintaannya sendiri tidak berarti apa-apa.
drop policy if exists "petty_cash_entries: kasir request" on petty_cash_entries;
create policy "petty_cash_entries: kasir request" on petty_cash_entries
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "petty_cash_entries: staff read" on petty_cash_entries;
create policy "petty_cash_entries: staff read" on petty_cash_entries
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

-- ─────────────────────────────────────────────────────────────────────
-- 3. GL Suspense Petty Cash
-- ─────────────────────────────────────────────────────────────────────
-- Daftarnya sengaja sama persis di semua berkas yang menyentuh batasan
-- ini, bukan hanya sepanjang yang dibutuhkan berkas ini sendiri.
--
-- Sebelumnya tiap berkas menuliskan daftar sepanjang zamannya, dan
-- itu berjalan baik tepat satu kali — saat dijalankan berurutan pada
-- database kosong. Menjalankan ulang berkas yang lebih tua sesudah
-- yang lebih baru berarti menyempitkan daftarnya lagi, dan barisan
-- akun yang terlanjur dibuat berkas yang lebih baru langsung
-- melanggarnya:
--
--   check constraint "gl_accounts_payment_method_check" is violated
--   by some row
--
-- Padahal tidak ada satu pun data yang salah. Yang salah adalah
-- batasannya yang mundur. Satu daftar untuk semua menutup itu.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- ─────────────────────────────────────────────────────────────────────
-- 4. Jurnal petty cash mengikuti statusnya
-- ─────────────────────────────────────────────────────────────────────
-- Saat diajukan: sumbernya berkurang, nilainya mengendap di Suspense
-- Petty Cash. Saat disetujui: berpindah dari suspense ke petty cash.
-- Saat ditolak: dikembalikan ke sumbernya semula.
create or replace function log_petty_cash_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petty_gl record;
  v_source_gl record;
  v_suspense_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_label text;
begin
  v_label := case new.source
    when 'cash_withdrawal' then 'Saldo Cash'
    when 'income_withdrawal' then 'Saldo Non Cash'
    else null
  end;

  -- Sumbernya berkurang begitu diajukan, apa pun statusnya: uangnya
  -- memang sudah diambil dari sana. Top up manual adalah modal dari
  -- luar, jadi tidak punya lawan akun.
  if v_label is not null then
    select * into v_source_gl from _gl_account_for(
      new.resto_id,
      case when new.source = 'cash_withdrawal' then 'cash' else 'income_aggregate' end
    );
    if v_source_gl.gl_code is not null and v_source_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_source_gl.gl_code, v_source_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'debit', 'Dipindah ke Petty Cash #' || v_ref
      );
    end if;
  end if;

  if new.status = 'pending' then
    -- Menunggu persetujuan: berhenti dulu di suspense.
    select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense_petty');
    if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit', 'Titipan top up petty cash #' || v_ref
      );
    end if;
  else
    -- Dibuat langsung oleh Finance: tidak perlu singgah di suspense.
    select * into v_petty_gl from _gl_account_for(new.resto_id, 'petty_cash');
    if v_petty_gl.gl_code is not null and v_petty_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_petty_gl.gl_code, v_petty_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit',
        coalesce('Top Up Petty Cash dari ' || v_label, 'Top Up Petty Cash (Manual)')
      );
    end if;
  end if;

  return new;
end;
$$;

create or replace function log_petty_cash_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suspense_gl record;
  v_target_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense_petty');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'debit', 'Titipan top up #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    v_target := 'petty_cash';
    v_note := 'Top up petty cash #' || v_ref || ' disetujui';
  else
    -- Ditolak: uangnya kembali ke sumber asalnya.
    v_target := case when new.source = 'cash_withdrawal' then 'cash' else 'income_aggregate' end;
    v_note := 'Top up petty cash #' || v_ref || ' ditolak';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'credit', v_note
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_petty_cash_review on petty_cash_entries;
create trigger trg_log_petty_cash_review
  after update of status on petty_cash_entries
  for each row execute function log_petty_cash_review();

drop policy if exists "petty_cash_entries: finance review" on petty_cash_entries;
create policy "petty_cash_entries: finance review" on petty_cash_entries
  for update
  using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));

-- ─────────────────────────────────────────────────────────────────────
-- 5. Inbox pengumuman
-- ─────────────────────────────────────────────────────────────────────
-- Pengumumannya disimpan sekali, bukan disalin ke tiap penerima. Menyalin
-- berarti orang yang mendaftar besok tidak akan pernah melihat
-- pengumuman hari ini, dan setiap blast menambah ribuan baris kembar.
-- Yang per orang hanyalah keadaannya: sudah dibaca, atau sudah dihapus.
create table if not exists app_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  -- Versi aplikasi yang diumumkan. Dipakai layar tamu untuk tahu apakah
  -- aplikasinya sudah usang, tanpa perlu punya akun.
  version text,
  download_url text,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists idx_announcements_created on app_announcements(created_at desc);

alter table app_announcements enable row level security;

-- Boleh dibaca siapa saja, termasuk tamu: pemberitahuan versi baru justru
-- paling dibutuhkan orang yang belum punya akun.
drop policy if exists "announcements: public read" on app_announcements;
create policy "announcements: public read" on app_announcements
  for select using (true);

drop policy if exists "announcements: super_admin write" on app_announcements;
create policy "announcements: super_admin write" on app_announcements
  for all using (is_super_admin()) with check (is_super_admin());

create table if not exists inbox_states (
  email text not null,
  announcement_id uuid not null references app_announcements(id) on delete cascade,
  read_at timestamptz,
  deleted_at timestamptz,
  primary key (email, announcement_id)
);

alter table inbox_states enable row level security;

-- Setiap orang hanya menyentuh barisnya sendiri. Inbox milik orang lain
-- bukan urusan siapa pun, termasuk admin.
drop policy if exists "inbox_states: own rows" on inbox_states;
create policy "inbox_states: own rows" on inbox_states
  for all
  using (email = auth.jwt()->>'email')
  with check (email = auth.jwt()->>'email');

-- ─────────────────────────────────────────────────────────────────────
-- 6. Titik lokasi resto
-- ─────────────────────────────────────────────────────────────────────
-- Alamat berupa teks cukup untuk dicetak di struk, tapi tidak cukup
-- untuk mengantar orang ke sana. Koordinatnya disimpan terpisah supaya
-- alamat tetap bisa disunting sedetail yang dibutuhkan ("ruko blok C
-- no. 4") tanpa merusak titik petanya.
alter table restaurants add column if not exists latitude double precision;
alter table restaurants add column if not exists longitude double precision;

-- ─────────────────────────────────────────────────────────────────────
-- 7. Membetulkan baris jurnal yang terlanjur terbalik
-- ─────────────────────────────────────────────────────────────────────
-- Setoran dan top up petty cash yang sudah tercatat sebelum perbaikan di
-- atas memakai arah yang salah. Barisnya tidak dihapus — riwayat jurnal
-- tidak boleh hilang — hanya arahnya yang dibalik.
--
-- Dijaga supaya hanya berjalan sekali. Menjalankannya dua kali akan
-- mengembalikan keadaan yang justru sedang diperbaiki, dan file ini
-- memang dirancang untuk boleh dijalankan berulang kali.
create table if not exists applied_migrations (
  name text primary key,
  applied_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from applied_migrations where name = 'flip_transfer_journal_direction') then
    update gl_journal_entries
       set entry_type = case entry_type when 'debit' then 'credit' else 'debit' end
     where reference_type in ('cash_deposit', 'petty_cash');

    insert into applied_migrations (name) values ('flip_transfer_journal_direction');
  end if;
end $$;


commit;


-- ═══════════════════════════════════════════════════════════
-- 40. employee_surrogate_key.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — email karyawan jadi bisa diubah.
--
-- Jalankan SETELAH owner_multi_resto.sql. Aman dijalankan berulang kali.
--
-- Selama ini baris karyawan dikenali dari emailnya sendiri, jadi
-- mengubah email berarti mengubah identitas barisnya — yang bukan
-- "mengubah", melainkan membuat orang baru dan meninggalkan yang lama.
-- Karena itu kolomnya dikunci di layar admin.
--
-- Sekarang barisnya punya id sendiri yang tidak berarti apa-apa selain
-- "baris ini". Email kembali menjadi data biasa: boleh salah ketik saat
-- didaftarkan, boleh diperbaiki nanti, tanpa kehilangan riwayat apa pun
-- yang menempel pada baris itu.

begin;

-- Kolom baru terisi otomatis untuk baris yang sudah ada, karena
-- defaultnya dihitung per baris saat kolomnya ditambahkan.
alter table employees add column if not exists id uuid not null default gen_random_uuid();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'employees'::regclass and contype = 'p'
  ) then
    alter table employees add constraint employees_pkey primary key (id);
  end if;
end $$;

-- Pasangan (email, resto_id) tetap unik: satu orang tetap tidak boleh
-- terdaftar dua kali di resto yang sama. Yang berubah hanya soal apa
-- yang menjadi identitas barisnya.
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

commit;


-- ═══════════════════════════════════════════════════════════
-- 41. promo_banner.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — banner promo per resto.
--
-- Jalankan kapan saja setelah schema.sql. Aman dijalankan berulang kali.
--
-- Bannernya milik resto, bukan milik MerchantPOS: tiap resto memasang
-- promonya sendiri, dan customer hanya melihat banner resto yang sedang
-- dia buka.

begin;

create table if not exists promo_banners (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),

  -- Gambar disimpan langsung sebagai base64 di barisnya, sama seperti
  -- logo resto dan foto produk. Tidak ada storage bucket baru yang perlu
  -- disiapkan dan dijaga izinnya — dan banner jumlahnya sedikit, tidak
  -- seperti foto struk yang tumbuh tiap hari.
  image_base64 text not null,

  title text,
  description text,

  -- Nonaktif berarti disimpan tapi tidak ditampilkan. Promo musiman
  -- biasanya kembali dipakai tahun depan, jadi menghapusnya berarti
  -- mengunggah ulang gambar yang sama.
  active boolean not null default true,

  -- Urutan tampil. Promo utama harus bisa ditaruh di depan tanpa
  -- menghapus dan mengunggah ulang yang lain.
  sort_order integer not null default 0,

  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists idx_promo_banners_resto
  on promo_banners(resto_id, active, sort_order);

alter table promo_banners enable row level security;

-- Dibaca siapa saja, termasuk tamu: banner promo justru ditujukan untuk
-- orang yang belum punya akun.
drop policy if exists "promo_banners: public read" on promo_banners;
create policy "promo_banners: public read" on promo_banners
  for select using (true);

-- Yang mengelola hanya admin restonya sendiri (dan owner, yang lolos
-- setiap pemeriksaan peran lewat is_resto_employee), atau super_admin.
drop policy if exists "promo_banners: admin manage" on promo_banners;
create policy "promo_banners: admin manage" on promo_banners
  for all
  using (is_super_admin() or is_resto_employee(resto_id, array['admin']))
  with check (is_super_admin() or is_resto_employee(resto_id, array['admin']));

commit;


-- ═══════════════════════════════════════════════════════════
-- 42. customer_cash_payment.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pelanggan boleh memilih bayar tunai di kasir.
--
-- Jalankan SETELAH orders_gl_code.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang pesanan mandiri dari HP pelanggan selalu QRIS, dan itu
-- dianggap benar di banyak tempat sekaligus. Yang berubah di sini cuma
-- satu: kalau pesanannya sudah menyebut cara bayarnya sendiri, sebutan
-- itu yang dipakai — bukan diganti QRIS karena kebetulan datang dari
-- pelanggan.

begin;

-- Uang yang diserahkan pelanggan di meja kasir.
--
-- Kembaliannya tidak ikut disimpan: itu selalu bisa dihitung ulang dari
-- uang yang diterima dikurangi totalnya, dan menyimpan dua angka yang
-- saling terikat berarti membuka peluang keduanya tidak lagi cocok.
alter table orders add column if not exists cash_received bigint;

-- Sebelumnya: pesanan mana pun dari pelanggan langsung dipetakan ke
-- 'qris' tanpa melihat apa pun. Akibatnya pesanan tunai akan tercatat
-- masuk ke GL QRIS — uangnya benar jumlahnya, tapi salah kantong, dan
-- Finance baru sadar saat mencocokkan mutasi QRIS yang tidak pernah ada.
--
-- Baris pelanggan lama tidak pernah mengisi payment_method, jadi
-- pemetaan lamanya tetap berlaku persis untuk mereka.
create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_payment_method in ('cash', 'qris', 'transfer') then p_payment_method
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    when p_payment_method = 'Tunai' then 'cash'
    when p_source = 'customer' then 'qris'
    else 'cash'
  end;
$$;

-- Setoran dan top up ikut disiarkan realtime.
--
-- Tanpa ini, kasir baru tahu pengajuannya disetujui kalau kebetulan
-- membuka layarnya lagi — padahal justru itu yang bikin orang tidak
-- membukanya: tidak ada yang memberi tahu ada yang perlu dilihat.
do $$
begin
  alter publication supabase_realtime add table cash_deposits;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table petty_cash_entries;
exception when duplicate_object then null;
end $$;

-- Pesanan tunai pelanggan diselesaikan kasir lewat UPDATE biasa —
-- kebijakan "orders: employees update" sudah mengizinkannya, dan RPC
-- mark_order_paid memang khusus untuk tamu yang tidak punya sesi login.
-- Tidak ada yang perlu ditambahkan di sini.

commit;


-- ═══════════════════════════════════════════════════════════
-- 43. push_notifications.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — notifikasi yang tetap sampai walau aplikasinya tertutup.
--
-- Jalankan SETELAH customer_cash_payment.sql. Aman dijalankan berulang
-- kali.
--
-- Notifikasi yang sudah ada dibangkitkan aplikasinya sendiri dari aliran
-- realtime, dan itu hanya hidup selama prosesnya hidup. Berkas ini
-- menyiapkan sisi servernya: daftar perangkat yang boleh diketuk, dan
-- pemicu yang memberi tahu Edge Function bahwa ada yang perlu
-- dikabarkan.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Daftar perangkat
-- ─────────────────────────────────────────────────────────────────────

-- Satu baris per perangkat, bukan per orang: satu orang bisa memegang HP
-- dan tablet sekaligus, dan satu HP bisa berpindah tangan antar shift.
-- Tokennya sendiri yang jadi kunci — itu satu-satunya hal yang benar-
-- benar mewakili "tempat notifikasi ini akan mendarat".
create table if not exists device_tokens (
  token text primary key,

  -- Siapa yang sedang memakainya. Semuanya boleh kosong: pelanggan tamu
  -- tidak punya email, dan perangkat yang belum memilih resto belum
  -- terikat ke mana pun.
  email text,
  resto_id text references restaurants (id) on delete cascade,
  role text,

  -- Pengenal pelanggan tamu. Tamu adalah sebagian besar pelanggan resto;
  -- tanpa kolom ini fitur ini hanya bekerja untuk yang paling jarang
  -- membutuhkannya.
  session_id text,

  platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_resto_role_idx
  on device_tokens (resto_id, role);
create index if not exists device_tokens_email_idx on device_tokens (email);
create index if not exists device_tokens_session_idx on device_tokens (session_id);

alter table device_tokens enable row level security;

-- Siapa pun boleh mendaftarkan tokennya sendiri, termasuk tamu yang
-- tidak punya sesi login sama sekali — sama seperti kebijakan `orders`,
-- yang memang harus menerima pesanan dari orang tanpa akun.
--
-- Yang dijaga bukan siapa yang boleh menulis, tapi siapa yang boleh
-- membaca: daftar token adalah daftar "ke mana notifikasi bisa
-- dikirim", dan itu tidak boleh bisa dibaca dari aplikasi sama sekali.
-- Edge Function membacanya dengan service role, yang melewati RLS.
drop policy if exists "device_tokens: public upsert" on device_tokens;
create policy "device_tokens: public upsert" on device_tokens
  for insert with check (true);

drop policy if exists "device_tokens: update own" on device_tokens;
create policy "device_tokens: update own" on device_tokens
  for update using (true) with check (true);

drop policy if exists "device_tokens: delete own" on device_tokens;
create policy "device_tokens: delete own" on device_tokens
  for delete using (true);

-- Sengaja tidak ada kebijakan select untuk peran mana pun.

-- ─────────────────────────────────────────────────────────────────────
-- 2. Antrean kabar
-- ─────────────────────────────────────────────────────────────────────

-- Kejadian ditulis ke tabel dulu, baru dikirim.
--
-- Memanggil FCM langsung dari trigger berarti transaksi database
-- menunggu jaringan pihak lain: FCM lambat sedetik, dan kasir menunggu
-- sedetik itu sebelum pesanannya tersimpan. Lebih buruk lagi, FCM
-- gagal berarti seluruh transaksinya batal — pesanan yang sah hilang
-- gara-gara notifikasinya tidak terkirim.
--
-- Dengan antrean, kejadiannya tercatat dulu dan dikirim menyusul. Yang
-- gagal terkirim tetap tercatat di sini berikut galatnya, jadi
-- "notifikasinya tidak sampai" berhenti jadi tebakan.
create table if not exists push_outbox (
  id uuid primary key default gen_random_uuid(),
  resto_id text,
  event text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  error text,
  attempts int not null default 0
);

create index if not exists push_outbox_pending_idx
  on push_outbox (created_at) where sent_at is null;

alter table push_outbox enable row level security;
-- Tidak ada kebijakan apa pun: hanya trigger dan service role yang
-- menyentuhnya.

-- ─────────────────────────────────────────────────────────────────────
-- 3. Pemicu — pesanan
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_push_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_where text;
begin
  v_where := case
    when new.table_number is not null and new.table_number <> ''
      then 'Meja ' || new.table_number
    when coalesce(new.customer_name, '') <> ''
      then 'Take Away · ' || new.customer_name
    else 'Take Away'
  end;

  -- Pesanan baru → dapur.
  if tg_op = 'INSERT' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'order_new',
      jsonb_build_object(
        'audience', 'role', 'roles', array['chef'],
        'title', 'Pesanan baru masuk',
        'body', v_where || ' · #' || v_ref
      )
    );
    return new;
  end if;

  -- Dapur bergerak → pelanggannya, dan kasir yang menginput.
  if new.kitchen_status is distinct from old.kitchen_status then
    if new.kitchen_status = 'onProgress' then
      insert into push_outbox (resto_id, event, payload) values (
        new.resto_id, 'order_cooking',
        jsonb_build_object(
          'audience', 'order_owner',
          'email', new.customer_label,
          'session_id', new.session_id,
          'title', 'Pesanan kamu lagi dimasak 👨‍🍳',
          'body', 'Dapur sudah mulai. Tunggu sebentar ya — #' || v_ref
        )
      );
    elsif new.kitchen_status = 'done' then
      insert into push_outbox (resto_id, event, payload) values (
        new.resto_id, 'order_ready',
        jsonb_build_object(
          'audience', 'order_owner',
          'email', new.customer_label,
          'session_id', new.session_id,
          'title', 'Pesanan kamu siap! 🎉',
          'body', 'Selamat menikmati — #' || v_ref
        )
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_queue_push_order_insert on orders;
create trigger trg_queue_push_order_insert
  after insert on orders
  for each row execute function queue_push_order();

drop trigger if exists trg_queue_push_order_update on orders;
create trigger trg_queue_push_order_update
  after update on orders
  for each row execute function queue_push_order();

-- Pesanan tunai dari HP pelanggan yang menunggu dibayar — kasir, admin,
-- dan owner perlu tahu ada orang berdiri di depan kasir.
create or replace function queue_push_pending_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source = 'customer'
     and new.payment_status = 'pending'
     and new.payment_method = 'cash' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'pending_payment',
      jsonb_build_object(
        'audience', 'role', 'roles', array['kasir', 'admin', 'owner'],
        'title', 'Pesanan menunggu dibayar',
        'body', 'Pelanggan memilih bayar tunai di kasir — #'
                || upper(substr(new.id::text, 1, 8))
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_pending_payment on orders;
create trigger trg_queue_push_pending_payment
  after insert on orders
  for each row execute function queue_push_pending_payment();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Pemicu — setoran & petty cash
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_push_deposit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount text := 'Rp ' || to_char(new.amount, 'FM999G999G999');
begin
  -- Pengajuan baru → yang memutuskan.
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'deposit_pending',
      jsonb_build_object(
        'audience', 'role', 'roles', array['finance', 'owner'],
        'title', 'Setoran tunai menunggu konfirmasi',
        'body', v_amount || ' dari ' || coalesce(new.created_by, 'kasir')
      )
    );
    return new;
  end if;

  -- Sudah diputus → yang mengajukan.
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'deposit_reviewed',
      jsonb_build_object(
        'audience', 'email', 'email', new.created_by,
        'title', case new.status
                   when 'approved' then 'Setoran tunai dikonfirmasi ✅'
                   else 'Setoran tunai ditolak' end,
        'body', case new.status
                  when 'approved' then v_amount || ' sudah masuk rekening merchant.'
                  else v_amount || ' dikembalikan ke Saldo Cash'
                       || coalesce(' — ' || nullif(trim(new.review_note), ''), '.')
                end
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_deposit_insert on cash_deposits;
create trigger trg_queue_push_deposit_insert
  after insert on cash_deposits
  for each row execute function queue_push_deposit();

drop trigger if exists trg_queue_push_deposit_update on cash_deposits;
create trigger trg_queue_push_deposit_update
  after update of status on cash_deposits
  for each row execute function queue_push_deposit();

create or replace function queue_push_petty()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount text := 'Rp ' || to_char(new.amount, 'FM999G999G999');
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'petty_pending',
      jsonb_build_object(
        'audience', 'role', 'roles', array['finance', 'owner'],
        'title', 'Top up petty cash menunggu persetujuan',
        'body', v_amount || ' dari ' || coalesce(new.created_by, 'kasir')
      )
    );
    return new;
  end if;

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'petty_reviewed',
      jsonb_build_object(
        'audience', 'email', 'email', new.created_by,
        'title', case new.status
                   when 'approved' then 'Top up petty cash disetujui ✅'
                   else 'Top up petty cash ditolak' end,
        'body', case new.status
                  when 'approved' then v_amount || ' sudah masuk saldo petty cash.'
                  else v_amount || ' tidak jadi ditambahkan'
                       || coalesce(' — ' || nullif(trim(new.review_note), ''), '.')
                end
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_petty_insert on petty_cash_entries;
create trigger trg_queue_push_petty_insert
  after insert on petty_cash_entries
  for each row execute function queue_push_petty();

drop trigger if exists trg_queue_push_petty_update on petty_cash_entries;
create trigger trg_queue_push_petty_update
  after update of status on petty_cash_entries
  for each row execute function queue_push_petty();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Langkah berikutnya, di luar berkas ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Deploy Edge Function-nya:
--        supabase functions deploy send-push --project-ref xizpwtycczigjhzxegen
--
-- 2. Pasang Database Webhook di Dashboard → Database → Webhooks:
--        tabel  : push_outbox
--        event  : Insert
--        tipe   : Supabase Edge Function → send-push
--
--    Webhook dipilih, bukan pg_net di dalam trigger, supaya kegagalan
--    jaringan tidak pernah bisa membatalkan transaksi yang menulis
--    pesanannya.
--
-- 3. Periksa hasilnya kapan pun:
--        select event, created_at, sent_at, error, attempts
--        from push_outbox order by created_at desc limit 20;
--
--    Baris ber-sent_at berarti benar-benar terkirim. Yang ber-error
--    menyebutkan sebabnya. Tidak perlu menebak lagi.


-- ═══════════════════════════════════════════════════════════
-- 44. announcement_categories.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pengumuman dibagi dua jenis, dan admin resto boleh mengirim.
--
-- Jalankan SETELAH rilis_setor_petty_inbox.sql. Aman dijalankan
-- berulang kali.
--
-- Sampai sekarang kotak masuk cuma berisi satu jenis pesan: pemberitahuan
-- versi baru, dan hanya Super Admin yang boleh mengirimnya. Dua hal
-- berubah di sini — pengumuman punya jenis, dan pengumuman umum boleh
-- diterbitkan admin resto untuk restonya sendiri.

begin;

-- 'update' = pemberitahuan versi baru, 'general' = pengumuman biasa
-- termasuk promo. Baris lama semuanya pemberitahuan versi, jadi
-- defaultnya itu — dan karena kolomnya baru, seluruh baris lama terisi
-- benar tanpa perlu ditebak satu-satu.
alter table app_announcements
  add column if not exists category text not null default 'update';

alter table app_announcements
  drop constraint if exists app_announcements_category_check;
alter table app_announcements
  add constraint app_announcements_category_check
  check (category in ('update', 'general'));

-- Null berarti untuk semua resto — itulah pengumuman dari Super Admin.
-- Terisi berarti hanya untuk resto itu.
alter table app_announcements
  add column if not exists resto_id text references restaurants (id) on delete cascade;

-- Gambar promo sebagai base64, sependekatan dengan banner promo dan logo
-- resto. Menyimpannya di kolom, bukan di object storage, membuat satu
-- pengumuman tetap satu baris — dan pengumuman yang gambarnya hilang
-- karena berkasnya terhapus terpisah adalah jenis kerusakan yang tidak
-- perlu diciptakan.
alter table app_announcements
  add column if not exists image_base64 text;

create index if not exists idx_announcements_category
  on app_announcements (category, created_at desc);
create index if not exists idx_announcements_resto
  on app_announcements (resto_id);

-- ─────────────────────────────────────────────────────────────────────
-- Siapa boleh menerbitkan apa
-- ─────────────────────────────────────────────────────────────────────
--
-- Super Admin: apa saja, untuk resto mana saja.
--
-- Admin dan Owner: hanya 'general', hanya untuk restonya sendiri.
-- Pemberitahuan versi sengaja tetap milik Super Admin — itu menyangkut
-- APK yang dia terbitkan, dan admin resto tidak punya cara mengetahui
-- versi mana yang sebenarnya sudah rilis.
--
-- Batasnya ditegakkan di sini, bukan hanya di aplikasi: tombol yang
-- disembunyikan cuma menghalangi orang yang memakai aplikasinya.

drop policy if exists "announcements: super_admin write" on app_announcements;
drop policy if exists "announcements: super_admin all" on app_announcements;
create policy "announcements: super_admin all" on app_announcements
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "announcements: resto admin general" on app_announcements;
create policy "announcements: resto admin general" on app_announcements
  for insert
  with check (
    category = 'general'
    and resto_id is not null
    and is_resto_employee(resto_id, array['admin'])
  );

-- Menghapus pengumuman sendiri: yang salah kirim harus bisa ditarik,
-- tapi hanya miliknya sendiri dan hanya yang umum.
drop policy if exists "announcements: resto admin delete own" on app_announcements;
create policy "announcements: resto admin delete own" on app_announcements
  for delete
  using (
    category = 'general'
    and resto_id is not null
    and is_resto_employee(resto_id, array['admin'])
  );

commit;


-- ═══════════════════════════════════════════════════════════
-- 45. fix_device_tokens_rls.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pendaftaran token push lewat fungsi, bukan tulis langsung.
--
-- Jalankan SETELAH push_notifications.sql. Aman dijalankan berulang kali.
--
-- Gejalanya: aplikasi mendapat token FCM, tapi menyimpannya ditolak
-- dengan 42501 "new row violates row-level security policy for table
-- device_tokens" — padahal kebijakan INSERT-nya berbunyi `with check
-- (true)`, yang secara logika tidak mungkin gagal.
--
-- Sebabnya bukan kebijakan INSERT-nya. Pendaftarannya berupa upsert,
-- dan `insert ... on conflict do update` mengharuskan Postgres MEMBACA
-- baris yang bentrok lebih dulu — jadi butuh kebijakan SELECT. Tabel ini
-- sengaja dibuat tanpa kebijakan SELECT, karena daftar token tidak perlu
-- terbaca aplikasi. Niatnya benar, akibatnya upsert-nya mustahil lolos.
--
-- Menambahkan kebijakan SELECT akan membuka seluruh daftar token —
-- berikut email karyawan dan resto tempatnya bekerja — kepada siapa pun
-- yang punya anon key, dan kunci itu memang tertanam di dalam APK.
--
-- Jalan keluarnya membalik arah: tabelnya ditutup rapat dari aplikasi,
-- dan pendaftarannya lewat satu fungsi SECURITY DEFINER yang tugasnya
-- cuma itu. Aplikasi tidak lagi bisa membaca, mengubah, atau menghapus
-- baris mana pun — dia hanya bisa menitipkan tokennya sendiri.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tutup akses langsung
-- ─────────────────────────────────────────────────────────────────────
alter table device_tokens enable row level security;

drop policy if exists "device_tokens: public upsert" on device_tokens;
drop policy if exists "device_tokens: update own" on device_tokens;
drop policy if exists "device_tokens: delete own" on device_tokens;
drop policy if exists "device_tokens: insert" on device_tokens;
drop policy if exists "device_tokens: update" on device_tokens;
drop policy if exists "device_tokens: delete" on device_tokens;

revoke all on table device_tokens from anon, authenticated;

-- Tanpa kebijakan apa pun dan tanpa hak akses, tabel ini tidak bisa
-- disentuh dari aplikasi sama sekali. Yang menyentuhnya cuma fungsi di
-- bawah dan Edge Function (service role).

-- ─────────────────────────────────────────────────────────────────────
-- 2. Satu-satunya pintu masuk
-- ─────────────────────────────────────────────────────────────────────

create or replace function register_device_token(
  p_token text,
  p_email text default null,
  p_resto_id text default null,
  p_role text default null,
  p_session_id text default null,
  p_platform text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return;
  end if;

  insert into device_tokens (
    token, email, resto_id, role, session_id, platform, updated_at
  ) values (
    p_token, p_email, p_resto_id, p_role, p_session_id, p_platform, now()
  )
  on conflict (token) do update set
    -- Seluruh kolom ditimpa, bukan digabung. Satu HP bisa berpindah
    -- tangan antar shift, dan pemilik lama yang tertinggal di barisnya
    -- berarti kasir yang sudah logout tetap menerima kabar setoran
    -- penggantinya.
    email = excluded.email,
    resto_id = excluded.resto_id,
    role = excluded.role,
    session_id = excluded.session_id,
    platform = excluded.platform,
    updated_at = now();
end;
$$;

create or replace function unregister_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from device_tokens where token = p_token;
end;
$$;

-- Tamu memakai anon, karyawan yang login memakai authenticated —
-- keduanya harus bisa mendaftarkan perangkatnya.
grant execute on function register_device_token(text, text, text, text, text, text)
  to anon, authenticated;
grant execute on function unregister_device_token(text) to anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memastikan
-- ─────────────────────────────────────────────────────────────────────
-- Setelah berkas ini jalan, aplikasi versi 1.37.0 ke atas akan memakai
-- fungsi di atas. Buka Tes Notifikasi di HP; barisnya harus berbunyi
-- "Push aktif". Lalu:
--
--   select email, role, resto_id, platform, updated_at
--   from device_tokens order by updated_at desc;


-- ═══════════════════════════════════════════════════════════
-- 46. push_trigger_pg_net.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — panggil Edge Function langsung dari database, tanpa webhook.
--
-- Jalankan SETELAH fix_device_tokens_rls.sql. Aman dijalankan berulang
-- kali.
--
-- Rencana semula memakai Database Webhook, tapi tipe "Supabase Edge
-- Function" tidak tersedia di Dashboard proyek ini. pg_net melakukan hal
-- yang sama dari sisi database, dan sebetulnya lebih sedikit bagian yang
-- bisa rusak: satu tempat yang mengatur, bukan dua.
--
-- pg_net mengirim permintaannya secara asinkron — dititipkan ke antrean,
-- bukan ditunggu. Itu penting: transaksi yang menulis pesanan tidak
-- boleh menunggu jaringan pihak lain, dan kegagalan mengirim notifikasi
-- tidak boleh membatalkan pesanan yang sah.

begin;

create extension if not exists pg_net with schema extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Alamat dan kunci pemanggilnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan di tabel, bukan ditanam di badan fungsi: kunci yang tertanam
-- di definisi fungsi ikut terbaca siapa pun yang boleh melihat skema.
-- Tabel ini tidak punya kebijakan RLS satu pun, jadi tidak bisa disentuh
-- dari aplikasi — yang membacanya cuma trigger di bawah, yang berjalan
-- sebagai pemiliknya.
create table if not exists push_config (
  id int primary key default 1,
  function_url text not null,
  secret text not null,
  constraint push_config_single_row check (id = 1)
);

alter table push_config enable row level security;
revoke all on table push_config from anon, authenticated;

insert into push_config (id, function_url, secret) values (
  1,
  'https://xizpwtycczigjhzxegen.supabase.co/functions/v1/send-push',
  'fBFcxm-9uT-rQ3ha8I29_i4Y4xm_vq3a-oE1gOFEHhM'
)
on conflict (id) do update set
  function_url = excluded.function_url,
  secret = excluded.secret;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Pemicunya
-- ─────────────────────────────────────────────────────────────────────

create or replace function notify_push_outbox()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_config push_config;
begin
  select * into v_config from push_config where id = 1;
  if v_config.function_url is null then
    return new;
  end if;

  -- Barisnya dikirim utuh dalam bentuk yang sama dengan yang dikirim
  -- Database Webhook, supaya Edge Function-nya tidak perlu tahu dari
  -- mana panggilannya datang.
  perform net.http_post(
    url := v_config.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-kaata-hook-secret', v_config.secret
    ),
    body := jsonb_build_object(
      'record', jsonb_build_object(
        'id', new.id,
        'resto_id', new.resto_id,
        'event', new.event,
        'payload', new.payload
      )
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_push_outbox on push_outbox;
create trigger trg_notify_push_outbox
  after insert on push_outbox
  for each row execute function notify_push_outbox();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memastikan
-- ─────────────────────────────────────────────────────────────────────
-- Buat satu pesanan, lalu:
--
--   select event, created_at, sent_at, error from push_outbox
--   order by created_at desc limit 5;
--
-- sent_at terisi berarti benar-benar terkirim. Kalau masih kosong,
-- lihat antrean pg_net-nya — di situ tercatat jawaban HTTP-nya:
--
--   select id, created, status_code, content from net._http_response
--   order by created desc limit 5;


-- ═══════════════════════════════════════════════════════════
-- 47. payment_gateway.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — QRIS sungguhan lewat Xendit.
--
-- Jalankan SETELAH customer_cash_payment.sql. Aman dijalankan berulang
-- kali.
--
-- Sampai sekarang QRIS-nya simulasi: kodenya dibangkitkan sendiri dan
-- yang menandai lunas adalah tombol yang ditekan pelanggan. Berkas ini
-- menyiapkan sisi database untuk pembayaran yang benar-benar terjadi —
-- tagihannya dibuat di server, dan yang menyatakannya lunas adalah
-- webhook dari Xendit, bukan siapa pun yang memegang HP.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tagihan yang dibuat di penyedia
-- ─────────────────────────────────────────────────────────────────────

-- Satu baris per tagihan, bukan kolom tambahan di `orders`.
--
-- Sebuah pesanan bisa punya lebih dari satu tagihan: QR yang kedaluwarsa
-- sebelum dibayar harus dibuatkan yang baru, dan yang lama tetap perlu
-- tercatat — kalau ternyata dibayar juga di detik terakhir, webhooknya
-- datang menyebut tagihan yang mana.
create table if not exists payment_charges (
  id uuid primary key default gen_random_uuid(),

  order_id uuid not null references orders (id) on delete cascade,
  resto_id text references restaurants (id) on delete cascade,

  provider text not null default 'xendit',

  -- Pengenal yang kita kirim ke penyedia, dan yang dikembalikan lagi di
  -- webhooknya. Unik, karena itulah yang dipakai mencocokkan kembali.
  reference_id text not null unique,

  -- Pengenal milik penyedia.
  provider_charge_id text,

  -- Isi QR-nya. Disimpan supaya layar yang dibuka ulang menampilkan QR
  -- yang sama persis, bukan membuat tagihan baru tiap kali orangnya
  -- kembali ke layar itu.
  qr_string text,

  amount bigint not null,
  status text not null default 'pending',
  expires_at timestamptz,
  paid_at timestamptz,

  -- Jawaban mentah dari penyedia, apa adanya. Saat ada selisih uang,
  -- inilah satu-satunya keterangan yang tidak bisa dibantah.
  raw jsonb,

  created_at timestamptz not null default now()
);

alter table payment_charges
  drop constraint if exists payment_charges_status_check;
alter table payment_charges add constraint payment_charges_status_check
  check (status in ('pending', 'paid', 'expired', 'failed'));

create index if not exists payment_charges_order_idx on payment_charges (order_id);
create index if not exists payment_charges_status_idx on payment_charges (status, created_at desc);

alter table payment_charges enable row level security;

-- Tidak ada kebijakan apa pun untuk aplikasi. Yang membuat tagihan dan
-- yang menandainya lunas sama-sama Edge Function dengan service role.
-- Membiarkan aplikasi menulis ke sini berarti membiarkan siapa pun yang
-- memegang anon key menyatakan tagihannya sendiri lunas.
revoke all on table payment_charges from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Pelunasan, hanya dari webhook
-- ─────────────────────────────────────────────────────────────────────

-- Dipanggil Edge Function penerima webhook. Satu fungsi, satu tugas:
-- menandai tagihan dan pesanannya lunas, sekali saja.
--
-- Webhook penyedia bisa datang dua kali untuk pembayaran yang sama —
-- itu perilaku normal, bukan kesalahan. Tanpa penjagaan di sini,
-- pesanan yang sama akan masuk jurnal dua kali dan pemasukan hari itu
-- tercatat dobel.
create or replace function settle_gateway_payment(
  p_reference_id text,
  p_provider_charge_id text default null,
  p_raw jsonb default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_charge payment_charges;
begin
  select * into v_charge from payment_charges
  where reference_id = p_reference_id for update;

  if v_charge.id is null then
    return 'tagihan tidak dikenal';
  end if;

  if v_charge.status = 'paid' then
    return 'sudah lunas sebelumnya';
  end if;

  update payment_charges set
    status = 'paid',
    paid_at = now(),
    provider_charge_id = coalesce(p_provider_charge_id, provider_charge_id),
    raw = coalesce(p_raw, raw)
  where id = v_charge.id;

  -- Pesanannya sendiri hanya disentuh kalau memang masih menunggu.
  -- Pesanan yang sudah dilunasi lewat jalan lain — misalnya pelanggan
  -- akhirnya membayar tunai di kasir — tidak boleh ikut tertimpa.
  update orders set payment_status = 'paid'
  where id = v_charge.order_id and payment_status = 'pending';

  return 'lunas';
end;
$$;

-- Tidak diberikan ke anon maupun authenticated. Hanya service role, yang
-- memang melewati pemeriksaan hak akses.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Langkah berikutnya, di luar berkas ini
-- ─────────────────────────────────────────────────────────────────────
--
--   supabase secrets set --project-ref xizpwtycczigjhzxegen \
--     XENDIT_SECRET_KEY='xnd_development_...' \
--     XENDIT_CALLBACK_TOKEN='...'
--
--   supabase functions deploy create-qris    --project-ref xizpwtycczigjhzxegen
--   supabase functions deploy xendit-webhook --project-ref xizpwtycczigjhzxegen --no-verify-jwt
--
-- Lalu daftarkan URL webhooknya di Dashboard Xendit → Settings →
-- Callbacks → QR Code payment:
--
--   https://xizpwtycczigjhzxegen.supabase.co/functions/v1/xendit-webhook
--
-- Memeriksa hasilnya kapan pun:
--
--   select reference_id, amount, status, expires_at, paid_at
--   from payment_charges order by created_at desc limit 20;


-- ═══════════════════════════════════════════════════════════
-- 48. gateway_settlement.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pencairan dana dari payment gateway.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang pesanan QRIS dicatat penuh dan seketika ke GL QRIS,
-- seolah uangnya langsung ada di rekening. Dengan gateway sungguhan itu
-- tidak benar dua kali:
--
--   1. Yang benar-benar masuk rekening adalah nominal DIKURANGI MDR
--      (sekitar 0,7%).
--   2. Masuknya BARU T+1 atau T+2, bukan saat pelanggan membayar.
--
-- Kalau dibiarkan, GL QRIS akan terus bertambah tanpa pernah cocok
-- dengan mutasi bank mana pun, dan selisihnya menumpuk tiap hari sampai
-- tidak ada yang berani menutup buku.
--
-- Yang berubah di sini bukan pencatatan pemasukannya — itu tetap seperti
-- sekarang. GL QRIS-nya sendiri yang berubah arti: bukan "uang di
-- rekening", melainkan "uang yang ditahan penyedia dan akan cair".
-- Berkas ini menambahkan kejadian keduanya: saat dananya benar-benar
-- cair.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Akun biaya MDR
-- ─────────────────────────────────────────────────────────────────────

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- ─────────────────────────────────────────────────────────────────────
-- 2. Catatan pencairan
-- ─────────────────────────────────────────────────────────────────────

-- Bruto, biaya, dan neto disimpan ketiganya, walaupun yang satu bisa
-- dihitung dari dua lainnya.
--
-- Ini bukan penyimpanan berlebih: yang tertulis di mutasi bank adalah
-- neto, yang tertulis di laporan penyedia adalah bruto dan biaya, dan
-- saat keduanya tidak cocok — pembulatan, biaya tambahan, penyesuaian —
-- yang dibutuhkan justru ketiganya apa adanya. Menghitung ulang salah
-- satunya berarti menghapus bukti bahwa mereka pernah berbeda.
create table if not exists gateway_settlements (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  settled_on date not null default (now() at time zone 'Asia/Jakarta')::date,

  gross_amount bigint not null,
  fee_amount bigint not null default 0,
  net_amount bigint not null,

  provider text not null default 'xendit',
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists gateway_settlements_resto_idx
  on gateway_settlements (resto_id, settled_on desc);

alter table gateway_settlements enable row level security;

drop policy if exists "gateway_settlements: finance read" on gateway_settlements;
create policy "gateway_settlements: finance read" on gateway_settlements
  for select using (is_resto_employee(resto_id, array['finance', 'admin']));

-- Hanya Finance yang mencatatnya. Ini bukan pengajuan yang butuh
-- persetujuan seperti setoran tunai — Finance sedang menyalin apa yang
-- sudah terjadi di rekening, bukan meminta sesuatu terjadi.
drop policy if exists "gateway_settlements: finance write" on gateway_settlements;
create policy "gateway_settlements: finance write" on gateway_settlements
  for all using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));

-- ─────────────────────────────────────────────────────────────────────
-- 3. Jurnalnya
-- ─────────────────────────────────────────────────────────────────────

-- Tiga kaki, dan ketiganya harus seimbang:
--
--   GL QRIS         debit  bruto   uang meninggalkan penampungan penyedia
--   GL Total Saldo  credit neto    yang benar-benar masuk rekening
--   GL Biaya MDR    credit biaya   potongan penyedia, diakui sebagai beban
--
-- Debit = uang keluar dari akun, credit = uang masuk ke akun — konvensi
-- yang sama dengan seluruh jurnal MerchantPOS lainnya.
create or replace function log_gateway_settlement_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_qris_gl record;
  v_total_gl record;
  v_fee_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  select * into v_qris_gl from _gl_account_for(new.resto_id, 'qris');
  if v_qris_gl.gl_code is not null and v_qris_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_qris_gl.gl_code, v_qris_gl.gl_name, 'gateway_settlement', new.id::text,
      new.gross_amount, 'debit', 'Pencairan gateway #' || v_ref
    );
  end if;

  select * into v_total_gl from _gl_account_for(new.resto_id, 'total_balance');
  if v_total_gl.gl_code is not null and v_total_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_total_gl.gl_code, v_total_gl.gl_name, 'gateway_settlement', new.id::text,
      new.net_amount, 'credit', 'Dana gateway masuk rekening #' || v_ref
    );
  end if;

  -- Biaya nol tidak dijurnal sama sekali. Baris bernilai nol bukan
  -- keterangan, cuma derau yang harus dilewati mata setiap kali.
  if new.fee_amount > 0 then
    select * into v_fee_gl from _gl_account_for(new.resto_id, 'gateway_fee');
    if v_fee_gl.gl_code is not null and v_fee_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_fee_gl.gl_code, v_fee_gl.gl_name, 'gateway_settlement', new.id::text,
        new.fee_amount, 'credit', 'Biaya MDR pencairan #' || v_ref
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_gateway_settlement on gateway_settlements;
create trigger trg_log_gateway_settlement
  after insert on gateway_settlements
  for each row execute function log_gateway_settlement_journal();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- Isi nomor GL untuk "GL Biaya MDR" di Finance → Mapping GL Account.
-- Tanpa itu, biayanya tidak akan tercatat dan jurnal pencairannya jadi
-- timpang sebesar potongan penyedia.
--
-- Memeriksa keseimbangannya kapan pun:
--
--   select reference_id,
--          sum(case when entry_type = 'debit'  then amount else 0 end) as debit,
--          sum(case when entry_type = 'credit' then amount else 0 end) as kredit
--   from gl_journal_entries
--   where reference_type = 'gateway_settlement'
--   group by reference_id;


-- ═══════════════════════════════════════════════════════════
-- 49. resto_payment_accounts.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pencairan langsung ke rekening masing-masing resto.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang seluruh pembayaran QRIS masuk ke satu akun penyedia:
-- yang kuncinya terpasang di server. Untuk resto milik sendiri itu tidak
-- masalah. Untuk resto milik orang lain, itu berarti uang mereka mampir
-- dulu ke rekening MerchantPOS — dan menampung lalu meneruskan dana milik
-- pihak lain bukan sekadar urusan pembukuan.
--
-- Jalan keluarnya sub-akun: tiap resto punya akunnya sendiri di
-- penyedia, dan pembayarannya dibuat atas nama akun itu. Dananya cair
-- langsung ke rekening restonya, tanpa pernah lewat rekening MerchantPOS.
--
-- Yang disimpan di sini hanya PENGENAL sub-akunnya, bukan kuncinya.
-- Menyimpan secret key milik resto lain berarti satu kebocoran database
-- membuka seluruh akun penyedia mereka sekaligus — kerugian yang bukan
-- milik kita tapi kita yang menyebabkannya.

begin;

create table if not exists resto_payment_accounts (
  resto_id text primary key references restaurants (id) on delete cascade,

  provider text not null default 'xendit',

  -- Pengenal sub-akun di penyedia. Dikirim sebagai header saat membuat
  -- tagihan, dan itu yang menentukan ke rekening siapa dananya cair.
  account_id text not null,

  -- Sekadar catatan supaya Finance tahu ini akun yang mana tanpa harus
  -- membuka dashboard penyedia.
  account_label text,

  active boolean not null default true,
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table resto_payment_accounts enable row level security;

-- Tidak terbaca pelanggan. Tabel `settings` disiarkan realtime ke layar
-- pembayaran pelanggan, jadi pengenal ini sengaja tidak dititipkan di
-- sana — bukan karena rahasia, tapi karena tidak ada gunanya di HP
-- pelanggan dan yang tidak berguna di sana sebaiknya tidak ada di sana.
drop policy if exists "resto_payment_accounts: staff read" on resto_payment_accounts;
create policy "resto_payment_accounts: staff read" on resto_payment_accounts
  for select using (
    is_super_admin() or is_resto_employee(resto_id, array['finance', 'admin'])
  );

drop policy if exists "resto_payment_accounts: staff write" on resto_payment_accounts;
create policy "resto_payment_accounts: staff write" on resto_payment_accounts
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['finance'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Aktifkan xenPlatform di akun Xendit MerchantPOS (butuh verifikasi
--    badan usaha; di mode uji bisa langsung dicoba).
--
-- 2. Buat sub-akun untuk tiap resto — lewat Dashboard atau API:
--
--      curl -X POST https://api.xendit.co/v2/accounts \
--        -u 'xnd_development_...:' -H 'Content-Type: application/json' \
--        -d '{"email":"resto@contoh.com","type":"OWNED",
--             "public_profile":{"business_name":"Kaata Resto Dago"}}'
--
--    Jawabannya memuat "id" berawalan angka/huruf — itu yang diisikan
--    ke aplikasi lewat Finance → Pengaturan Pembayaran.
--
-- 3. Tiap resto melengkapi rekening banknya sendiri di sub-akun itu.
--    Sampai itu selesai, dananya tertahan di saldo sub-akun — tidak
--    hilang, tapi juga tidak cair.
--
-- Memeriksa resto mana yang sudah terpasang:
--
--   select r.name, a.account_id, a.active
--   from restaurants r
--   left join resto_payment_accounts a on a.resto_id = r.id;


-- ═══════════════════════════════════════════════════════════
-- 50. announcement_push.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pengumuman ikut membunyikan HP.
--
-- Selama ini pengumuman hanya duduk di Kotak Masuk. Kotak Masuk baru
-- dilihat orang kalau dia membuka aplikasinya, dan orang membuka
-- aplikasinya kalau ada yang memanggil. Pengumuman yang menunggu
-- dibuka adalah pengumuman yang dibaca seminggu kemudian — atau tidak
-- sama sekali.
--
-- Jangkauannya mengikuti resto_id pengumuman itu sendiri, aturan yang
-- sama dengan yang sudah dipakai saat menampilkannya:
--   resto_id kosong  → dari Super Admin, kabar versi baru, untuk semua
--   resto_id terisi  → dari admin resto itu, hanya perangkat restonya
--                      — pelanggan maupun karyawan, apa pun perannya.
--
-- Jalankan di SQL Editor Supabase.

begin;

create or replace function queue_push_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into push_outbox (resto_id, event, payload) values (
    new.resto_id, 'announcement',
    jsonb_build_object(
      'audience', 'all',
      'title', new.title,
      -- Isi pengumuman bisa sepanjang apa pun; baris notifikasi tidak.
      -- Dipotong di sini supaya yang sampai di layar kunci adalah
      -- kalimat pembuka yang utuh, bukan paragraf yang dipenggal
      -- Android di tempat sembarang.
      'body', case
                when length(new.body) > 160
                  then left(new.body, 157) || '...'
                else new.body
              end
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_queue_push_announcement on app_announcements;
create trigger trg_queue_push_announcement
  after insert on app_announcements
  for each row execute function queue_push_announcement();

commit;


-- ═══════════════════════════════════════════════════════════
-- 51. cash_payment_expiry.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pesanan tunai yang tidak dilunasi di kasir hangus sendiri.
--
-- Pelanggan yang memesan dari HP lalu memilih bayar tunai diarahkan ke
-- meja kasir. Sebagian tidak pernah sampai ke sana: berubah pikiran,
-- salah pencet, atau memang tidak berniat datang. Tanpa batas waktu,
-- pesanan itu menetap selamanya di layar Pending Payment dan di dapur —
-- dan tiap hari sisanya bertambah sedikit, sampai layarnya tidak lagi
-- bisa dipakai membaca apa yang benar-benar sedang ditunggu.
--
-- Tiga puluh menit dihitung dari pesanannya dibuat. Angka yang sama
-- ditulis di HP pelanggan (CustomerOrder.paymentWindow) — kalau salah
-- satunya diubah, keduanya harus diubah.
--
-- Butuh pg_cron. Kalau belum aktif: Dashboard → Database → Extensions →
-- cari "pg_cron" → Enable. Aman dijalankan berulang kali.

begin;

create extension if not exists pg_cron with schema extensions;

-- 'expired' — dibatalkan karena tidak dibayar. Dibedakan dari 'pending'
-- supaya hilang dari antrean kasir dan dapur, dan dibedakan dari 'paid'
-- supaya tidak pernah ikut terhitung sebagai pendapatan.
--
-- Daftarnya ditulis lengkap — termasuk 'cancelled' yang baru
-- diperkenalkan berkas lain. Berkas yang menuliskan daftar sepanjang
-- zamannya sendiri berjalan baik tepat sekali: saat dijalankan berurutan
-- di database kosong. Menjalankan ulang yang lebih tua sesudah yang
-- lebih baru menyempitkan daftarnya lagi, dan baris yang terlanjur
-- memakai nilai baru langsung melanggarnya:
--
--   check constraint "orders_payment_status_check" is violated by some row
--
-- Tidak ada satu pun data yang salah di sana. Yang salah adalah
-- batasannya yang mundur.
alter table orders drop constraint if exists orders_payment_status_check;
alter table orders add constraint orders_payment_status_check
  check (payment_status in ('pending', 'paid', 'expired', 'cancelled'));

create or replace function expire_unpaid_cash_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with hangus as (
    update orders
    set payment_status = 'expired'
    where payment_status = 'pending'
      and source = 'customer'
      -- Hanya yang tunai. Pesanan QRIS punya tenggangnya sendiri di sisi
      -- penyedia pembayaran, dan membatalkannya dari sini berarti
      -- membatalkan pesanan yang uangnya mungkin sedang dalam perjalanan.
      and _normalize_payment_method(source, payment_method) = 'cash'
      and created_at <= now() - interval '30 minutes'
    returning 1
  )
  select count(*) into v_count from hangus;
  return v_count;
end;
$$;

-- Tiap menit. Tenggangnya tetap 30 menit — yang diputuskan di sini cuma
-- seberapa cepat pesanan yang sudah lewat tenggang benar-benar hilang
-- dari layar, dan menitan sudah cukup rapat untuk itu.
select cron.unschedule('expire-unpaid-cash-orders')
where exists (
  select 1 from cron.job where jobname = 'expire-unpaid-cash-orders'
);

select cron.schedule(
  'expire-unpaid-cash-orders',
  '* * * * *',
  $$select expire_unpaid_cash_orders();$$
);

commit;


-- ═══════════════════════════════════════════════════════════
-- 52. counter_charge.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — tagihan QRIS di meja kasir.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Pesanan yang diinput kasir baru dibuat SETELAH pembayarannya diterima,
-- bukan sebelum — itu urutan yang sudah ada sejak awal, dan mengubahnya
-- berarti membongkar alur checkout beserta pengurangan stoknya. Jadi
-- tagihannya boleh berdiri tanpa pesanan: yang menghubungkannya nanti
-- adalah transaksi yang tercatat sesudahnya.

begin;

alter table payment_charges alter column order_id drop not null;

-- Status tagihan, untuk ditanyakan aplikasi kasir sambil menunggu.
--
-- Lewat fungsi, bukan membaca tabelnya langsung: tabel tagihan tetap
-- tertutup rapat dari aplikasi. Yang boleh diketahui cuma satu kata —
-- sudah dibayar atau belum — dan bukan seluruh isinya.
create or replace function gateway_charge_status(p_reference_id text)
returns text
language sql
security definer
set search_path = public
as $$
  select status from payment_charges where reference_id = p_reference_id;
$$;

grant execute on function gateway_charge_status(text) to anon, authenticated;

commit;


-- ═══════════════════════════════════════════════════════════
-- 53. gateway_account_super_admin.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pengenal sub-akun Xendit jadi urusan Super Admin saja.
--
-- Jalankan SETELAH resto_payment_accounts.sql. Aman diulang.
--
-- Sebelumnya Finance resto boleh membaca dan mengubah pengenal ini dari
-- Pengaturan Pembayaran. Itu keliru dari dua sisi.
--
-- Yang pertama: dia tidak punya cara mengetahui nilainya. Sub-akunnya
-- dibuat di akun Xendit milik MerchantPOS dan pengenalnya ditentukan
-- Xendit — bukan sesuatu yang bisa dicari orang resto di mana pun.
-- Kolom isian yang jawabannya tidak dimiliki siapa pun yang melihatnya
-- hanya mengundang tebakan.
--
-- Yang kedua, dan ini yang berbahaya: salah ketik satu huruf mengirim
-- seluruh pembayaran QRIS resto ini ke sub-akun resto lain. Uangnya
-- tidak hilang — tapi cair ke rekening orang lain, dan yang menemukan
-- selisihnya adalah kedua resto sekaligus, berhari-hari kemudian.
--
-- Batasnya ditegakkan di sini, bukan hanya dengan menyembunyikan
-- kolomnya di aplikasi: kolom yang disembunyikan cuma menghalangi orang
-- yang memakai aplikasinya.
--
-- Edge Function create-qris tetap bisa membacanya — dia memakai service
-- role, yang memang melewati RLS.

begin;

drop policy if exists "resto_payment_accounts: staff read" on resto_payment_accounts;
drop policy if exists "resto_payment_accounts: staff write" on resto_payment_accounts;

drop policy if exists "resto_payment_accounts: super_admin all" on resto_payment_accounts;
create policy "resto_payment_accounts: super_admin all" on resto_payment_accounts
  for all using (is_super_admin()) with check (is_super_admin());

commit;


-- ═══════════════════════════════════════════════════════════
-- 54. level_groups.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — tiap resto menyusun sendiri kelompok levelnya.
--
-- Jalankan SETELAH product_level_groups.sql. Aman diulang.
--
-- Sebelumnya daftarnya tertanam di dalam aplikasi: lima kelompok tetap
-- (Level Pedas, Level Gula, Level Es, Suhu, Ukuran), sama untuk semua
-- resto. Cukup untuk warung nasi dan kedai kopi, dan langsung kurang
-- untuk yang berikutnya — tingkat kematangan steak, pilihan topping,
-- jenis susu. Resto yang butuh satu kelompok di luar lima itu tidak
-- punya jalan apa pun selain menyuruh pelanggannya mengetik di kolom
-- catatan, yang tidak terbaca sebagai pilihan oleh dapur maupun kasir.
--
-- Produk tetap menyandang NAMA kelompoknya (products.level_groups),
-- bukan id-nya. Sengaja: itu yang sudah tersimpan di ribuan baris
-- produk dan pesanan, dan mengubahnya jadi id berarti membongkar
-- riwayat pesanan yang sudah terjadi hanya demi kerapian.

begin;

create table if not exists level_groups (
  id text primary key,
  resto_id text not null references restaurants (id) on delete cascade,

  -- Namanya yang mengikat produk ke kelompok ini, jadi tidak boleh
  -- kembar di dalam satu resto.
  name text not null,

  options jsonb not null default '[]'::jsonb,

  -- Urutan tampilnya di layar pesan. Kelompok yang paling sering
  -- dipakai pantas berada di atas, dan itu berbeda tiap resto.
  sort_order integer not null default 0,

  created_at timestamptz not null default now(),
  unique (resto_id, name)
);

create index if not exists idx_level_groups_resto on level_groups (resto_id);

alter table level_groups enable row level security;

-- Dibaca siapa saja, termasuk pelanggan tamu yang belum login: tanpa
-- ini dropdown level di layar pesan kosong, dan pesanan pedas tidak
-- bisa dibedakan dari yang tidak.
drop policy if exists "level_groups: public read" on level_groups;
create policy "level_groups: public read" on level_groups
  for select using (true);

drop policy if exists "level_groups: admin write" on level_groups;
create policy "level_groups: admin write" on level_groups
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['admin'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['admin'])
  );

-- ─────────────────────────────────────────────────────────────────────
-- Bibit: lima kelompok yang selama ini tertanam di aplikasi
-- ─────────────────────────────────────────────────────────────────────
--
-- Disemaikan ke tiap resto yang sudah ada, sekali. Tanpa ini semua resto
-- membuka tab Level yang kosong dan produk mereka yang sudah menyandang
-- "Level Pedas" menunjuk kelompok yang tidak ada lagi.
--
-- `on conflict do nothing` yang membuatnya aman diulang: resto yang
-- sudah menyunting "Level Pedas"-nya sendiri tidak dikembalikan ke
-- bentuk bawaan hanya karena berkas ini dijalankan dua kali.

insert into level_groups (id, resto_id, name, options, sort_order)
select
  r.id || ':' || b.name,
  r.id,
  b.name,
  b.options,
  b.sort_order
from restaurants r
cross join (values
  ('Level Pedas',
   '["Tidak Pedas","Sedang","Pedas","Extra Pedas"]'::jsonb, 0),
  ('Level Gula',
   '["Normal","Kurang Manis","Setengah Manis","Tanpa Gula"]'::jsonb, 1),
  ('Level Es',
   '["Normal","Less Ice","No Ice"]'::jsonb, 2),
  ('Suhu',
   '["Panas","Dingin"]'::jsonb, 3),
  ('Ukuran',
   '["Regular","Large"]'::jsonb, 4)
) as b(name, options, sort_order)
on conflict (resto_id, name) do nothing;

commit;

-- Resto yang dibuat SESUDAH ini tetap perlu bibitnya. Pemicu di bawah
-- yang mengurusnya, supaya tidak ada yang harus ingat menjalankan
-- berkas ini lagi tiap kali ada resto baru.
create or replace function seed_level_groups()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into level_groups (id, resto_id, name, options, sort_order)
  select new.id || ':' || b.name, new.id, b.name, b.options, b.sort_order
  from (values
    ('Level Pedas', '["Tidak Pedas","Sedang","Pedas","Extra Pedas"]'::jsonb, 0),
    ('Level Gula', '["Normal","Kurang Manis","Setengah Manis","Tanpa Gula"]'::jsonb, 1),
    ('Level Es', '["Normal","Less Ice","No Ice"]'::jsonb, 2),
    ('Suhu', '["Panas","Dingin"]'::jsonb, 3),
    ('Ukuran', '["Regular","Large"]'::jsonb, 4)
  ) as b(name, options, sort_order)
  on conflict (resto_id, name) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_level_groups on restaurants;
create trigger trg_seed_level_groups
  after insert on restaurants
  for each row execute function seed_level_groups();


-- ═══════════════════════════════════════════════════════════
-- 55. product_out_of_stock.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — ketersediaan produk ditandai, bukan dihitung.
--
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang produk hilang dari menu begitu stoknya 0. Itu memaksa
-- tiap resto mengurus angka yang sebagian besar tidak pernah mereka
-- hitung: nasi goreng tidak punya "sisa 7 porsi", yang ada cuma "masih
-- ada" atau "bahannya habis". Resto yang membiarkan stoknya 0 karena
-- angkanya memang tidak relevan justru kehilangan seluruh menunya, dan
-- tidak pernah tahu kenapa.
--
-- Sekarang angka stok jadi catatan biasa — boleh diisi, boleh tidak —
-- dan yang menentukan bisa dipesan atau tidak cuma kolom ini, yang
-- dinyatakan sengaja oleh orang yang tahu keadaan dapurnya.

begin;

alter table products
  add column if not exists out_of_stock boolean not null default false;

-- Stok tidak lagi wajib. Produk yang tidak diisi angkanya bukan produk
-- yang habis — cuma produk yang tidak dihitung.
alter table products alter column stock drop not null;
alter table products alter column stock set default 0;

-- Produk lama dianggap tersedia, termasuk yang stoknya 0.
--
-- Sebagian dari mereka memang benar-benar habis, dan menyalakannya
-- kembali berarti resto harus menandainya lagi satu per satu. Itu
-- disengaja: resto jauh lebih cepat menandai barang yang habis daripada
-- menemukan sendiri kenapa separuh menunya tidak pernah muncul.
update products set out_of_stock = false where out_of_stock is null;

commit;

-- Catatan: fungsi decrement_stock tetap dipakai — angkanya masih
-- berguna buat resto yang memang menghitung. Yang berubah cuma
-- artinya: mencapai nol tidak lagi menyembunyikan produknya.


-- ═══════════════════════════════════════════════════════════
-- 56. resto_order_types.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — resto menentukan sendiri melayani Dine In, Take Away, atau
-- keduanya.
--
-- Aman dijalankan berulang kali.
--
-- Selama ini kedua pilihan selalu ditawarkan di layar checkout, di
-- semua resto. Padahal tidak semua resto melayani keduanya: gerai food
-- court dan cloud kitchen tidak punya meja sama sekali. Selama
-- pilihannya tetap ada, pesanan yang tidak bisa dilayani tetap masuk —
-- dan yang harus menolaknya adalah orang, di depan pelanggan yang sudah
-- membayar.
--
-- Keduanya true untuk semua resto yang sudah ada. Mematikan salah
-- satunya harus jadi keputusan yang diambil sengaja, bukan akibat kolom
-- baru yang belum sempat diisi.

begin;

alter table restaurants
  add column if not exists dine_in_enabled boolean not null default true;
alter table restaurants
  add column if not exists take_away_enabled boolean not null default true;

-- Resto yang tidak melayani keduanya tidak bisa menerima pesanan apa
-- pun — layar checkoutnya tidak punya satu pun pilihan yang bisa
-- ditekan. Itu bukan konfigurasi, itu resto yang tutup, dan untuk itu
-- sudah ada kolom `active`.
alter table restaurants drop constraint if exists restaurants_order_type_check;
alter table restaurants add constraint restaurants_order_type_check
  check (dine_in_enabled or take_away_enabled);

commit;


-- ═══════════════════════════════════════════════════════════
-- 57. default_gl_accounts.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — resto baru langsung punya bagan akun dan tarif pajaknya.
--
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang resto yang baru dibuat lahir tanpa satu pun GL
-- account. Akibatnya bukan sekadar merepotkan: pemicu jurnal melewatkan
-- baris yang GL-nya kosong, jadi transaksi hari-hari pertama benar-benar
-- terjadi, uangnya benar-benar diterima, tapi tidak pernah masuk Jurnal
-- GL. Yang menemukan lubangnya adalah Finance, berminggu-minggu
-- kemudian, saat mencari ke mana perginya penjualan minggu pembukaan.
--
-- Semua yang diisi di sini tetap bisa diubah Finance lewat Mapping GL
-- Account. Yang diberikan cuma titik berangkat yang masuk akal.
--
-- Pengelompokan nomornya:
--
--   195xxxx  Pemasukan (tunai, QRIS, transfer, agregat)
--   196xxxx  Pajak & service
--   198xxxx  Petty cash
--   199xxxx  Total saldo
--   210xxxx  Suspense & pengeluaran
--   220xxxx  Payment gateway & diskon

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tarif bawaan
-- ─────────────────────────────────────────────────────────────────────
--
-- PPN 11% dan service 5% — yang paling lazim dipakai restoran di
-- Indonesia. Nol sebagai bawaan terlihat aman, tapi artinya tiap resto
-- baru menjual dengan harga yang belum memuat pajak sampai ada yang
-- ingat menyetelnya, dan selisih itu tidak bisa ditagih ulang ke
-- pelanggan yang sudah pulang.
--
-- Hanya berlaku untuk resto yang dibuat SESUDAH ini. Resto yang sudah
-- ada tidak disentuh: mengubah tarif pajak resto yang sedang berjalan
-- akan mengubah harga jual seluruh menunya dalam satu perintah.
alter table restaurants alter column ppn_percent set default 11;
alter table restaurants alter column service_percent set default 5;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Bagan akun bawaan
-- ─────────────────────────────────────────────────────────────────────

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
    -- Payment gateway & diskon
    ('gateway_fee',      '2200001', 'GL Biaya Payment Gateway'),
    ('discount',         '2200002', 'GL Diskon Penjualan');
$$;

-- Akun biaya bawaan. Terpisah dari yang di atas karena pengeluaran
-- memang berkategori banyak, dan tiap resto akan menambah sendiri
-- sesudahnya.
create or replace function _default_expense_gl_accounts()
returns table (gl_code text, gl_name text)
language sql
immutable
as $$
  values
    ('2101001', 'GL Biaya Operasional'),
    ('2101002', 'GL Biaya Bahan Baku'),
    ('2101003', 'GL Biaya Gaji'),
    ('2101004', 'GL Biaya Sewa'),
    ('2101005', 'GL Biaya Listrik & Air'),
    ('2101009', 'GL Biaya Lain-lain');
$$;

create or replace function seed_gl_accounts(p_resto_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- `do nothing`, bukan `do update`: resto yang sudah menyetel
  -- nomornya sendiri tidak boleh dikembalikan ke bawaan hanya karena
  -- berkas ini dijalankan lagi. Yang diisi cuma yang belum ada.
  insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
  select p_resto_id, d.payment_method, d.gl_code, d.gl_name
  from _default_gl_accounts() d
  on conflict (resto_id, payment_method) do nothing;

  insert into expense_gl_accounts (resto_id, gl_code, gl_name)
  select p_resto_id, d.gl_code, d.gl_name
  from _default_expense_gl_accounts() d
  where not exists (
    select 1 from expense_gl_accounts e
    where e.resto_id = p_resto_id and e.gl_code = d.gl_code
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Resto baru langsung terisi
-- ─────────────────────────────────────────────────────────────────────
--
-- Lewat pemicu, bukan lewat aplikasi. Resto bisa dibuat dari layar Super
-- Admin, dari SQL saat memulihkan data, atau dari alat lain nanti — dan
-- yang lahir tanpa bagan akun akan diam-diam kehilangan jurnalnya.
create or replace function seed_gl_accounts_for_new_resto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform seed_gl_accounts(new.id);
  return new;
end;
$$;

drop trigger if exists trg_seed_gl_accounts on restaurants;
create trigger trg_seed_gl_accounts
  after insert on restaurants
  for each row execute function seed_gl_accounts_for_new_resto();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Resto yang sudah ada ikut dilengkapi
-- ─────────────────────────────────────────────────────────────────────
--
-- Hanya yang belum punya. Nomor yang sudah disetel Finance tetap seperti
-- adanya — lihat `do nothing` di atas.
do $$
declare
  r record;
begin
  for r in select id from restaurants loop
    perform seed_gl_accounts(r.id);
  end loop;
end $$;

commit;

-- Memeriksa hasilnya:
--
--   select r.name, count(g.*) as akun
--   from restaurants r
--   left join gl_accounts g on g.resto_id = r.id
--   group by r.name order by akun;


-- ═══════════════════════════════════════════════════════════
-- 58. discounts.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — diskon: per menu (termasuk bundling) atau minimum belanja.
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


-- ═══════════════════════════════════════════════════════════
-- 59. promo_banner_period.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — banner promo punya masa berlaku.
--
-- Aman dijalankan berulang kali.
--
-- Sebelumnya banner hanya punya saklar aktif/nonaktif, dan itu berarti
-- ada orang yang harus ingat mematikannya. Promo Ramadan yang masih
-- terpasang di bulan Juli bukan sekadar salah — ia menjanjikan harga
-- yang sudah tidak berlaku kepada orang yang sedang memesan.
--
-- Tanggal, bukan timestamp: resto berpikir dalam hari, dan "sampai 31
-- Agustus" berarti sampai tutup toko tanggal 31.

begin;

alter table promo_banners add column if not exists starts_on date;
alter table promo_banners add column if not exists ends_on date;

alter table promo_banners drop constraint if exists promo_banners_period_check;
alter table promo_banners add constraint promo_banners_period_check
  check (ends_on is null or starts_on is null or ends_on > starts_on);

commit;


-- ═══════════════════════════════════════════════════════════
-- 60. announcement_audience.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pengumuman resto memilih sasarannya: karyawan, pelanggan,
-- atau keduanya.
--
-- Jalankan SETELAH announcement_categories.sql dan announcement_push.sql.
-- Aman dijalankan berulang kali.
--
-- Sebelumnya satu pengumuman resto pergi ke semua orang yang terkait
-- resto itu. Dua kebutuhan yang sangat berbeda terpaksa memakai jalur
-- yang sama: promo yang justru harus dibaca pelanggan, dan pengumuman
-- internal — jadwal shift, rapat, aturan baru dapur — yang tidak ada
-- urusannya dengan pelanggan dan sering tidak pantas dibaca mereka.
--
-- Tanpa pilihan, yang terjadi bisa ditebak: pengumuman internal berhenti
-- ditulis di sini dan pindah ke grup chat, lalu kotak masuknya kosong
-- dan tidak ada yang membukanya lagi.

begin;

alter table app_announcements
  add column if not exists audience text not null default 'all';

alter table app_announcements drop constraint if exists app_announcements_audience_check;
alter table app_announcements add constraint app_announcements_audience_check
  check (audience in ('employees', 'customers', 'all'));

-- Pengumuman lama tetap 'all' — itu memang perilakunya selama ini, dan
-- mengubahnya surut berarti menyembunyikan kabar yang sudah terlanjur
-- dibaca sebagian orang.

-- ─────────────────────────────────────────────────────────────────────
-- Notifikasinya ikut menyempit
-- ─────────────────────────────────────────────────────────────────────
--
-- Sasaran yang dipilih dititipkan ke antrean push, supaya Edge Function
-- tidak perlu membaca ulang barisnya. Nama audience-nya sendiri
-- ('all') sengaja tidak dipakai ulang untuk ini — itu jenis penerima
-- di antrean push, bukan sasaran pengumuman.
create or replace function queue_push_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into push_outbox (resto_id, event, payload) values (
    new.resto_id, 'announcement',
    jsonb_build_object(
      'audience', 'all',
      'target', coalesce(new.audience, 'all'),
      'title', new.title,
      'body', case
                when length(new.body) > 160
                  then left(new.body, 157) || '...'
                else new.body
              end
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_queue_push_announcement on app_announcements;
create trigger trg_queue_push_announcement
  after insert on app_announcements
  for each row execute function queue_push_announcement();

commit;


-- ═══════════════════════════════════════════════════════════
-- 61. kasir_journal_read.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — kasir boleh melihat jurnal dari catatan yang dia buat.
--
-- Aman dijalankan berulang kali.
--
-- Layar Saldo & Pengeluaran memang sudah dibuka untuk kasir: dia
-- mencatat pengeluaran dari petty cash dan mengajukan top up, dan
-- keduanya terlihat di sana. Yang tertinggal cuma satu — mengetuk salah
-- satu catatan untuk melihat jurnalnya.
--
-- Karena hak bacanya berhenti di admin dan finance, jawabannya selalu
-- kosong, dan layarnya menyimpulkan yang paling masuk akal dari data
-- kosong: "akun GL-nya belum dipetakan". Kasir lalu mencari kesalahan
-- pemetaan yang tidak pernah ada, sementara di layar Finance jurnal yang
-- sama muncul lengkap.
--
-- Tidak ada yang baru yang terbuka: barisnya menjelaskan catatan yang
-- sudah boleh dia lihat isinya. Menulis tetap tertutup untuk semua peran
-- — seluruh baris jurnal ditulis oleh pemicu, tidak pernah oleh
-- aplikasi.

begin;

drop policy if exists "gl_journal_entries: finance/admin read" on gl_journal_entries;
drop policy if exists "gl_journal_entries: staff read" on gl_journal_entries;
create policy "gl_journal_entries: staff read" on gl_journal_entries
  for select using (
    is_resto_employee(resto_id, array['admin', 'finance', 'kasir'])
  );

commit;


-- ═══════════════════════════════════════════════════════════
-- 62. cancel_order.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pelanggan boleh membatalkan pesanannya sendiri selama
-- pembayarannya belum diterima.
--
-- Jalankan SETELAH cash_payment_expiry.sql. Aman dijalankan berulang.
--
-- Sampai sekarang pesanan yang terlanjur dibuat cuma punya dua jalan
-- keluar: dibayar, atau menunggu tiga puluh menit sampai hangus
-- sendiri. Yang berubah pikiran satu menit setelah memesan tetap
-- terlihat di layar kasir dan di dapur selama setengah jam, dan yang
-- harus menjelaskannya adalah pramusaji.
--
-- Dibatalkan berbeda dari hangus, dan keduanya sengaja dibedakan:
-- 'expired' adalah pesanan yang ditinggalkan, 'cancelled' adalah
-- pesanan yang ditarik. Yang pertama pertanda pelanggan hilang, yang
-- kedua tidak — dan resto yang membaca angkanya nanti berhak tahu
-- bedanya.

begin;

alter table orders drop constraint if exists orders_payment_status_check;
alter table orders add constraint orders_payment_status_check
  check (payment_status in ('pending', 'paid', 'expired', 'cancelled'));

-- Lewat fungsi, bukan UPDATE langsung.
--
-- rls_hardening.sql menutup UPDATE pada orders untuk siapa pun selain
-- karyawan, dan itu benar: tanpa itu, siapa pun yang punya anon key
-- bisa menandai pesanan orang lain sudah dibayar. Pengaman
-- pembatalannya ditanam di dalam fungsi ini, bukan dengan membuka
-- kembali pintunya.
create or replace function cancel_my_order(
  p_order_id uuid,
  p_session_id text default null,
  p_email text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    return 'Pesanan tidak ditemukan.';
  end if;

  -- Miliknya sendiri. Pelanggan yang login dikenali dari emailnya, tamu
  -- dari session id yang tersimpan di HP-nya. Tanpa pemeriksaan ini,
  -- nomor pesanan yang terbaca dari struk orang lain sudah cukup untuk
  -- membatalkan pesanannya.
  if not (
    (p_email is not null and v_order.customer_label = p_email)
    or (p_session_id is not null and v_order.session_id = p_session_id)
  ) then
    return 'Pesanan ini bukan milikmu.';
  end if;

  if v_order.source <> 'customer' then
    return 'Pesanan yang diinput kasir dibatalkan lewat kasir.';
  end if;

  if v_order.payment_status = 'paid' then
    return 'Pesanan sudah dibayar. Hubungi kasir untuk pembatalan.';
  end if;

  if v_order.payment_status <> 'pending' then
    return 'Pesanan ini sudah tidak aktif.';
  end if;

  -- Dapur sudah mulai memasak berarti bahannya sudah terpakai.
  -- Membatalkannya sepihak dari HP memindahkan kerugiannya ke resto,
  -- dan yang menanggungnya bukan pihak yang membuat keputusannya.
  if v_order.kitchen_status <> 'waiting' then
    return 'Pesanan sudah mulai dimasak. Hubungi kasir kalau mau batal.';
  end if;

  update orders set payment_status = 'cancelled' where id = p_order_id;
  return null;
end;
$$;

grant execute on function cancel_my_order(uuid, text, text) to anon, authenticated;

commit;


-- ═══════════════════════════════════════════════════════════
-- 63. settled_at_counter.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — menandai pesanan mandiri yang uangnya diterima di meja
-- kasir, alih-alih menebaknya dari cara bayarnya.
--
-- Aman dijalankan berulang kali.
--
-- Riwayat Kasir berisi dua hal: pesanan yang diinput kasir, dan pesanan
-- mandiri pelanggan yang dilunasi di meja kasir. Yang kedua sampai
-- sekarang dikenali dengan menebak — "cara bayarnya tunai berarti
-- dibayar di kasir".
--
-- Tebakan itu benar selama tunai adalah satu-satunya cara melunasi di
-- meja kasir. Sejak layar Pending Payment bisa mengganti cara bayar ke
-- QRIS atau transfer, tebakannya jadi salah: begitu kasir memilih
-- QRIS, cara bayarnya berubah, tebakannya tidak lagi cocok, dan
-- pesanannya menghilang dari Riwayat Kasir — padahal uangnya baru saja
-- diterima orang yang sedang berdiri di sana.
--
-- Uang yang masuk laci tapi tidak muncul di riwayat adalah selisih yang
-- ditemukan saat tutup shift, oleh orang yang tidak tahu sebabnya.
--
-- Yang ditambahkan di sini adalah catatan tegas: siapa yang menerima,
-- dan kapan. Tidak ada lagi yang perlu ditebak.

begin;

alter table orders add column if not exists settled_by text;
alter table orders add column if not exists settled_at timestamptz;

-- Baris lama tidak diisi surut.
--
-- Yang lama semuanya dilunasi tunai — satu-satunya cara yang ada saat
-- itu — jadi tebakan lamanya masih benar untuk mereka, dan aplikasi
-- tetap memakainya sebagai cadangan. Menuliskan nama penerima yang
-- tidak pernah tercatat justru mengarang riwayat.

commit;


-- ═══════════════════════════════════════════════════════════
-- 64. discount_min_qty.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — diskon dengan syarat jumlah pembelian.
--
-- Jalankan SETELAH discounts.sql. Aman diulang.
--
-- "Beli 2 Mont Blanc diskon 30%" adalah bentuk promo yang paling sering
-- dipakai resto, dan sampai sekarang tidak bisa dinyatakan: aturan
-- diskon hanya menyebut menunya, tidak berapa banyak. Akibatnya promo
-- yang dimaksudkan untuk mendorong pembelian kedua ikut terpakai oleh
-- yang membeli satu — persis kebalikan dari maksudnya.
--
-- Bawaannya 1, jadi seluruh diskon yang sudah ada berlaku persis
-- seperti sebelumnya.

begin;

alter table discounts add column if not exists min_qty integer not null default 1;

-- Nol atau negatif tidak punya arti; yang dimaksud "tanpa syarat
-- jumlah" adalah 1.
alter table discounts drop constraint if exists discounts_min_qty_check;
alter table discounts add constraint discounts_min_qty_check
  check (min_qty >= 1);

commit;


-- ═══════════════════════════════════════════════════════════
-- 65. discount_product_rules.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — syarat jumlah menempel di tiap menu, bukan di promonya.
--
-- Jalankan SETELAH discounts.sql dan discount_min_qty.sql. Aman diulang.
--
-- min_qty menyimpan satu angka untuk seluruh promo, dan itu terlalu
-- longgar untuk bundling: promo "Nasi Goreng + Es Teh, beli 2" berlaku
-- untuk keranjang berisi dua Nasi Goreng dan segelas kopi. Paket yang
-- dijanjikan spanduknya tidak pernah benar-benar dibeli, tapi restonya
-- tetap membayar potongannya.
--
-- Sekarang tiap menu membawa syaratnya sendiri, dan seluruhnya harus
-- terpenuhi:
--
--   [{"product_id": "abc", "qty": 2, "mode": "exactly"},
--    {"product_id": "def", "qty": 1, "mode": "at_least"}]
--
-- 'exactly' untuk paket yang isinya sudah pasti — tiga ayam bukan lagi
-- paket "2 ayam + 1 nasi", dan kalau tetap diberi potongan, harga
-- paketnya tidak berarti apa-apa.

begin;

alter table discounts add column if not exists product_rules jsonb not null default '[]'::jsonb;

-- Promo yang sudah ada dipindahkan apa adanya: tiap menunya memakai
-- min_qty yang berlaku untuknya selama ini. Yang belum punya aturan
-- saja — supaya menjalankan ulang berkas ini tidak menimpa aturan yang
-- sudah disunting Admin.
update discounts
set product_rules = (
  select jsonb_agg(jsonb_build_object(
    'product_id', id,
    'qty', greatest(coalesce(min_qty, 1), 1),
    'mode', 'at_least'
  ))
  from jsonb_array_elements_text(product_ids) as t(id)
)
where basis = 'products'
  and jsonb_array_length(product_ids) > 0
  and jsonb_array_length(product_rules) = 0;

-- min_qty sengaja TIDAK dihapus. Aplikasi versi 1.45.3 masih
-- membacanya, dan kolom yang hilang membuat layar diskonnya gagal
-- memuat — bukan menampilkan promo tanpa syarat jumlah, tapi tidak
-- menampilkan apa-apa. Dibiarkan sampai versi itu tidak lagi terpasang.

commit;


-- ═══════════════════════════════════════════════════════════
-- 66. billing.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — langganan bulanan resto.
--
-- Jalankan SETELAH schema.sql, rls_hardening.sql, dan super_admin.sql.
-- Aman dijalankan berulang. Butuh pg_cron.
--
-- Resto membayar biaya langganan bulanan. Harganya dan tanggal
-- tagihannya ditentukan per resto oleh Super Admin — bukan satu angka
-- untuk semuanya, karena resto yang baru buka dan jaringan sepuluh
-- cabang tidak pernah dinilai sama.
--
-- Tiga hari sebelum jatuh tempo, restonya diingatkan. Lewat satu hari
-- dari jatuh tempo dan tagihannya belum lunas, restonya terkunci.
--
-- ── Kenapa penguncian ditegakkan di sini, bukan di aplikasi ──────────
--
-- Aplikasi ini berbicara langsung ke Postgres tanpa server perantara.
-- Layar yang terkunci hanyalah layar: siapa pun yang memegang kunci
-- publik proyek bisa memanggil API-nya langsung dan tetap membuat
-- pesanan. Karena itu penguncian dipasang sebagai kebijakan RLS
-- restrictive — yang tidak bisa dilewati lewat jalan mana pun, termasuk
-- jalan yang belum terpikirkan hari ini.
--
-- ── Yang sengaja TIDAK dikunci ───────────────────────────────────────
--
-- Membaca tagihan sendiri dan mengunggah bukti bayar tetap terbuka.
-- Mengunci itu berarti mengunci satu-satunya jalan keluar dari
-- penguncian — resto yang sudah membayar tidak punya cara memberi tahu
-- siapa pun.

begin;

create extension if not exists pg_cron with schema extensions;

-- ─────────────────────────────────────────────────────────────────────
-- Setelan langganan per resto
-- ─────────────────────────────────────────────────────────────────────

create table if not exists resto_billing (
  resto_id text primary key references restaurants (id) on delete cascade,

  -- Rupiah per bulan. Nol berarti gratis — dipakai untuk masa percobaan
  -- dan resto milik sendiri, dan resto bernilai nol tidak pernah
  -- terkunci.
  monthly_price bigint not null default 0 check (monthly_price >= 0),

  -- Tanggal jatuh tempo tiap bulan. Dibatasi 1–28 supaya artinya sama
  -- di bulan mana pun: "tanggal 31" tidak ada di bulan Februari, dan
  -- menggesernya diam-diam ke 28 membuat tagihan datang di hari yang
  -- tidak dijanjikan.
  billing_day smallint not null default 1
    check (billing_day between 1 and 28),

  -- Tenggang sesudah jatuh tempo sebelum restonya terkunci.
  grace_days smallint not null default 1 check (grace_days >= 0),

  -- Dimatikan berarti resto ini tidak pernah ditagih dan tidak pernah
  -- terkunci, apa pun isi tabel tagihannya.
  active boolean not null default true,

  started_on date not null default current_date,
  note text,
  updated_at timestamptz not null default now()
);

-- Resto baru langsung punya barisnya, gratis, sampai Super Admin
-- menetapkan harganya. Bawaan yang menagih sebelum ada yang menyepakati
-- harganya akan mengunci resto yang belum pernah diberi tahu.
create or replace function seed_resto_billing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into resto_billing (resto_id, monthly_price, billing_day)
  values (new.id, 0, 1)
  on conflict (resto_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_resto_billing on restaurants;
create trigger trg_seed_resto_billing
  after insert on restaurants
  for each row execute function seed_resto_billing();

insert into resto_billing (resto_id, monthly_price, billing_day)
select r.id, 0, 1 from restaurants r
on conflict (resto_id) do nothing;

-- ─────────────────────────────────────────────────────────────────────
-- Tagihan
-- ─────────────────────────────────────────────────────────────────────

create table if not exists billing_invoices (
  id text primary key,
  resto_id text not null references restaurants (id) on delete cascade,

  period_start date not null,
  period_end date not null,
  due_date date not null,
  amount bigint not null check (amount >= 0),

  -- unpaid  → belum dibayar
  -- review  → resto sudah mengunggah bukti, menunggu diperiksa MerchantPOS
  -- paid    → diterima
  -- waived  → dibebaskan (masa percobaan, kompensasi gangguan)
  status text not null default 'unpaid'
    check (status in ('unpaid', 'review', 'paid', 'waived')),

  proof_base64 text,
  paid_note text,
  submitted_at timestamptz,

  confirmed_by text,
  confirmed_at timestamptz,
  reject_reason text,

  created_at timestamptz not null default now(),

  -- Satu tagihan per resto per periode. Tanpa ini, pembangkit yang
  -- kebetulan berjalan dua kali menagih dua kali — dan yang menemukannya
  -- adalah restonya, bukan kita.
  constraint billing_invoices_period_unique unique (resto_id, period_start)
);

create index if not exists idx_billing_invoices_resto
  on billing_invoices (resto_id, due_date desc);
create index if not exists idx_billing_invoices_open
  on billing_invoices (due_date) where status in ('unpaid', 'review');

-- ─────────────────────────────────────────────────────────────────────
-- Penerbitan tagihan
-- ─────────────────────────────────────────────────────────────────────

-- Jatuh tempo berikutnya bagi sebuah tanggal.
create or replace function _billing_due_on(p_day smallint, p_from date)
returns date
language sql
immutable
as $$
  select case
    when extract(day from p_from) <= p_day
      then make_date(extract(year from p_from)::int,
                     extract(month from p_from)::int, p_day)
    else (make_date(extract(year from p_from)::int,
                    extract(month from p_from)::int, p_day)
          + interval '1 month')::date
  end;
$$;

-- Diterbitkan tujuh hari sebelum jatuh tempo, supaya pengingat H-3
-- punya tagihan yang bisa ditunjuk — pengingat membayar tanpa nominal
-- dan nomor tagihan bukan pengingat, cuma kabar cemas.
create or replace function generate_billing_invoices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  b record;
  v_due date;
begin
  for b in
    select * from resto_billing
    where active = true and monthly_price > 0
  loop
    v_due := _billing_due_on(b.billing_day, current_date);
    continue when v_due - current_date > 7;

    insert into billing_invoices (
      id, resto_id, period_start, period_end, due_date, amount
    ) values (
      'INV-' || upper(substr(md5(b.resto_id || v_due::text), 1, 10)),
      b.resto_id,
      (v_due - interval '1 month')::date,
      (v_due - interval '1 day')::date,
      v_due,
      b.monthly_price
    )
    on conflict (resto_id, period_start) do nothing;

    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

select cron.unschedule('generate-billing-invoices')
where exists (
  select 1 from cron.job where jobname = 'generate-billing-invoices'
);

-- Sekali sehari, lewat tengah malam WIB (17:00 UTC).
select cron.schedule(
  'generate-billing-invoices',
  '5 17 * * *',
  $$select generate_billing_invoices();$$
);

-- ─────────────────────────────────────────────────────────────────────
-- Keadaan langganan sebuah resto
-- ─────────────────────────────────────────────────────────────────────

-- Satu sumber kebenaran, dipakai RLS maupun layar aplikasi. Dua
-- perhitungan terpisah akan berpisah, dan yang terlihat adalah layar
-- yang mengaku aman sementara database menolak menyimpan apa pun.
-- Dibuang dulu, bukan langsung `create or replace`.
--
-- `billing_due_day.sql` menambah kolom `next_due_date` ke kembaliannya,
-- dan Postgres menolak `create or replace` yang mengubah tipe
-- kembalian. Di basis data yang sudah menjalankan berkas itu, berkas
-- ini akan gagal dengan 42P13 — dan berkas yang tidak aman dijalankan
-- ulang berhenti jadi berkas yang bisa dipercaya (lihat TSD §11.2).
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
  active boolean
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
    -- Terkunci hanya kalau tagihannya benar-benar lewat tenggang DAN
    -- belum diserahkan buktinya. Resto yang sudah mengunggah bukti
    -- diberi kesempatan sampai diperiksa — mengunci orang yang sudah
    -- membayar adalah kesalahan yang paling mahal di seluruh fitur ini.
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
    coalesce(s.active, false)
  from setelan s
  left join tertunggak t on true;
$$;

-- Bentuk ringkas untuk RLS. Super Admin tidak pernah terkunci: dialah
-- yang membuka kuncinya.
create or replace function is_resto_billing_locked(p_resto_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when is_super_admin() then false
    else coalesce((select locked from resto_billing_state(p_resto_id)), false)
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Penguncian
-- ─────────────────────────────────────────────────────────────────────
--
-- Kebijakan RESTRICTIVE, bukan permissive. Kebijakan permissive
-- digabung dengan OR — menambah satu lagi justru MELONGGARKAN aksesnya.
-- Yang restrictive digabung dengan AND, dan itulah satu-satunya bentuk
-- yang benar-benar menutup pintu tanpa menyentuh kebijakan yang sudah
-- ada.

drop policy if exists "orders: billing lock" on orders;
create policy "orders: billing lock" on orders
  as restrictive for insert
  with check (not is_resto_billing_locked(resto_id));

drop policy if exists "orders: billing lock update" on orders;
create policy "orders: billing lock update" on orders
  as restrictive for update
  using (not is_resto_billing_locked(resto_id));

-- Katalog ikut dibekukan. Tanpa ini, resto terkunci masih bisa
-- mengubah harga dan menu — pekerjaan yang hasilnya tidak bisa dijual.
drop policy if exists "products: billing lock" on products;
create policy "products: billing lock" on products
  as restrictive for all
  using (not is_resto_billing_locked(resto_id))
  with check (not is_resto_billing_locked(resto_id));

-- ─────────────────────────────────────────────────────────────────────
-- RLS tabel langganan
-- ─────────────────────────────────────────────────────────────────────

alter table resto_billing enable row level security;
alter table billing_invoices enable row level security;

-- Resto boleh melihat setelannya sendiri — orang berhak tahu berapa
-- yang ditagihkan kepadanya dan kapan. Yang mengubah hanya Super Admin.
drop policy if exists "resto_billing: read" on resto_billing;
create policy "resto_billing: read" on resto_billing
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

drop policy if exists "resto_billing: super admin write" on resto_billing;
create policy "resto_billing: super admin write" on resto_billing
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "billing_invoices: read" on billing_invoices;
create policy "billing_invoices: read" on billing_invoices
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance', 'kasir', 'chef'])
  );

drop policy if exists "billing_invoices: super admin write" on billing_invoices;
create policy "billing_invoices: super admin write" on billing_invoices
  for all using (is_super_admin()) with check (is_super_admin());

-- Resto mengunggah bukti bayar lewat RPC, bukan UPDATE langsung —
-- kalau langsung, tidak ada yang mencegahnya menulis status 'paid'
-- sendiri.
create or replace function submit_billing_payment(
  p_invoice_id text,
  p_proof_base64 text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resto text;
begin
  select resto_id into v_resto from billing_invoices where id = p_invoice_id;
  if v_resto is null then
    raise exception 'Tagihan tidak ditemukan';
  end if;

  if not (is_super_admin()
          or is_resto_employee(v_resto, array['owner', 'admin', 'finance'])) then
    raise exception 'Tidak berwenang atas tagihan ini';
  end if;

  update billing_invoices
  set status = 'review',
      proof_base64 = coalesce(p_proof_base64, proof_base64),
      paid_note = p_note,
      submitted_at = now(),
      reject_reason = null
  where id = p_invoice_id
    and status in ('unpaid', 'review');
end;
$$;

-- Hanya MerchantPOS yang menyatakan lunas. Itu satu-satunya cara membuka
-- kunci, jadi wewenangnya tidak dibagi.
create or replace function review_billing_payment(
  p_invoice_id text,
  p_accept boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat memutuskan';
  end if;

  update billing_invoices
  set status = case when p_accept then 'paid' else 'unpaid' end,
      confirmed_by = auth.jwt() ->> 'email',
      confirmed_at = now(),
      reject_reason = case when p_accept then null else p_reason end
  where id = p_invoice_id;
end;
$$;

commit;


-- ═══════════════════════════════════════════════════════════
-- 67. billing_va.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — tagihan langganan dibayar lewat Virtual Account Xendit.
--
-- Jalankan SETELAH billing.sql. Aman diulang.
--
-- Sebelumnya resto mengunggah foto bukti transfer dan menunggu
-- diperiksa manusia. Itu bekerja, tapi menaruh jeda berjam-jam — kadang
-- semalam — antara uang yang sudah dikirim dan kunci yang dibuka. Yang
-- menanggung jeda itu adalah resto yang tidak bisa berjualan.
--
-- Virtual Account menutup jeda itu: nomornya tetap, nominalnya terkunci,
-- dan begitu ditransfer, Xendit mengabari kita dalam hitungan detik.
--
-- ── Perbedaan penting dari QRIS pesanan ──────────────────────────────
--
-- QRIS pesanan dibuat atas nama sub-akun restonya, supaya dananya cair
-- ke rekening resto itu. VA langganan justru kebalikannya: dibuat atas
-- nama akun platform, karena inilah satu-satunya aliran uang yang
-- tujuannya memang rekening MerchantPOS.
--
-- Salah memasang `for-user-id` di sini berarti resto membayar tagihan
-- langganan ke rekeningnya sendiri — dan tidak ada satu pun galat yang
-- muncul saat itu terjadi.

begin;

alter table billing_invoices add column if not exists va_bank text;
alter table billing_invoices add column if not exists va_number text;
alter table billing_invoices add column if not exists va_id text;
alter table billing_invoices add column if not exists va_expires_at timestamptz;
alter table billing_invoices add column if not exists xendit_payment_id text;

-- Bagaimana tagihannya akhirnya lunas. Dibedakan karena keduanya punya
-- tingkat kepercayaan yang berbeda: 'xendit_va' berarti uangnya benar
-- benar masuk dan terkonfirmasi mesin, 'manual' berarti ada orang yang
-- memutuskan berdasarkan foto.
alter table billing_invoices add column if not exists paid_via text;
alter table billing_invoices drop constraint if exists billing_invoices_paid_via_check;
alter table billing_invoices add constraint billing_invoices_paid_via_check
  check (paid_via is null or paid_via in ('xendit_va', 'manual', 'waived'));

create index if not exists idx_billing_invoices_va
  on billing_invoices (va_id) where va_id is not null;

-- Dipakai webhook untuk menemukan tagihannya dari nomor VA-nya.
create index if not exists idx_billing_invoices_va_number
  on billing_invoices (va_number) where va_number is not null;

-- ─────────────────────────────────────────────────────────────────────
-- Bank yang tersedia
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan sebagai batasan, bukan daftar bebas: kode bank yang salah
-- ketik baru ketahuan saat Xendit menolaknya, dan yang melihat
-- penolakan itu adalah resto yang sedang mencoba membayar.
alter table billing_invoices drop constraint if exists billing_invoices_va_bank_check;
alter table billing_invoices add constraint billing_invoices_va_bank_check
  check (va_bank is null or va_bank in
    ('BCA', 'BNI', 'BRI', 'MANDIRI', 'PERMATA', 'BSI', 'CIMB'));

-- ─────────────────────────────────────────────────────────────────────
-- Pelunasan oleh mesin
-- ─────────────────────────────────────────────────────────────────────
--
-- Dipanggil fungsi edge pemroses callback Xendit, memakai service role.
-- Ditulis sebagai fungsi, bukan UPDATE lepas di dalam fungsi edge,
-- supaya syaratnya — nominal cukup, tagihan belum lunas — hidup di satu
-- tempat yang sama dengan aturan lainnya.
-- Dibuang dulu, bukan sekadar `create or replace`.
--
-- Versi pertama fungsi ini mengembalikan boolean; sekarang text.
-- Postgres menolak `create or replace` yang mengubah tipe kembalian —
-- dan penolakannya baru terlihat di database yang sudah pernah
-- menjalankan versi lama, bukan di database kosong tempat berkas ini
-- biasanya diuji:
--
--   ERROR: cannot change return type of existing function
--
-- Tanda tangannya ditulis lengkap supaya yang dibuang persis fungsi
-- ini, bukan fungsi bernama sama dengan argumen berbeda.
drop function if exists settle_billing_va(text, bigint, text);

create or replace function settle_billing_va(
  p_invoice_id text,
  p_amount bigint,
  p_payment_id text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv billing_invoices;
begin
  select * into v_inv from billing_invoices where id = p_invoice_id;

  -- Empat jawaban berbeda, bukan satu "gagal".
  --
  -- Ketiga kegagalannya sama-sama berarti "tidak dilunasi", tapi
  -- artinya jauh berbeda saat ditelusuri: tagihan yang tidak ditemukan
  -- menunjuk ke nomor yang salah, kurang bayar menunjuk ke uang yang
  -- benar-benar masuk tapi kurang. Menyatukan keduanya di bawah satu
  -- pesan membuat penelusuran uang berangkat ke arah yang salah — dan
  -- ini catatan yang dibaca justru saat ada uang yang tidak jelas
  -- rimbanya.
  if v_inv.id is null then
    return 'not_found';
  end if;

  -- Xendit mengulang callback-nya sampai dijawab 200, dan percobaan
  -- kedua tidak boleh menimpa catatan siapa yang melunasi.
  if v_inv.status in ('paid', 'waived') then
    return 'already_paid';
  end if;

  -- VA-nya dibuat tertutup di nominal tagihan, jadi ini seharusnya
  -- tidak pernah terjadi — dan justru karena itu, kalau terjadi, ia
  -- layak berhenti di sini alih-alih diam-diam membuka kunci.
  if p_amount < v_inv.amount then
    return 'underpaid';
  end if;

  update billing_invoices
  set status = 'paid',
      paid_via = 'xendit_va',
      xendit_payment_id = p_payment_id,
      confirmed_by = 'xendit',
      confirmed_at = now(),
      reject_reason = null
  where id = p_invoice_id;

  return 'paid';
end;
$$;

-- Pelunasan manual ikut menandai jalurnya, supaya laporan bisa
-- membedakan mana yang terkonfirmasi mesin dan mana yang keputusan
-- orang.
create or replace function review_billing_payment(
  p_invoice_id text,
  p_accept boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat memutuskan';
  end if;

  update billing_invoices
  set status = case when p_accept then 'paid' else 'unpaid' end,
      paid_via = case when p_accept then 'manual' else null end,
      confirmed_by = auth.jwt() ->> 'email',
      confirmed_at = now(),
      reject_reason = case when p_accept then null else p_reason end
  where id = p_invoice_id;
end;
$$;

commit;


-- ═══════════════════════════════════════════════════════════
-- 68. platform_finance.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — keuangan MerchantPOS sendiri, terpisah dari keuangan resto.
--
-- Jalankan SETELAH billing.sql dan billing_va.sql. Aman diulang.
--
-- Sampai sekarang seluruh pembukuan di aplikasi ini milik resto: uang
-- yang masuk ke mereka, pengeluaran mereka, kas kecil mereka. Pendapatan
-- MerchantPOS sendiri — biaya langganan yang dibayarkan resto — tidak
-- tercatat di mana pun kecuali sebagai baris tagihan berstatus lunas.
--
-- ── Kenapa memakai "resto" sendiri, bukan tabel baru ─────────────────
--
-- Seluruh mesin pembukuan yang sudah ada — bagan akun, jurnal,
-- pengeluaran, kas kecil, berikut pemicu dan kebijakannya — bekerja per
-- resto. Menyalinnya jadi tabel platform_* berarti dua salinan aturan
-- yang sama, dan dua salinan akan berpisah: perbaikan yang dipasang di
-- satu sisi tidak pernah ikut ke sisi lain, dan yang menemukannya
-- adalah selisih angka berbulan-bulan kemudian.
--
-- Jadi MerchantPOS diberi satu barisnya sendiri di tabel restaurants,
-- ditandai is_platform. Seluruh layar keuangan yang sudah ada langsung
-- bekerja untuknya.
--
-- Konsekuensinya harus dijaga: baris itu tidak boleh muncul di daftar
-- resto mana pun yang dilihat pelanggan atau karyawan.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Penyewa platform
-- ─────────────────────────────────────────────────────────────────────

alter table restaurants add column if not exists is_platform boolean not null default false;

-- active = false supaya ia lolos dari setiap saringan yang sudah ada:
-- daftar resto pelanggan, pemilih resto, dan pencarian semuanya sudah
-- menyaring yang tidak aktif. Penandanya sendiri (is_platform) dipakai
-- untuk menyaring di tempat yang tidak melihat `active` — daftar resto
-- di Super Admin, dan daftar langganan.
insert into restaurants (id, name, address, active, is_platform)
values ('merchantpos', 'MerchantPOS', 'Pembukuan internal MerchantPOS', false, true)
on conflict (id) do update set is_platform = true;

-- Ia bukan pelanggan dirinya sendiri.
update resto_billing set active = false, monthly_price = 0
where resto_id = 'merchantpos';

-- ─────────────────────────────────────────────────────────────────────
-- Bagan akun MerchantPOS
-- ─────────────────────────────────────────────────────────────────────
--
-- Nomor 11xxxxx dipakai supaya berbeda jelas dari 19xxxxx milik resto.
-- Selisih golongan itu yang membuat satu baris jurnal bisa dikenali
-- pemiliknya hanya dari nomornya, tanpa menelusuri restonya lebih dulu.

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values
  ('merchantpos', 'subscription',          '1100001', 'GL Pendapatan Langganan'),
  ('merchantpos', 'subscription_discount', '1100002', 'GL Diskon Langganan'),
  ('merchantpos', 'cash',                  '1100010', 'GL Kas Tunai MerchantPOS'),
  ('merchantpos', 'transfer',              '1100011', 'GL Rekening MerchantPOS'),
  ('merchantpos', 'qris',                  '1100012', 'GL Penerimaan QRIS MerchantPOS'),
  ('merchantpos', 'income_aggregate',      '1100020', 'GL Pendapatan MerchantPOS'),
  ('merchantpos', 'petty_cash',            '1100030', 'GL Petty Cash MerchantPOS'),
  ('merchantpos', 'total_balance',         '1100040', 'GL Total Saldo MerchantPOS'),
  ('merchantpos', 'suspense',              '1100050', 'GL Suspense MerchantPOS'),
  ('merchantpos', 'suspense_petty',        '1100051', 'GL Suspense Petty MerchantPOS'),
  ('merchantpos', 'gateway_fee',           '1100060', 'GL Biaya Gateway MerchantPOS'),
  ('merchantpos', 'ppn',                   '1100070', 'GL PPN MerchantPOS'),
  ('merchantpos', 'service',               '1100071', 'GL Biaya Service MerchantPOS'),
  ('merchantpos', 'discount',              '1100072', 'GL Diskon Lain MerchantPOS')
on conflict (resto_id, payment_method) do nothing;

insert into expense_gl_accounts (resto_id, gl_code, gl_name)
select 'merchantpos', d.gl_code, d.gl_name
from _default_expense_gl_accounts() d
where not exists (
  select 1 from expense_gl_accounts e
  where e.resto_id = 'merchantpos' and e.gl_code = d.gl_code
);

-- ─────────────────────────────────────────────────────────────────────
-- Diskon langganan
-- ─────────────────────────────────────────────────────────────────────
--
-- Potongan harga langganan untuk resto tertentu — masa percobaan,
-- promo pembukaan, kompensasi gangguan. Dipilih per resto, bukan
-- berlaku untuk semuanya: yang sering terjadi justru satu-dua resto
-- yang perlu diperlakukan berbeda.

create table if not exists billing_discounts (
  id text primary key,
  name text not null,

  kind text not null default 'percent' check (kind in ('percent', 'amount')),
  value bigint not null check (value > 0),

  -- Resto yang dikenai. Kosong berarti tidak mengenai siapa pun —
  -- diskon tanpa sasaran bukan diskon, itu setengah jadi.
  resto_ids jsonb not null default '[]'::jsonb,

  starts_on date,
  ends_on date,
  active boolean not null default true,

  created_by text,
  created_at timestamptz not null default now(),

  constraint billing_discounts_period_check
    check (ends_on is null or starts_on is null or ends_on > starts_on),
  constraint billing_discounts_percent_check
    check (kind <> 'percent' or value between 1 and 100)
);

alter table billing_discounts enable row level security;

drop policy if exists "billing_discounts: super admin" on billing_discounts;
create policy "billing_discounts: super admin" on billing_discounts
  for all using (is_super_admin()) with check (is_super_admin());

-- Resto boleh melihat diskon yang mengenai dirinya — potongan yang
-- muncul di tagihan tanpa nama dan alasan terbaca sebagai salah hitung.
drop policy if exists "billing_discounts: resto read" on billing_discounts;
create policy "billing_discounts: resto read" on billing_discounts
  for select using (
    is_super_admin()
    or exists (
      select 1 from jsonb_array_elements_text(resto_ids) t(rid)
      where is_resto_employee(t.rid, array['owner', 'admin', 'finance'])
    )
  );

alter table billing_invoices add column if not exists discount_id text;
alter table billing_invoices add column if not exists discount_name text;
alter table billing_invoices add column if not exists discount_amount bigint not null default 0;
alter table billing_invoices add column if not exists gross_amount bigint;

-- Potongan terbaik untuk sebuah resto hari ini.
--
-- Satu diskon, bukan ditumpuk — alasannya sama dengan diskon menu di
-- resto: dua potongan yang kebetulan berlaku bersamaan bisa melebihi
-- harga langganannya sendiri.
create or replace function _best_billing_discount(p_resto_id text, p_price bigint)
returns table (id text, name text, amount bigint)
language sql
stable
as $$
  select d.id, d.name,
    least(
      case when d.kind = 'percent' then p_price * d.value / 100 else d.value end,
      p_price
    )::bigint as amount
  from billing_discounts d
  where d.active
    and (d.starts_on is null or d.starts_on <= current_date)
    and (d.ends_on is null or d.ends_on >= current_date)
    and d.resto_ids ? p_resto_id
  order by amount desc
  limit 1;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Penerbitan tagihan berikut diskonnya
-- ─────────────────────────────────────────────────────────────────────

create or replace function generate_billing_invoices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  b record;
  v_due date;
  v_disc record;
  v_amount bigint;
begin
  for b in
    select * from resto_billing
    where active = true and monthly_price > 0
  loop
    v_due := _billing_due_on(b.billing_day, current_date);
    continue when v_due - current_date > 7;

    select * into v_disc from _best_billing_discount(b.resto_id, b.monthly_price);
    v_amount := b.monthly_price - coalesce(v_disc.amount, 0);

    insert into billing_invoices (
      id, resto_id, period_start, period_end, due_date,
      amount, gross_amount, discount_id, discount_name, discount_amount
    ) values (
      'INV-' || upper(substr(md5(b.resto_id || v_due::text), 1, 10)),
      b.resto_id,
      (v_due - interval '1 month')::date,
      (v_due - interval '1 day')::date,
      v_due,
      v_amount,
      b.monthly_price,
      v_disc.id,
      v_disc.name,
      coalesce(v_disc.amount, 0)
    )
    on conflict (resto_id, period_start) do nothing;

    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Jurnal pendapatan langganan
-- ─────────────────────────────────────────────────────────────────────
--
-- Dicatat di buku MerchantPOS, bukan di buku restonya. Bagi resto, biaya
-- langganan adalah pengeluaran mereka — dan mereka mencatatnya sendiri
-- lewat menu Pengeluaran kalau mau. Menuliskannya ke jurnal mereka dari
-- sini berarti kami menulis di pembukuan orang lain.

alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

create or replace function log_billing_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
  v_resto text;
begin
  if new.status <> 'paid' then
    return new;
  end if;

  -- Sudah pernah dicatat? Tagihan bisa berpindah status lebih dari
  -- sekali — ditolak lalu diterima lagi — dan tiap perpindahan tidak
  -- boleh menambah pendapatan sekali lagi.
  if exists (
    select 1 from gl_journal_entries
    where reference_type = 'billing' and reference_id = new.id
  ) then
    return new;
  end if;

  select name into v_resto from restaurants where id = new.resto_id;

  -- Pendapatan: kredit, karena uang masuk.
  select * into v_gl from _gl_account_for('merchantpos', 'subscription');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      'merchantpos',
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'billing', new.id, new.amount, 'credit',
      'Langganan ' || coalesce(v_resto, new.resto_id) || ' — ' || new.id
    );
  end if;

  -- Diskon: debit, karena pendapatan yang tidak jadi diterima.
  if coalesce(new.discount_amount, 0) > 0 then
    select * into v_gl from _gl_account_for('merchantpos', 'subscription_discount');
    if v_gl.gl_code is not null and v_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        'merchantpos',
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl.gl_code, v_gl.gl_name,
        'billing_discount', new.id, new.discount_amount, 'debit',
        coalesce(nullif(new.discount_name, ''), 'Diskon langganan')
          || ' — ' || coalesce(v_resto, new.resto_id)
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_billing_journal on billing_invoices;
create trigger trg_log_billing_journal
  after update of status on billing_invoices
  for each row execute function log_billing_journal();

drop trigger if exists trg_log_billing_journal_insert on billing_invoices;
create trigger trg_log_billing_journal_insert
  after insert on billing_invoices
  for each row execute function log_billing_journal();

-- ─────────────────────────────────────────────────────────────────────
-- Akses Super Admin ke seluruh pembukuan
-- ─────────────────────────────────────────────────────────────────────
--
-- Ditambahkan sebagai kebijakan BARU, bukan dengan menulis ulang yang
-- sudah ada. Kebijakan permissive digabung dengan OR, jadi menambah satu
-- cukup untuk memberi akses — dan menulis ulang yang lama berarti
-- menyalin ulang syaratnya, yang suatu hari akan tersalin tidak lengkap.

drop policy if exists "gl_accounts: super admin" on gl_accounts;
create policy "gl_accounts: super admin" on gl_accounts
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "expense_gl_accounts: super admin" on expense_gl_accounts;
create policy "expense_gl_accounts: super admin" on expense_gl_accounts
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "expenses: super admin" on expenses;
create policy "expenses: super admin" on expenses
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "petty_cash_entries: super admin" on petty_cash_entries;
create policy "petty_cash_entries: super admin" on petty_cash_entries
  for all using (is_super_admin()) with check (is_super_admin());

-- Jurnal: BACA SAJA, lintas seluruh resto.
--
-- Sengaja tanpa insert/update/delete. Tiap baris jurnal ditulis pemicu
-- yang mengikuti kejadian nyata di orders/expenses; tangan yang bisa
-- menulis langsung ke sini adalah tangan yang bisa membuat pembukuan
-- berbeda dari yang benar-benar terjadi — dan itu berlaku untuk Super
-- Admin persis seperti untuk yang lain.
drop policy if exists "gl_journal_entries: super admin read" on gl_journal_entries;
create policy "gl_journal_entries: super admin read" on gl_journal_entries
  for select using (is_super_admin());

-- Pesanan dan setoran ikut terbaca, supaya layar Pemasukan dan rincian
-- jurnal lintas resto punya isinya.
drop policy if exists "orders: super admin read" on orders;
create policy "orders: super admin read" on orders
  for select using (is_super_admin());

drop policy if exists "cash_deposits: super admin read" on cash_deposits;
create policy "cash_deposits: super admin read" on cash_deposits
  for select using (is_super_admin());

commit;


-- ═══════════════════════════════════════════════════════════
-- 69. resto_soft_delete.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — menghapus resto tanpa membuang datanya.
--
-- Jalankan SETELAH platform_finance.sql. Aman diulang.
--
-- `delete from restaurants` akan bekerja — dan membawa serta seluruh
-- isinya, karena hampir semua tabel menggantung padanya dengan
-- `on delete cascade`. Termasuk jurnal GL-nya.
--
-- Itu bukan yang dimaksud orang saat menghapus resto dari daftar.
-- Restonya berhenti berjualan, tapi pembukuan tahun berjalan masih
-- harus bisa dibaca, tagihan langganannya masih harus bisa ditelusuri,
-- dan kalau ternyata salah pencet — resto yang mirip namanya — harus
-- ada jalan kembali.
--
-- Jadi yang dihapus cuma penandanya.

begin;

alter table restaurants add column if not exists is_deleted boolean not null default false;
alter table restaurants add column if not exists deleted_at timestamptz;
alter table restaurants add column if not exists deleted_by text;

create index if not exists idx_restaurants_hidup
  on restaurants (id) where is_deleted = false;

-- ─────────────────────────────────────────────────────────────────────
-- Yang terhapus benar-benar berhenti
-- ─────────────────────────────────────────────────────────────────────
--
-- Menyembunyikannya dari daftar saja tidak cukup. Pelanggan yang
-- terlanjur menyimpan tautan mejanya, atau memindai QR meja yang masih
-- tertempel, akan tetap sampai ke menunya — dan memesan dari resto yang
-- sudah tidak melayani siapa pun.
--
-- RESTRICTIVE, sama alasannya dengan penguncian tagihan: kebijakan
-- permissive digabung dengan OR, jadi menambah satu justru
-- melonggarkan. Yang restrictive digabung dengan AND.

create or replace function is_resto_deleted(p_resto_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select is_deleted from restaurants where id = p_resto_id), false);
$$;

drop policy if exists "orders: deleted resto" on orders;
create policy "orders: deleted resto" on orders
  as restrictive for insert
  with check (not is_resto_deleted(resto_id));

drop policy if exists "products: deleted resto" on products;
create policy "products: deleted resto" on products
  as restrictive for all
  using (not is_resto_deleted(resto_id))
  with check (not is_resto_deleted(resto_id));

-- ─────────────────────────────────────────────────────────────────────
-- Berhenti ditagih
-- ─────────────────────────────────────────────────────────────────────
--
-- Resto yang sudah dihapus tidak boleh menerima tagihan bulan depan.
-- Tagihan yang sudah terbit dibiarkan apa adanya — itu utang yang
-- benar-benar pernah ada, dan menghapusnya berarti menghapus catatan
-- pendapatan yang mungkin sudah masuk.

create or replace function generate_billing_invoices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  b record;
  v_due date;
  v_disc record;
  v_amount bigint;
begin
  for b in
    select rb.* from resto_billing rb
    join restaurants r on r.id = rb.resto_id
    where rb.active = true
      and rb.monthly_price > 0
      and r.is_deleted = false
  loop
    v_due := _billing_due_on(b.billing_day, current_date);
    continue when v_due - current_date > 7;

    select * into v_disc from _best_billing_discount(b.resto_id, b.monthly_price);
    v_amount := b.monthly_price - coalesce(v_disc.amount, 0);

    insert into billing_invoices (
      id, resto_id, period_start, period_end, due_date,
      amount, gross_amount, discount_id, discount_name, discount_amount
    ) values (
      'INV-' || upper(substr(md5(b.resto_id || v_due::text), 1, 10)),
      b.resto_id,
      (v_due - interval '1 month')::date,
      (v_due - interval '1 day')::date,
      v_due,
      v_amount,
      b.monthly_price,
      v_disc.id,
      v_disc.name,
      coalesce(v_disc.amount, 0)
    )
    on conflict (resto_id, period_start) do nothing;

    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- Resto terhapus juga tidak dikunci karena tagihan: layar penguncian
-- menawarkan membayar, dan tidak ada gunanya menagih resto yang sudah
-- kita hentikan sendiri.
create or replace function is_resto_billing_locked(p_resto_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when is_super_admin() then false
    when is_resto_deleted(p_resto_id) then false
    else coalesce((select locked from resto_billing_state(p_resto_id)), false)
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menghapus dan mengembalikan
-- ─────────────────────────────────────────────────────────────────────
--
-- Lewat RPC, bukan UPDATE langsung: penandanya ikut mencatat siapa dan
-- kapan. Penghapusan tanpa jejak siapa yang melakukannya adalah
-- pertanyaan yang tidak akan pernah terjawab saat ada yang menanyakannya
-- enam bulan kemudian.

create or replace function set_resto_deleted(p_resto_id text, p_deleted boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menghapus merchant';
  end if;

  if p_resto_id = 'merchantpos' then
    raise exception 'Penyewa platform tidak dapat dihapus';
  end if;

  update restaurants
  set is_deleted = p_deleted,
      deleted_at = case when p_deleted then now() else null end,
      deleted_by = case when p_deleted then auth.jwt() ->> 'email' else null end,
      -- Ikut dinonaktifkan supaya seluruh saringan `active` yang sudah
      -- ada di aplikasi langsung berlaku, tanpa menunggu tiap layar
      -- diajari mengenali penanda baru ini.
      active = case when p_deleted then false else active end
  where id = p_resto_id;
end;
$$;

commit;


-- ═══════════════════════════════════════════════════════════
-- 70. billing_discount_apply.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — diskon ikut memotong tagihan yang sudah terbit.
--
-- Jalankan SETELAH resto_soft_delete.sql. Aman diulang.
--
-- Tagihan diterbitkan tujuh hari sebelum jatuh tempo. Diskon yang dibuat
-- sesudah itu tidak pernah sampai ke tagihan yang sudah ada: penerbitnya
-- memakai `on conflict do nothing`, yang memang menjaga satu tagihan per
-- periode — tapi juga membekukan nominalnya sejak detik pertama.
--
-- Yang terlihat: harga langganan di kartu paket sudah turun, sementara
-- tagihannya masih penuh. Orang yang membacanya menyimpulkan diskonnya
-- tidak berlaku, dan itu kesimpulan yang wajar.
--
-- ── Nomor VA harus ikut dibuang ──────────────────────────────────────
--
-- VA-nya tertutup di nominal tagihan (`is_closed` + `expected_amount`).
-- Kalau nominalnya berubah sementara nomor VA lamanya dibiarkan,
-- transfer sebesar nominal baru akan DITOLAK bank — resto membayar
-- jumlah yang benar dan tetap dianggap belum bayar. Karena itu nomornya
-- dikosongkan tiap kali nominalnya berubah, supaya yang berikutnya
-- diterbitkan ulang dengan nominal yang benar.

begin;

create or replace function generate_billing_invoices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  b record;
  v_due date;
  v_disc record;
  v_amount bigint;
begin
  for b in
    select rb.* from resto_billing rb
    join restaurants r on r.id = rb.resto_id
    where rb.active = true
      and rb.monthly_price > 0
      and r.is_deleted = false
  loop
    v_due := _billing_due_on(b.billing_day, current_date);
    continue when v_due - current_date > 7;

    select * into v_disc from _best_billing_discount(b.resto_id, b.monthly_price);
    v_amount := b.monthly_price - coalesce(v_disc.amount, 0);

    insert into billing_invoices (
      id, resto_id, period_start, period_end, due_date,
      amount, gross_amount, discount_id, discount_name, discount_amount
    ) values (
      'INV-' || upper(substr(md5(b.resto_id || v_due::text), 1, 10)),
      b.resto_id,
      (v_due - interval '1 month')::date,
      (v_due - interval '1 day')::date,
      v_due,
      v_amount,
      b.monthly_price,
      v_disc.id,
      v_disc.name,
      coalesce(v_disc.amount, 0)
    )
    on conflict (resto_id, period_start) do nothing;

    if found then
      v_count := v_count + 1;
    end if;

    -- Menyegarkan tagihan yang sudah ada, selama belum dibayar.
    --
    -- Hanya yang berstatus 'unpaid'. Yang sudah 'review' berarti restonya
    -- sudah mentransfer sejumlah tertentu dan sedang menunggu diperiksa —
    -- mengubah nominalnya di bawah kaki orang yang sudah membayar adalah
    -- cara tercepat membuat pembayaran yang benar terlihat kurang.
    update billing_invoices i
    set amount = v_amount,
        gross_amount = b.monthly_price,
        discount_id = v_disc.id,
        discount_name = v_disc.name,
        discount_amount = coalesce(v_disc.amount, 0),
        -- Nomor VA dibuang begitu nominalnya berubah. Lihat catatan di
        -- kepala berkas: VA tertutup akan menolak transfer sebesar
        -- nominal baru.
        va_bank = null,
        va_number = null,
        va_id = null,
        va_expires_at = null
    where i.resto_id = b.resto_id
      and i.period_start = (v_due - interval '1 month')::date
      and i.status = 'unpaid'
      and i.amount <> v_amount;
  end loop;
  return v_count;
end;
$$;

-- Menyegarkan satu tagihan sekarang juga.
--
-- Dipakai layar Super Admin sesudah menyunting diskon: menunggu
-- penjadwal harian berarti resto melihat tagihan penuh sampai besok,
-- dan yang menjelaskan selisihnya adalah orang yang menerima telepon.
create or replace function refresh_billing_invoice(p_invoice_id text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv billing_invoices;
  v_price bigint;
  v_disc record;
  v_amount bigint;
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menyegarkan tagihan';
  end if;

  select * into v_inv from billing_invoices where id = p_invoice_id;
  if v_inv.id is null then
    raise exception 'Tagihan tidak ditemukan';
  end if;
  if v_inv.status <> 'unpaid' then
    return v_inv.amount;
  end if;

  select monthly_price into v_price from resto_billing where resto_id = v_inv.resto_id;
  if v_price is null then
    return v_inv.amount;
  end if;

  select * into v_disc from _best_billing_discount(v_inv.resto_id, v_price);
  v_amount := v_price - coalesce(v_disc.amount, 0);

  update billing_invoices
  set amount = v_amount,
      gross_amount = v_price,
      discount_id = v_disc.id,
      discount_name = v_disc.name,
      discount_amount = coalesce(v_disc.amount, 0),
      va_bank = case when v_amount <> v_inv.amount then null else va_bank end,
      va_number = case when v_amount <> v_inv.amount then null else va_number end,
      va_id = case when v_amount <> v_inv.amount then null else va_id end,
      va_expires_at =
        case when v_amount <> v_inv.amount then null else va_expires_at end
  where id = p_invoice_id;

  return v_amount;
end;
$$;

-- Tagihan lama yang terbit sebelum kolom diskon ada belum punya
-- gross_amount. Diisi dari nominalnya sendiri, supaya rincian di layar
-- tidak menampilkan "harga langganan Rp 0".
update billing_invoices
set gross_amount = amount
where gross_amount is null;

commit;


-- ═══════════════════════════════════════════════════════════
-- 71. billing_journal_gross.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pendapatan langganan dicatat sebesar harga penuh.
--
-- Jalankan SETELAH billing_discount_apply.sql. Aman diulang.
--
-- ── Kesalahannya ─────────────────────────────────────────────────────
--
-- Pemicu jurnal mengkredit `amount`, yaitu nominal yang SUDAH dipotong
-- diskon, lalu mendebit diskonnya sekali lagi. Untuk tagihan 230.000
-- dengan diskon 50%, jurnalnya jadi:
--
--     kredit  Pendapatan Langganan   115.000
--     debit   Diskon Langganan       115.000
--     ────────────────────────────────────── +
--     bersih                               0
--
-- Padahal uang yang benar-benar masuk 115.000. Diskonnya terhitung dua
-- kali: sekali dengan mengecilkan pendapatannya, sekali lagi sebagai
-- debit tersendiri.
--
-- Yang benar: pendapatan dicatat sebesar harga daftarnya, dan diskon
-- menguranginya.
--
--     kredit  Pendapatan Langganan   230.000
--     debit   Diskon Langganan       115.000
--     ────────────────────────────────────── +
--     bersih                          115.000
--
-- Bukan sekadar supaya angka bersihnya benar. Dengan cara ini, "berapa
-- harga daftar yang kita jual" dan "berapa yang kita berikan sebagai
-- potongan" jadi dua angka yang bisa dibaca terpisah — dan pertanyaan
-- "berapa besar diskon kita tahun ini" punya jawabannya sendiri, bukan
-- angka yang harus dikira-kira dari selisih.

begin;

create or replace function log_billing_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
  v_resto text;
  v_gross bigint;
begin
  if new.status <> 'paid' then
    return new;
  end if;

  if exists (
    select 1 from gl_journal_entries
    where reference_type = 'billing' and reference_id = new.id
  ) then
    return new;
  end if;

  select name into v_resto from restaurants where id = new.resto_id;

  -- Harga daftarnya. Tagihan lama yang terbit sebelum kolom diskon ada
  -- tidak punya gross_amount — untuk mereka, nominalnya sendiri memang
  -- harga penuhnya.
  v_gross := coalesce(new.gross_amount, new.amount);

  select * into v_gl from _gl_account_for('merchantpos', 'subscription');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      'merchantpos',
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'billing', new.id, v_gross, 'credit',
      'Langganan ' || coalesce(v_resto, new.resto_id) || ' — ' || new.id
    );
  end if;

  if coalesce(new.discount_amount, 0) > 0 then
    select * into v_gl from _gl_account_for('merchantpos', 'subscription_discount');
    if v_gl.gl_code is not null and v_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        'merchantpos',
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl.gl_code, v_gl.gl_name,
        'billing_discount', new.id, new.discount_amount, 'debit',
        coalesce(nullif(new.discount_name, ''), 'Diskon langganan')
          || ' — ' || coalesce(v_resto, new.resto_id)
      );
    end if;
  end if;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memperbaiki jurnal yang sudah terlanjur salah
-- ─────────────────────────────────────────────────────────────────────
--
-- Barisnya TIDAK diubah dan TIDAK dihapus. Jurnal hanya bertambah —
-- aturan yang sama dengan pembalikan pengeluaran, dan alasannya sama:
-- pembukuan yang barisnya bisa disunting belakangan tidak bisa dipakai
-- membuktikan apa pun.
--
-- Yang ditambahkan adalah selisihnya, sebagai baris koreksi tersendiri
-- yang menyebut dirinya koreksi. Orang yang membacanya enam bulan lagi
-- akan melihat kesalahannya sekaligus perbaikannya, bukan pembukuan yang
-- terlihat selalu benar.

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  'merchantpos',
  (now() at time zone 'Asia/Jakarta')::date,
  (now() at time zone 'Asia/Jakarta')::time,
  j.gl_code, j.gl_name,
  'billing', i.id,
  i.gross_amount - i.amount, 'credit',
  'Koreksi pencatatan diskon — ' || i.id
    || ' (pendapatan semula dicatat sesudah potongan)'
from billing_invoices i
join gl_journal_entries j
  on j.reference_type = 'billing'
 and j.reference_id = i.id
 and j.entry_type = 'credit'
where i.gross_amount is not null
  and i.gross_amount > i.amount
  and j.amount = i.amount
  and not exists (
    select 1 from gl_journal_entries k
    where k.reference_type = 'billing'
      and k.reference_id = i.id
      and k.description like 'Koreksi pencatatan diskon%'
  );

commit;


-- ═══════════════════════════════════════════════════════════
-- 72. gl_discount_backfill.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — GL Diskon terisi bawaannya di tiap resto.
--
-- Jalankan SETELAH billing_journal_gross.sql. Aman diulang.
--
-- Akun diskon lahir bersama fitur promo menu, dan disemai untuk seluruh
-- resto yang ada saat itu. Tapi barisnya bisa hilang di tiga jalan:
-- resto yang dibuat sebelum berkas promonya dijalankan, resto yang
-- barisnya terhapus saat merapikan pemetaan, dan resto yang barisnya ada
-- tapi nomornya dikosongkan.
--
-- Ketiganya berakhir sama: pemicu jurnal diam-diam melewatkan diskonnya.
-- Transaksinya tetap terjadi, potongannya tetap diberikan, tapi tidak
-- ada satu baris pun di GL Diskon — dan pertanyaan "berapa yang kita
-- berikan sebagai potongan bulan ini" tidak punya jawaban di mana pun.
--
-- Nomornya tetap bisa diubah Finance lewat Mapping GL Account. Yang
-- dijamin di sini cuma satu: tidak ada resto yang berjalan tanpa akun
-- diskon sama sekali.

begin;

-- Resto biasa: 2200002, sederet dengan akun pengurang pendapatan lain.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'discount', '2200002', 'GL Diskon Penjualan'
from restaurants r
where r.is_platform = false
on conflict (resto_id, payment_method) do nothing;

-- Baris yang ada tapi nomornya kosong ikut diisi. `on conflict do
-- nothing` di atas tidak menyentuhnya — dan baris kosong persis sama
-- akibatnya dengan baris yang tidak ada.
update gl_accounts
set gl_code = '2200002',
    gl_name = coalesce(nullif(gl_name, ''), 'GL Diskon Penjualan')
where payment_method = 'discount'
  and coalesce(gl_code, '') = ''
  and resto_id in (select id from restaurants where is_platform = false);

-- MerchantPOS memakai golongan 11xxxxx untuk pembukuannya sendiri.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values
  ('merchantpos', 'discount',              '1100072', 'GL Diskon Lain MerchantPOS'),
  ('merchantpos', 'subscription_discount', '1100002', 'GL Diskon Langganan')
on conflict (resto_id, payment_method) do nothing;

update gl_accounts
set gl_code = '1100002',
    gl_name = coalesce(nullif(gl_name, ''), 'GL Diskon Langganan')
where resto_id = 'merchantpos'
  and payment_method = 'subscription_discount'
  and coalesce(gl_code, '') = '';

-- Resto baru sesudah ini sudah terurus oleh seed_gl_accounts_for_new_resto,
-- yang membaca _default_gl_accounts() — dan 'discount' sudah ada di sana.

commit;


-- ═══════════════════════════════════════════════════════════
-- 73. platform_gl_renumber.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — nomor akun penyewa platform dipindah ke golongan 11xxxxx.
--
-- Jalankan SETELAH gl_discount_backfill.sql. Aman diulang.
--
-- ── Kenapa nomornya tidak sesuai ─────────────────────────────────────
--
-- Baris 'merchantpos' dimasukkan ke tabel restaurants, dan pemicu
-- seed_gl_accounts_for_new_resto langsung menyemai bagan akun BAWAAN
-- RESTO untuknya — 195xxxx, 196xxxx, 199xxxx, dan seterusnya. Nomor
-- 11xxxxx yang dimaksudkan untuk platform baru disisipkan sesudah itu,
-- dan `on conflict do nothing` membuatnya tidak melakukan apa-apa.
--
-- Akibatnya bukan sekadar angka yang berbeda dari dokumen. Janjinya
-- adalah satu baris jurnal bisa dikenali pemiliknya hanya dari nomor
-- akunnya — dan dengan MerchantPOS memakai 199xxxx yang sama dengan resto,
-- janji itu tidak berlaku. Orang yang membaca ekspor gabungan tidak
-- punya cara membedakan mana pendapatan resto dan mana pendapatan kami.
--
-- ── Yang tidak disentuh ──────────────────────────────────────────────
--
-- Hanya nomor yang masih sama persis dengan bawaan resto yang dipindah.
-- Nomor yang sudah disunting sendiri lewat Mapping GL dibiarkan: itu
-- keputusan orang, dan menimpanya berarti mengembalikan pekerjaannya ke
-- bawaan tanpa dia tahu.
--
-- Jurnal yang sudah tercatat ikut dipindahkan nomornya, supaya baris
-- lama dan baru menunjuk akun yang sama. Yang diubah cuma label
-- akunnya; nominal, arah, dan rujukannya tidak disentuh sama sekali.

begin;

-- Pasangan nomor bawaan resto → nomor platform.
--
-- Ditulis sebagai daftar sebaris di dalam tiap pernyataan, bukan tabel
-- sementara. Tabel sementara hanya hidup di satu sesi, dan SQL Editor
-- Supabase bisa menjalankan tiap pernyataan lewat koneksi yang berbeda:
--
--   ERROR: relation "_peta_gl" does not exist
--
-- Galatnya muncul di pernyataan kedua, bukan pada yang membuat tabelnya
-- — jadi yang membacanya menyangka ada yang salah pada UPDATE-nya.

-- Jurnal lebih dulu, selagi nomor lamanya masih bisa dicocokkan.
update gl_journal_entries j
set gl_code = p.ke,
    gl_name = p.nama
from (values
  ('cash',             '1950001', '1100010', 'GL Kas Tunai MerchantPOS'),
  ('qris',             '1950002', '1100012', 'GL Penerimaan QRIS MerchantPOS'),
  ('transfer',         '1950003', '1100011', 'GL Rekening MerchantPOS'),
  ('income_aggregate', '1950010', '1100020', 'GL Pendapatan MerchantPOS'),
  ('ppn',              '1960001', '1100070', 'GL PPN MerchantPOS'),
  ('service',          '1960002', '1100071', 'GL Biaya Service MerchantPOS'),
  ('petty_cash',       '1980001', '1100030', 'GL Petty Cash MerchantPOS'),
  ('total_balance',    '1990001', '1100040', 'GL Total Saldo MerchantPOS'),
  ('suspense',         '2100001', '1100050', 'GL Suspense MerchantPOS'),
  ('suspense_petty',   '2100002', '1100051', 'GL Suspense Petty MerchantPOS'),
  ('gateway_fee',      '2200001', '1100060', 'GL Biaya Gateway MerchantPOS'),
  ('discount',         '2200002', '1100072', 'GL Diskon Lain MerchantPOS')
) as p(payment_method, dari, ke, nama)
where j.resto_id = 'merchantpos'
  and j.gl_code = p.dari;

update gl_accounts a
set gl_code = p.ke,
    gl_name = p.nama
from (values
  ('cash',             '1950001', '1100010', 'GL Kas Tunai MerchantPOS'),
  ('qris',             '1950002', '1100012', 'GL Penerimaan QRIS MerchantPOS'),
  ('transfer',         '1950003', '1100011', 'GL Rekening MerchantPOS'),
  ('income_aggregate', '1950010', '1100020', 'GL Pendapatan MerchantPOS'),
  ('ppn',              '1960001', '1100070', 'GL PPN MerchantPOS'),
  ('service',          '1960002', '1100071', 'GL Biaya Service MerchantPOS'),
  ('petty_cash',       '1980001', '1100030', 'GL Petty Cash MerchantPOS'),
  ('total_balance',    '1990001', '1100040', 'GL Total Saldo MerchantPOS'),
  ('suspense',         '2100001', '1100050', 'GL Suspense MerchantPOS'),
  ('suspense_petty',   '2100002', '1100051', 'GL Suspense Petty MerchantPOS'),
  ('gateway_fee',      '2200001', '1100060', 'GL Biaya Gateway MerchantPOS'),
  ('discount',         '2200002', '1100072', 'GL Diskon Lain MerchantPOS')
) as p(payment_method, dari, ke, nama)
where a.resto_id = 'merchantpos'
  and a.payment_method = p.payment_method
  and a.gl_code = p.dari;

-- Dua akun yang memang hanya milik platform. Disisipkan kalau pemicunya
-- tidak pernah membuatnya — ia hanya menyemai bawaan resto, dan
-- langganan bukan salah satunya.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values
  ('merchantpos', 'subscription',          '1100001', 'GL Pendapatan Langganan'),
  ('merchantpos', 'subscription_discount', '1100002', 'GL Diskon Langganan')
on conflict (resto_id, payment_method) do nothing;

commit;


-- ═══════════════════════════════════════════════════════════
-- 74. product_toppings.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — topping per menu, berikut harga dan batas pilihnya.
--
-- Jalankan SETELAH platform_gl_renumber.sql. Aman diulang.
--
-- Topping berbeda bentuk dari level/varian, dan itu sebabnya ia tidak
-- menumpang di sana: level dipilih SATU dari beberapa ("Pedas" atau
-- "Tidak Pedas"), topping dipilih BEBERAPA sekaligus ("Keju dan
-- Telur"). Memaksakan keduanya jadi satu bentuk berarti salah satunya
-- harus berpura-pura jadi yang lain, dan yang berpura-pura selalu bocor
-- di tempat yang tidak terduga.
--
-- Bentuknya:
--
--   [{"name": "Keju", "price": 5000}, {"name": "Telur", "price": 3000}]
--
-- Harga disimpan di sini, bukan dikirim bersama pilihan dari HP: harga
-- yang datang dari aplikasi bisa diubah siapa pun yang ingin menambahkan
-- keju seharga nol rupiah.

begin;

alter table products add column if not exists toppings jsonb not null default '[]'::jsonb;

-- Paling banyak berapa yang boleh dipilih sekaligus. Nol berarti tanpa
-- batas — sebanyak yang ditawarkan.
--
-- Batasnya ada bukan cuma soal harga: dapur punya ruang terbatas di atas
-- satu porsi, dan "semua topping sekaligus" adalah pesanan yang tidak
-- bisa dibuat.
alter table products add column if not exists max_toppings smallint not null default 0;

alter table products drop constraint if exists products_max_toppings_check;
alter table products add constraint products_max_toppings_check
  check (max_toppings >= 0);

commit;


-- ═══════════════════════════════════════════════════════════
-- 75. vouchers.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — voucher untuk pelanggan, dananya benar-benar berpindah.
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
  ('merchantpos', 'voucher',        '1100073', 'GL Voucher'),
  ('merchantpos', 'voucher_redeem', '1100074', 'GL Voucher Redeem')
on conflict (resto_id, payment_method) do nothing;

-- Nomor lama dari rancangan sebelumnya dipindahkan, bukan ditinggalkan
-- jadi akun kembar yang tidak pernah dipakai lagi.
update gl_accounts
set gl_code = '1100073', gl_name = 'GL Voucher'
where resto_id = 'merchantpos' and payment_method = 'voucher'
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

create or replace function _jurnal_merchantpos(
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
  select * into v_gl from _gl_account_for('merchantpos', p_method);
  if v_gl.gl_code is null or v_gl.gl_code = '' then
    return;
  end if;
  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    'merchantpos',
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
  perform _jurnal_merchantpos('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_merchantpos('voucher', v_id, v_amount * p_quantity,
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

  perform _jurnal_merchantpos('voucher', v_id, v.amount,
    'debit', 'Ditebus ' || v.code || ' — ' || v_email);
  perform _jurnal_merchantpos('voucher_redeem', v_id, v.amount,
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
  perform _jurnal_merchantpos('voucher_redeem', v_claim.id, new.voucher_amount,
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
      'Voucher MerchantPOS ' || coalesce(new.voucher_code, '') ||
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

    perform _jurnal_merchantpos('voucher_redeem', c.id, c.amount,
      'debit', 'Voucher hangus tanpa dipakai');
    perform _jurnal_merchantpos('total_balance', c.id, c.amount,
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
      perform _jurnal_merchantpos('voucher', v.id, v_sisa,
        'debit', 'Sisa voucher ' || v.code || ' tidak ditebus');
      perform _jurnal_merchantpos('total_balance', v.id, v_sisa,
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


-- ═══════════════════════════════════════════════════════════
-- 76. voucher_payouts.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — voucher yang dipakai pelanggan dibayarkan sungguhan ke resto.
--
-- Jalankan SETELAH vouchers.sql dan resto_payment_accounts.sql.
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang tahap ketiga voucher hanya berupa jurnal: GL Voucher
-- Redeem didebit, GL Transfer restonya dikredit. Pembukuannya benar,
-- tapi tidak ada satu rupiah pun yang berpindah. Resto menyerahkan
-- makanan seharga seratus ribu, menerima nol dari pelanggan, dan yang
-- didapatnya cuma satu baris di layar.
--
-- Berkas ini yang membuat barisnya diikuti uang.
--
-- ── Kenapa transfer antar-akun, bukan pencairan ke rekening ──────────
--
-- Xendit punya dua cara mengirim uang keluar. Pencairan (disbursement)
-- menembak nomor rekening bank langsung — dan untuk itu kita harus
-- menyimpan nomor rekening tiap resto. Kita sengaja tidak menyimpannya
-- (lihat resto_payment_accounts.sql): data rekening milik orang lain
-- yang kita tampung adalah kerugian yang bukan milik kita tapi kita
-- yang menyebabkannya kalau bocor.
--
-- Transfer antar-akun memindahkan saldo dari akun MerchantPOS ke sub-akun
-- restonya di dalam xenPlatform. Tujuannya cukup disebut dengan
-- pengenal sub-akun yang memang sudah kita simpan. Dari sana dananya
-- ikut jadwal pencairan resto itu sendiri, ke rekening yang mereka
-- daftarkan sendiri, yang tidak pernah kita lihat.
--
-- ── Kenapa antrean, bukan panggilan langsung dari pemicu ─────────────
--
-- Pemicu berjalan di dalam transaksi yang menyimpan pesanan. Memanggil
-- Xendit dari sana berarti pesanan pelanggan gagal tersimpan setiap
-- kali Xendit lambat atau mati — pelanggan yang sudah antre di kasir
-- menanggung akibat dari gangguan pihak ketiga. Dan kalau panggilannya
-- terlanjur sampai lalu transaksinya dibatalkan, uangnya sudah pindah
-- untuk pesanan yang tidak pernah ada.
--
-- Jadi pemicunya cuma menulis satu baris "harus dibayar". Yang
-- membayarnya berjalan belakangan, boleh gagal, dan boleh diulang.

begin;

create table if not exists voucher_payouts (
  id uuid primary key default gen_random_uuid(),

  -- Satu klaim satu pencairan. Ini batasan basis data, bukan
  -- pemeriksaan di kode: penjadwal yang berjalan dua kali, atau
  -- pemicu yang entah bagaimana menyala dua kali, tidak boleh bisa
  -- membayar voucher yang sama dua kali.
  claim_id text not null unique references voucher_claims (id) on delete cascade,

  resto_id text not null references restaurants (id) on delete cascade,
  order_id uuid,
  amount bigint not null check (amount > 0),

  -- pending → sent, atau pending → failed lalu dicoba lagi.
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed')),

  -- Yang dikembalikan Xendit, supaya baris ini bisa dicocokkan dengan
  -- mutasi di dashboard mereka tanpa menebak-nebak.
  transfer_id text,

  -- Alasan gagalnya, apa adanya dari penyedia. Disimpan supaya yang
  -- memeriksa besok pagi tidak perlu membuka log fungsi edge.
  last_error text,
  attempts integer not null default 0,

  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists voucher_payouts_pending_idx
  on voucher_payouts (created_at) where status <> 'sent';

create index if not exists voucher_payouts_resto_idx
  on voucher_payouts (resto_id, created_at desc);

alter table voucher_payouts enable row level security;

-- Resto boleh melihat yang jadi haknya; Super Admin melihat semuanya.
drop policy if exists "voucher_payouts: read" on voucher_payouts;
create policy "voucher_payouts: read" on voucher_payouts
  for select using (
    is_super_admin() or is_resto_employee(resto_id, array['finance', 'owner', 'admin'])
  );

-- Tidak ada kebijakan tulis untuk siapa pun. Yang menulis ke sini
-- adalah pemicu pemakaian voucher dan fungsi pencairannya, keduanya
-- SECURITY DEFINER. Tangan yang bisa menulis langsung ke tabel ini
-- adalah tangan yang bisa memerintahkan uang sungguhan berpindah.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pemicunya sekarang juga mengantre pencairan
-- ─────────────────────────────────────────────────────────────────────

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
  perform _jurnal_merchantpos('voucher_redeem', v_claim.id, new.voucher_amount,
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
      'Voucher MerchantPOS ' || coalesce(new.voucher_code, '') ||
        ' — pesanan #' || v_ref
    );
  end if;

  -- Uang sungguhannya menyusul. Baris ini yang membuat jurnal di atas
  -- bukan sekadar janji.
  insert into voucher_payouts (claim_id, resto_id, order_id, amount)
  values (v_claim.id, new.resto_id, new.id, new.voucher_amount)
  on conflict (claim_id) do nothing;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Yang dibaca dan ditulis fungsi pencairannya
-- ─────────────────────────────────────────────────────────────────────

-- Antrean yang siap dibayar, lengkap dengan tujuannya.
--
-- Resto yang belum punya sub-akun aktif tidak ikut terangkut: tidak
-- ada tujuan untuk dikirimi, dan mencobanya cuma menaikkan `attempts`
-- sampai barisnya terlihat seperti gangguan Xendit padahal yang kurang
-- ada di sisi kita.
-- Tipe kembaliannya pernah salah menyebut claim_id sebagai uuid.
-- `create or replace` tidak bisa mengubah tipe kembalian, jadi yang
-- lama harus dibuang dulu — di basis data yang belum pernah
-- menjalankannya, baris ini tidak melakukan apa-apa.
drop function if exists voucher_payouts_due(integer);

create or replace function voucher_payouts_due(p_limit integer default 50)
returns table (
  payout_id uuid,
  claim_id text,
  resto_id text,
  resto_name text,
  account_id text,
  amount bigint
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.claim_id, p.resto_id, r.name, a.account_id, p.amount
  from voucher_payouts p
  join resto_payment_accounts a
    on a.resto_id = p.resto_id and a.active and a.account_id <> ''
  left join restaurants r on r.id = p.resto_id
  where p.status <> 'sent'
  order by p.created_at
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

revoke all on function voucher_payouts_due(integer) from public, anon, authenticated;

-- Menandai hasilnya. Hanya menambah dan menandai — tidak pernah
-- menghapus barisnya, karena baris pencairan yang hilang adalah uang
-- yang berpindah tanpa jejak.
create or replace function mark_voucher_payout(
  p_payout_id uuid,
  p_ok boolean,
  p_transfer_id text default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update voucher_payouts
  set status      = case when p_ok then 'sent' else 'failed' end,
      transfer_id = coalesce(p_transfer_id, transfer_id),
      last_error  = case when p_ok then null else p_error end,
      attempts    = attempts + 1,
      sent_at     = case when p_ok then now() else sent_at end
  where id = p_payout_id
    and status <> 'sent';   -- yang sudah terkirim tidak bisa dibatalkan
end;
$$;

revoke all on function mark_voucher_payout(uuid, boolean, text, text) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Mengantre yang sudah terlanjur dipakai sebelum berkas ini ada
-- ─────────────────────────────────────────────────────────────────────
--
-- Voucher yang sudah dipakai kemarin tetap utang yang belum dibayar.
-- Tanggal berkas ini dijalankan bukan garis pemisah antara utang dan
-- bukan utang.

insert into voucher_payouts (claim_id, resto_id, order_id, amount)
select c.id, c.resto_id, c.order_id, c.amount
from voucher_claims c
where c.status = 'used' and c.resto_id is not null and c.amount > 0
on conflict (claim_id) do nothing;

-- ─────────────────────────────────────────────────────────────────────
-- Penjadwalnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Antrean yang tidak pernah dijalankan sama saja dengan tidak ada.
-- Tapi alamat fungsi dan kuncinya berbeda antara proyek uji dan
-- produksi, jadi berkas ini tidak menebaknya — selama barisnya belum
-- diisi, penjadwalnya berjalan dan tidak melakukan apa-apa.

create table if not exists voucher_payout_config (
  id integer primary key default 1 check (id = 1),
  function_url text,
  service_key text,
  updated_at timestamptz not null default now()
);

insert into voucher_payout_config (id) values (1) on conflict (id) do nothing;

alter table voucher_payout_config enable row level security;
-- Tidak ada kebijakan apa pun: isinya kunci layanan, dan tidak ada
-- peran di aplikasi yang punya alasan membacanya.

create or replace function run_voucher_payouts()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_cfg voucher_payout_config;
begin
  select * into v_cfg from voucher_payout_config where id = 1;
  if v_cfg.function_url is null or v_cfg.service_key is null then
    return;
  end if;

  perform net.http_post(
    url := v_cfg.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_cfg.service_key
    ),
    body := jsonb_build_object('limit', 50)
  );
end;
$$;

revoke all on function run_voucher_payouts() from public, anon, authenticated;

-- Tiap 15 menit. Resto tidak perlu menunggu semalam untuk menerima
-- uang yang sudah jadi haknya sejak pesanannya selesai.
select cron.unschedule('settle-voucher-payouts')
where exists (select 1 from cron.job where jobname = 'settle-voucher-payouts');

select cron.schedule('settle-voucher-payouts', '*/15 * * * *',
  $cron$select run_voucher_payouts();$cron$);

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Deploy fungsinya:
--
--      supabase functions deploy settle-voucher-payouts \
--        --project-ref xizpwtycczigjhzxegen
--
-- 2. Isi secret pengenal akun MerchantPOS sendiri di Xendit — transfer
--    butuh tahu dari akun mana uangnya diambil:
--
--      supabase secrets set XENDIT_ACCOUNT_ID=...
--
--    Nomornya ada di Dashboard Xendit → Settings → Developers, atau:
--
--      curl https://api.xendit.co/balance -u 'xnd_...:' -v
--
-- 3. Isi alamat fungsi dan kunci layanan supaya penjadwalnya hidup:
--
--      update voucher_payout_config set
--        function_url = 'https://xizpwtycczigjhzxegen.supabase.co/functions/v1/settle-voucher-payouts',
--        service_key  = '<service_role key>',
--        updated_at   = now()
--      where id = 1;
--
-- 4. Periksa antreannya kapan saja:
--
--      select p.status, p.attempts, p.amount, r.name, p.last_error
--      from voucher_payouts p left join restaurants r on r.id = p.resto_id
--      order by p.created_at desc;
--
-- Resto yang belum punya sub-akun akan menumpuk sebagai `pending` tanpa
-- pernah dicoba. Itu disengaja — dan cara melihatnya:
--
--   select r.name, count(*), sum(p.amount)
--   from voucher_payouts p
--   left join restaurants r on r.id = p.resto_id
--   left join resto_payment_accounts a on a.resto_id = p.resto_id
--   where p.status <> 'sent' and (a.resto_id is null or not a.active)
--   group by r.name;


-- ═══════════════════════════════════════════════════════════
-- 77. billing_due_day.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — tanggal tagih 29, 30, 31, dan jatuh tempo berikutnya.
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


-- ═══════════════════════════════════════════════════════════
-- 78. market_report.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — laporan pasar untuk Super Admin.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Empat pertanyaan yang selama ini hanya bisa dijawab dengan membuka
-- satu per satu resto: siapa pelanggan yang paling sering memakai
-- MerchantPOS, siapa yang mendaftar lalu tidak pernah memesan, resto mana
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
-- Resto platform (MerchantPOS sendiri) dan resto yang sudah dihapus tidak
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
-- bukan hiasan — tanpa itu fungsinya membocorkan seluruh pasar MerchantPOS
-- ke siapa pun yang bisa memanggil RPC. Ditulis sebagai syarat WHERE,
-- bukan RAISE, supaya yang bukan Super Admin menerima daftar kosong
-- alih-alih pesan yang mengonfirmasi bahwa datanya ada.


-- ═══════════════════════════════════════════════════════════
-- 79. voucher_announcement.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — voucher yang terbit langsung mengabari pelanggan.
--
-- Jalankan SETELAH vouchers.sql, announcement_audience.sql, dan
-- announcement_categories.sql. Aman dijalankan berulang kali.
--
-- Voucher yang diterbitkan tapi tidak diumumkan adalah uang yang sudah
-- keluar dari saldo MerchantPOS untuk sesuatu yang tidak ada yang tahu.
-- Kuotanya habis oleh siapa pun yang kebetulan membuka layar Voucher
-- Saya, dan sisanya hangus tanpa pernah dilihat orang.
--
-- Pengumumannya ditulis di sini, di dalam transaksi yang sama dengan
-- penerbitannya. Dua langkah terpisah yang harus diingat berurutan
-- berarti suatu saat yang kedua terlewat.
--
-- Push-nya menyusul sendiri: `trg_queue_push_announcement` sudah
-- menyala pada setiap baris baru di app_announcements, jadi berkas ini
-- tidak perlu tahu apa-apa soal FCM.

begin;

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
  v_nilai text;
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
  perform _jurnal_merchantpos('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_merchantpos('voucher', v_id, v_amount * p_quantity,
    'credit', 'Alokasi voucher ' || v_code);

  -- Rp 100.000, bukan 100000. Angka telanjang di notifikasi terbaca
  -- salah sekilas, dan sekilas adalah satu-satunya waktu yang dipunya
  -- notifikasi.
  v_nilai := 'Rp ' || to_char(v_amount, 'FM999G999G999G999');

  -- Kabarnya masuk Kotak Masuk tab Umum, dan pemicu push mengantarnya
  -- ke layar kunci. Kodenya ikut di badan pesan supaya bisa disalin
  -- tanpa membuka aplikasi.
  insert into app_announcements (title, body, category, audience, created_by)
  values (
    'Voucher ' || v_nilai || ' dari MerchantPOS',
    'Buruan tebus, kuotanya cuma ' || p_quantity || ' dan siapa cepat dia dapat! ' ||
    'Kode voucher: ' || v_code || E'\n\n' ||
    'Tiap voucher bernilai ' || v_nilai ||
    case when p_min_purchase > 0
      then ', minimal belanja Rp ' || to_char(p_min_purchase, 'FM999G999G999G999')
      else '' end ||
    '. Berlaku sampai ' || to_char(p_expires_on, 'DD Mon YYYY') || '. ' ||
    'Tebus di menu Voucher Saya — satu akun cuma bisa sekali, jadi jangan sampai keduluan.',
    'general',
    'customers',
    auth.jwt() ->> 'email'
  );

  return v_id;
end;
$$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select title, category, audience, created_at
--   from app_announcements where audience = 'customers'
--   order by created_at desc limit 5;
--
-- Kalau barisnya ada tapi push-nya tidak sampai, yang bermasalah bukan
-- berkas ini — periksa antrean push-nya:
--
--   select event, created_at, sent_at, error
--   from push_outbox order by created_at desc limit 10;


-- ═══════════════════════════════════════════════════════════
-- 80. voucher_manage.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — banner voucher, dan menghapus batch yang tidak jadi.
--
-- Jalankan SETELAH voucher_announcement.sql. Aman dijalankan berulang.

begin;

-- Gambar 16:9 sebagai base64, sependekatan dengan banner promo resto
-- dan gambar pengumuman. Menyimpannya di kolom, bukan object storage,
-- membuat satu voucher tetap satu baris — pengumuman yang gambarnya
-- hilang karena berkasnya terhapus terpisah adalah jenis kerusakan yang
-- tidak perlu diciptakan.
alter table vouchers add column if not exists banner_base64 text;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Terbit — sekarang membawa bannernya ke kotak masuk
-- ─────────────────────────────────────────────────────────────────────

create or replace function generate_voucher_batch(
  p_code text,
  p_name text,
  p_total bigint,
  p_quantity integer,
  p_expires_on date,
  p_min_purchase bigint default 0,
  p_resto_ids jsonb default '[]'::jsonb,
  p_banner text default null
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
    min_purchase, resto_ids, banner_base64, created_by
  ) values (
    v_id, v_code, p_name,
    -- Yang dicatat keluar adalah yang benar-benar bisa ditebus. Sisa
    -- pembagian tidak pernah jadi voucher, jadi mencatatnya sebagai uang
    -- yang keluar berarti saldo berkurang untuk sesuatu yang tidak ada.
    v_amount * p_quantity,
    p_quantity, v_amount, p_expires_on,
    p_min_purchase, coalesce(p_resto_ids, '[]'::jsonb),
    nullif(p_banner, ''),
    auth.jwt() ->> 'email'
  );

  perform _jurnal_merchantpos('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_merchantpos('voucher', v_id, v_amount * p_quantity,
    'credit', 'Alokasi voucher ' || v_code);

  v_nilai := 'Rp ' || to_char(v_amount, 'FM999G999G999G999');

  insert into app_announcements (
    title, body, category, audience, image_base64, created_by
  ) values (
    'Voucher ' || v_nilai || ' dari MerchantPOS',
    'Buruan tebus, kuotanya cuma ' || p_quantity || ' dan siapa cepat dia dapat! ' ||
    'Kode voucher: ' || v_code || E'\n\n' ||
    'Tiap voucher bernilai ' || v_nilai ||
    case when p_min_purchase > 0
      then ', minimal belanja Rp ' || to_char(p_min_purchase, 'FM999G999G999G999')
      else '' end ||
    '. Berlaku sampai ' || to_char(p_expires_on, 'DD Mon YYYY') || '. ' ||
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
-- Menghapus batch yang tidak jadi
-- ─────────────────────────────────────────────────────────────────────
--
-- Dua syarat, dan keduanya soal uang.
--
-- Harus ditutup dulu. Batch yang masih berjalan sedang diumumkan ke
-- orang banyak; menghapusnya berarti kode yang sudah tersebar tiba-tiba
-- tidak ada, dan yang menemukannya adalah pelanggan yang mengetik kode
-- dari notifikasi lalu diberi tahu kodenya tidak ditemukan.
--
-- Harus belum ada yang menebus. Klaim adalah uang yang sudah menggantung
-- di tangan orang; barisnya juga yang dirujuk jurnal penebusan dan
-- antrean pencairan. Menghapus batch-nya membuat catatan itu kehilangan
-- namanya, dan yang tersisa adalah angka di buku besar tanpa keterangan
-- dari mana asalnya.
--
-- Dananya dikembalikan lebih dulu, bukan lenyap bersama barisnya. Batch
-- yang dihapus tanpa mengembalikan alokasinya adalah saldo MerchantPOS yang
-- berkurang selamanya untuk voucher yang tidak pernah ada.

create or replace function delete_voucher_batch(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v vouchers;
  v_klaim integer;
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menghapus voucher';
  end if;

  select * into v from vouchers where id = p_id;
  if v.id is null then
    raise exception 'Voucher tidak ditemukan';
  end if;

  if v.active then
    raise exception 'Tutup dulu vouchernya sebelum dihapus';
  end if;

  select count(*) into v_klaim from voucher_claims where voucher_id = v.id;
  if v_klaim > 0 then
    raise exception 'Sudah ada % pelanggan yang menebus — batch ini tidak bisa dihapus', v_klaim;
  end if;

  -- Alokasinya pulang ke saldo bebas, kecuali sudah pernah pulang lewat
  -- penjadwal kedaluwarsa.
  if v.settled_at is null then
    perform _jurnal_merchantpos('voucher', v.id, v.total_amount,
      'debit', 'Batal voucher ' || v.code);
    perform _jurnal_merchantpos('total_balance', v.id, v.total_amount,
      'credit', 'Dana voucher ' || v.code || ' kembali — batch dihapus');
  end if;

  -- Pengumumannya ikut dicabut. Kabar yang menyuruh menebus kode yang
  -- sudah tidak ada adalah kabar yang lebih buruk daripada tidak ada
  -- kabar sama sekali.
  delete from app_announcements
  where audience = 'customers'
    and category = 'general'
    and body like '%Kode voucher: ' || v.code || '%';

  delete from vouchers where id = v.id;
end;
$$;

revoke all on function delete_voucher_batch(text) from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select code, active, settled_at,
--          (select count(*) from voucher_claims c where c.voucher_id = v.id) as penebus
--   from vouchers v order by created_at desc;


-- ═══════════════════════════════════════════════════════════
-- 81. balance_topup.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — setoran modal ke saldo utama.
--
-- Jalankan SETELAH vouchers.sql dan platform_finance.sql. Aman diulang.
--
-- Ada satu jenis uang masuk yang selama ini tidak punya tempat: modal.
-- Investor menyetor ke MerchantPOS, atau pemilik resto menaruh uang awal
-- supaya kasnya tidak minus di hari pertama. Keduanya uang sungguhan
-- yang benar-benar masuk, tapi bukan penjualan dan bukan langganan —
-- jadi tidak ada pemicu yang menjurnalnya, dan saldonya berbunyi nol
-- padahal uangnya ada.
--
-- Mencatatnya sebagai "penghasilan" akan lebih buruk daripada tidak
-- mencatatnya: laporan penjualan jadi memuat uang yang tidak pernah
-- dijual, dan resto yang menyetor modal besar akan terlihat seperti
-- resto yang laris.

begin;

-- Akunnya sendiri, terpisah dari pendapatan.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- Untuk MerchantPOS — sederet dengan akun platform lainnya.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values ('merchantpos', 'capital', '1100003', 'GL Setoran Modal')
on conflict (resto_id, payment_method) do nothing;

-- Untuk tiap resto.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'capital', '1940001', 'GL Setoran Modal'
from restaurants r
where coalesce(r.is_platform, false) = false
on conflict (resto_id, payment_method) do nothing;

-- Jenis rujukan barunya. Daftarnya ditulis utuh, bukan ditambahi:
-- berkas lama yang dijalankan belakangan akan menyempitkannya lagi, dan
-- baris yang sudah memakai nilai baru jadi melanggar.
alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));

create table if not exists balance_topups (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,
  amount bigint not null check (amount > 0),

  -- Dari siapa, dan keterangannya. Setoran modal tanpa nama penyetor
  -- adalah uang yang tidak bisa dipertanggungjawabkan ke siapa pun.
  source text not null,
  note text,

  -- Bukti transfer, base64. Boleh kosong untuk setoran tunai langsung.
  proof_base64 text,

  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists balance_topups_resto_idx
  on balance_topups (resto_id, created_at desc);

alter table balance_topups enable row level security;

drop policy if exists "balance_topups: read" on balance_topups;
create policy "balance_topups: read" on balance_topups
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin', 'kasir'])
  );

-- Mencatatnya hanya Owner, Finance, dan Super Admin.
--
-- Kasir boleh melihat — angkanya memengaruhi saldo yang dia
-- pertanggungjawabkan — tapi tidak boleh menambah. Baris yang menaikkan
-- saldo tanpa uang sungguhan adalah cara paling rapi menutupi selisih
-- laci.
drop policy if exists "balance_topups: write" on balance_topups;
create policy "balance_topups: write" on balance_topups
  for insert with check (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  );

-- Tidak ada kebijakan ubah maupun hapus. Setoran yang salah diperbaiki
-- dengan setoran koreksi, bukan dengan menghapus jejaknya — jurnalnya
-- hanya pernah ditambah, tidak pernah disunting.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Jurnalnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Satu baris: kredit GL Setoran Modal. Kredit berarti uang masuk, dan
-- akunnya sendiri yang membedakannya dari pendapatan penjualan.
--
-- Bukan dua baris. Sempat ditulis sebagai kredit GL Total Saldo
-- berpasangan debit GL Setoran Modal — dan pasangan yang saling
-- menghapus itu membuat setoran modal tidak menaikkan saldo sama
-- sekali, karena saldo dihitung dari selisih seluruh kredit dan debit.
--
-- Polanya mengikuti pendapatan langganan, yang juga satu baris kredit
-- ke akunnya sendiri. Yang berpasangan hanyalah perpindahan antar
-- kantong — dan setoran modal bukan perpindahan: uangnya datang dari
-- luar.

create or replace function log_balance_topup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_modal record;
  v_now timestamptz := now();
begin
  select * into v_modal from _gl_account_for(new.resto_id, 'capital');
  if v_modal.gl_code is null or v_modal.gl_code = '' then
    return new;
  end if;

  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    new.resto_id,
    (v_now at time zone 'Asia/Jakarta')::date,
    (v_now at time zone 'Asia/Jakarta')::time,
    v_modal.gl_code, v_modal.gl_name,
    'capital', new.id::text, new.amount, 'credit',
    'Setoran modal dari ' || new.source
  );

  return new;
end;
$$;

drop trigger if exists trg_log_balance_topup on balance_topups;
create trigger trg_log_balance_topup
  after insert on balance_topups
  for each row execute function log_balance_topup();

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select t.created_at, r.name, t.amount, t.source
--   from balance_topups t left join restaurants r on r.id = t.resto_id
--   order by t.created_at desc;
--
--   select gl_code, gl_name, entry_type, amount, description
--   from gl_journal_entries where reference_type = 'capital'
--   order by created_at desc limit 10;


-- ═══════════════════════════════════════════════════════════
-- 82. voucher_new_customer.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — voucher khusus pengguna baru.
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
-- belum pernah benar-benar memakai MerchantPOS, dan menutup pintu untuknya
-- justru menutup pintu bagi orang yang paling ingin dibujuk kembali.
--
-- Batasnya seluruh MerchantPOS, bukan per resto. Voucher ini promo MerchantPOS,
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
      'Voucher ini hanya untuk pengguna baru MerchantPOS';
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

  perform _jurnal_merchantpos('voucher', v_id, v.amount,
    'debit', 'Ditebus ' || v.code || ' — ' || v_email);
  perform _jurnal_merchantpos('voucher_redeem', v_id, v.amount,
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

  perform _jurnal_merchantpos('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_merchantpos('voucher', v_id, v_amount * p_quantity,
    'credit', 'Alokasi voucher ' || v_code);

  v_nilai := 'Rp ' || to_char(v_amount, 'FM999G999G999G999');

  -- Syaratnya disebutkan di pengumumannya, bukan disimpan sampai orang
  -- menekan Tebus. Ditolak sesudah bersemangat lebih menjengkelkan
  -- daripada tahu sejak awal bahwa ini bukan untuk dirinya.
  v_syarat := case
    when coalesce(p_new_customers_only, false)
      then ' Khusus pengguna baru yang belum pernah memesan lewat MerchantPOS.'
    else '' end;

  insert into app_announcements (
    title, body, category, audience, image_base64, created_by
  ) values (
    'Voucher ' || v_nilai || ' dari MerchantPOS',
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


-- ═══════════════════════════════════════════════════════════
-- 83. qris_receipt_fields.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — rincian kuitansi QRIS dari Xendit, jadi kolomnya sendiri.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Seluruh data ini sebenarnya sudah tersimpan sejak awal di kolom
-- `raw`, apa adanya dari Xendit. Tapi terkubur di dalam JSON ia tidak
-- bisa dicari, tidak bisa diurutkan, dan tidak bisa dicocokkan
-- baris-per-baris dengan mutasi di dashboard penyedia — dan itu persis
-- yang dibutuhkan saat ada satu pembayaran yang angkanya tidak cocok.
--
-- `raw` tetap disimpan dan tetap jadi sumber kebenarannya. Kolom di
-- bawah ini salinan yang dikeluarkan untuk dibaca; kalau suatu saat
-- Xendit mengganti nama medannya, yang hilang cuma salinannya.

begin;

-- ID Transaksi — pengenal pembayaran di sisi Xendit.
alter table payment_charges add column if not exists transaction_id text;

-- ID QR — pengenal QR yang dipindai.
alter table payment_charges add column if not exists qr_id text;

-- ID Product.
alter table payment_charges add column if not exists product_id text;

-- Mitra, dan nama partnernya.
alter table payment_charges add column if not exists partner_code text;
alter table payment_charges add column if not exists partner_name text;

-- ID Kuitansi Mitra — nomor struk di sisi mitra pembayaran.
alter table payment_charges add column if not exists partner_receipt_id text;

-- Sumber dana.
alter table payment_charges add column if not exists payment_source text;

-- ID Pengakuisisi.
alter table payment_charges add column if not exists acquirer_id text;

-- Customer PAN, dan merchant PAN pasangannya.
--
-- PAN pelanggan disimpan sebagaimana dikirim Xendit — sudah tersamar
-- di sisi mereka, dan yang sampai ke sini bukan nomor kartu utuh.
-- Kolomnya ikut aturan baca yang sama dengan seluruh baris ini:
-- pegawai resto yang bersangkutan dan Super Admin, bukan pelanggan.
alter table payment_charges add column if not exists customer_pan text;
alter table payment_charges add column if not exists merchant_pan text;

-- Status apa adanya dari penyedia, berikut kapan terakhir berubah.
--
-- Terpisah dari kolom `status` milik kita sendiri. Yang kita catat
-- hanya mengenal 'pending' dan 'paid' karena itu yang menentukan
-- pesanannya boleh jalan atau tidak; yang dikirim Xendit jauh lebih
-- banyak — ACTIVE, INACTIVE, EXPIRED, FAILED — dan menimpanya ke satu
-- kolom yang sama berarti kehilangan bedanya antara "belum dibayar"
-- dan "sudah gagal".
alter table payment_charges add column if not exists provider_status text;
alter table payment_charges
  add column if not exists provider_status_at timestamptz;

-- Sebabnya kalau gagal, apa adanya dari penyedia.
--
-- Disimpan supaya yang menanyakan besok pagi tidak perlu membuka log
-- fungsi edge — dan supaya pelanggan yang bilang "sudah saya bayar tapi
-- ditolak" bisa dijawab dengan sebab yang sebenarnya.
alter table payment_charges add column if not exists failure_reason text;

-- Dicari saat mencocokkan satu pembayaran dengan mutasi penyedia.
create index if not exists payment_charges_transaction_idx
  on payment_charges (transaction_id);
create index if not exists payment_charges_partner_receipt_idx
  on payment_charges (partner_receipt_id);

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Mengisinya dari yang sudah terlanjur tersimpan
-- ─────────────────────────────────────────────────────────────────────
--
-- Pembayaran yang sudah lewat tetap punya rinciannya di `raw`. Tanggal
-- berkas ini dijalankan bukan garis pemisah antara yang bisa dicocokkan
-- dan yang tidak.
--
-- Nama medannya dicari di dua tempat: badan callback Xendit membungkus
-- isinya di `data`, tapi sebagian versi mengirimnya rata di akar.

update payment_charges c
set provider_status    = coalesce(c.provider_status, d.d ->> 'status'),
    failure_reason     = coalesce(c.failure_reason,
                                  d.d ->> 'failure_code',
                                  d.d ->> 'failure_reason'),
    transaction_id     = coalesce(c.transaction_id, d.d ->> 'id'),
    qr_id              = coalesce(c.qr_id, d.d ->> 'qr_id'),
    product_id         = coalesce(c.product_id, d.d ->> 'product_id'),
    partner_code       = coalesce(c.partner_code, d.d ->> 'channel_code'),
    partner_name       = coalesce(c.partner_name, d.d ->> 'partner'),
    partner_receipt_id = coalesce(c.partner_receipt_id,
                                  d.pd ->> 'receipt_id'),
    payment_source     = coalesce(c.payment_source, d.pd ->> 'source'),
    acquirer_id        = coalesce(c.acquirer_id, d.pd ->> 'acquirer_id'),
    customer_pan       = coalesce(c.customer_pan, d.pd ->> 'customer_pan'),
    merchant_pan       = coalesce(c.merchant_pan, d.pd ->> 'merchant_pan')
from (
  select id,
         coalesce(raw -> 'data', raw) as d,
         coalesce(raw -> 'data' -> 'payment_detail',
                  raw -> 'payment_detail',
                  '{}'::jsonb) as pd
  from payment_charges
  where raw is not null
) as d(id, d, pd)
where c.id = d.id;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select created_at, status, provider_status, amount, transaction_id,
--          qr_id, partner_code, partner_receipt_id, payment_source,
--          acquirer_id, customer_pan, failure_reason
--   from payment_charges
--   order by created_at desc limit 20;
--
-- Yang masih menunggu dan yang gagal ikut tersimpan — status penyedia
-- di kolomnya sendiri, dan `status` milik kita baru berubah jadi 'paid'
-- saat uangnya benar-benar diterima.
--
-- Kolom yang kosong berarti Xendit memang tidak mengirim medan itu
-- untuk pembayaran tersebut — bukan berarti datanya hilang. Yang
-- sebenarnya dikirim selalu bisa dilihat utuh:
--
--   select raw from payment_charges where reference_id = '...';


-- ═══════════════════════════════════════════════════════════
-- 84. customer_display.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — layar pelanggan di meja kasir.
--
-- Jalankan kapan saja setelah payment_gateway.sql. Aman diulang.
--
-- Perangkat kedua menghadap pelanggan, menampilkan apa yang sedang
-- ditagih kasir: jumlah yang harus dibayar dan QR-nya.
--
-- Yang ditampilkan disebut di sini, satu baris per resto — bukan
-- ditebak dari "tagihan terakhir". Tebakan semacam itu meleset persis
-- saat paling ramai: dua kasir melayani berbarengan, dan layar depan
-- menampilkan tagihan orang yang mengantre di belakang.
--
-- Barisnya membawa isi tampilannya, bukan penunjuk ke pesanan.
--
-- Rancangan pertamanya menunjuk ke `orders.id` supaya tidak ada angka
-- yang tersalin dua kali. Itu tidak bisa: di alur kasir, pesanannya
-- baru dibuat sesudah pembayaran dikonfirmasi — saat QR-nya tampil,
-- belum ada baris pesanan untuk ditunjuk sama sekali.
--
-- Salinan angkanya aman di sini karena baris ini bukan catatan uang.
-- Ia tampilan sesaat yang ditimpa tiap transaksi dan dikosongkan sesudah
-- selesai; yang dipakai membukukan tetap pesanan dan payment_charges.

begin;

create table if not exists customer_displays (
  resto_id text primary key references restaurants (id) on delete cascade,

  -- 'idle'     — tidak ada yang ditagih
  -- 'awaiting' — menunggu pelanggan membayar
  -- 'paid'     — lunas, tampil sebentar sebagai konfirmasi
  status text not null default 'idle'
    check (status in ('idle', 'awaiting', 'paid')),

  amount bigint,
  qr_string text,

  -- Keterangan singkat: nomor meja, nama pelanggan, atau nomor pesanan
  -- kalau sudah ada.
  label text,

  updated_by text,
  updated_at timestamptz not null default now()
);

alter table customer_displays enable row level security;

-- Dibaca dan ditulis pegawai resto yang bersangkutan.
--
-- Perangkat layar depan masuk dengan akun pegawai resto itu juga.
-- Membiarkannya terbuka untuk umum berarti siapa pun bisa memantau
-- tagihan yang sedang berjalan di resto mana pun — termasuk isi QR-nya,
-- yang bisa dipindai orang lain sebelum pelanggannya sempat.
drop policy if exists "customer_displays: staff read" on customer_displays;
create policy "customer_displays: staff read" on customer_displays
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'kasir', 'finance'])
  );

drop policy if exists "customer_displays: staff write" on customer_displays;
create policy "customer_displays: staff write" on customer_displays
  for all using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'kasir'])
  ) with check (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'kasir'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Menyalakan dan memadamkannya
-- ─────────────────────────────────────────────────────────────────────
--
-- Satu pernyataan, supaya dua kasir yang menekan Bayar hampir bersamaan
-- tidak meninggalkan baris ganda — yang menekan belakangan yang tampil,
-- dan itu memang yang sedang berdiri di depan mesinnya.

create or replace function set_customer_display(
  p_resto_id text,
  p_status text,
  p_amount bigint default null,
  p_qr_string text default null,
  p_label text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'admin', 'kasir'])) then
    raise exception 'Tidak berwenang atas layar merchant ini';
  end if;

  insert into customer_displays (
    resto_id, status, amount, qr_string, label, updated_by, updated_at
  ) values (
    p_resto_id, coalesce(p_status, 'idle'), p_amount, p_qr_string, p_label,
    auth.jwt() ->> 'email', now()
  )
  on conflict (resto_id) do update
    set status = excluded.status,
        amount = excluded.amount,
        qr_string = excluded.qr_string,
        label = excluded.label,
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$$;

revoke all on function set_customer_display(text, text, bigint, text, text)
  from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- Supaya perubahannya sampai seketika
-- ─────────────────────────────────────────────────────────────────────
--
-- Tanpa ini layarnya baru berubah saat dimuat ulang — dan tidak ada
-- yang memuat ulang layar yang menghadap pelanggan.
--
-- Dibungkus penangkap galat, bukan sekadar diberi catatan "abaikan
-- kalau gagal". Menjalankan ulang berkas ini adalah hal biasa, dan
-- galat di sini menghentikan sisa bagiannya — jadi catatan yang
-- menyuruh mengabaikannya justru menyuruh mengabaikan sesuatu yang
-- sudah terlanjur merusak jalannya.
do $$
begin
  alter publication supabase_realtime add table customer_displays;
exception when duplicate_object then null;
end $$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select d.resto_id, r.name, d.status, d.amount, d.label,
--          d.updated_by, d.updated_at
--   from customer_displays d left join restaurants r on r.id = d.resto_id;


-- ═══════════════════════════════════════════════════════════
-- 85. order_number.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — nomor pesanan harian per resto.
--
-- Jalankan kapan saja setelah schema.sql. Aman dijalankan berulang.
--
-- Sampai sekarang pesanan hanya punya UUID. Itu cukup untuk mesin, tapi
-- tidak untuk orang: kasir tidak bisa memanggil "pesanan
-- 8f3a1c2e-..." ke ruangan, dan pelanggan tidak bisa mengingatnya
-- sampai makanannya datang.
--
-- Nomornya dimulai dari 1 tiap hari, dan berdiri sendiri di tiap resto.
-- Angka yang terus bertambah selamanya jadi empat digit dalam sebulan
-- dan berhenti bisa diteriakkan; angka yang dibagi antar resto membuat
-- resto kedua mulai dari nomor yang tidak pernah dia pakai.
--
-- Harinya memakai waktu Jakarta, sama dengan seluruh pembukuan di sini.
-- Memakai UTC berarti nomornya berganti pukul tujuh pagi — di tengah
-- persiapan buka, bukan di antara dua hari kerja.

begin;

alter table orders add column if not exists order_no integer;

-- Tanggal yang dipakai menghitungnya, disimpan supaya nomor lama tetap
-- bisa dibaca artinya tanpa menghitung ulang zona waktunya.
alter table orders add column if not exists order_date date;

-- Nomor yang sama tidak boleh terbit dua kali di resto dan hari yang
-- sama. Ini batasan basis data, bukan pemeriksaan di kode: dua pesanan
-- yang masuk di detik yang sama adalah keadaan biasa saat ramai, dan
-- justru saat ramai itulah nomor kembar paling merepotkan.
create unique index if not exists orders_no_harian_idx
  on orders (resto_id, order_date, order_no)
  where order_no is not null;

-- Pencacahnya. Satu baris per resto per hari.
create table if not exists order_counters (
  resto_id text not null references restaurants (id) on delete cascade,
  order_date date not null,
  last_no integer not null default 0,
  primary key (resto_id, order_date)
);

alter table order_counters enable row level security;
-- Tidak ada kebijakan untuk siapa pun. Yang menyentuhnya hanya pemicu
-- di bawah, yang berjalan SECURITY DEFINER. Tangan yang bisa mengubah
-- pencacah ini adalah tangan yang bisa membuat dua pesanan bernomor
-- sama.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pemberian nomornya
-- ─────────────────────────────────────────────────────────────────────
--
-- Diberikan saat pesanannya dibuat, apa pun status bayarnya. Pelanggan
-- yang masih menunggu QRIS-nya sudah memegang nomor, dan itu memang
-- yang dia butuhkan: nomor itulah yang disebut kasir kalau QRIS-nya
-- gagal dan dia beralih membayar tunai.
--
-- Nomornya tidak ditarik kembali kalau pesanannya batal. Nomor yang
-- dipakai ulang berarti dua struk berbeda menyebut angka yang sama di
-- hari yang sama — dan yang menemukannya adalah orang yang mengambil
-- pesanan orang lain.

create or replace function assign_order_no()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tanggal date := (coalesce(new.created_at, now()) at time zone 'Asia/Jakarta')::date;
  v_no integer;
begin
  if new.order_no is not null then
    return new;
  end if;

  -- Satu pernyataan, dan pertambahannya terjadi di dalam basis data.
  -- Membacanya dulu lalu menambah satu di aplikasi berarti dua pesanan
  -- yang datang bersamaan sama-sama membaca angka yang sama.
  insert into order_counters (resto_id, order_date, last_no)
  values (new.resto_id, v_tanggal, 1)
  on conflict (resto_id, order_date)
  do update set last_no = order_counters.last_no + 1
  returning last_no into v_no;

  new.order_no := v_no;
  new.order_date := v_tanggal;
  return new;
end;
$$;

drop trigger if exists trg_assign_order_no on orders;
create trigger trg_assign_order_no
  before insert on orders
  for each row execute function assign_order_no();

-- ─────────────────────────────────────────────────────────────────────
-- Pesanan yang sudah terlanjur ada
-- ─────────────────────────────────────────────────────────────────────
--
-- Diberi nomor menurut urutan waktunya, per resto per hari — supaya
-- riwayat lama tidak jadi satu-satunya bagian yang kosong nomornya.
-- Pencacahnya ikut disetel ke angka terakhir tiap hari, supaya pesanan
-- berikutnya di hari yang sama tidak menabrak nomor yang sudah dipakai.

with bernomor as (
  select id,
         resto_id,
         (created_at at time zone 'Asia/Jakarta')::date as tgl,
         row_number() over (
           partition by resto_id, (created_at at time zone 'Asia/Jakarta')::date
           order by created_at, id
         ) as no
  from orders
  where order_no is null
)
update orders o
set order_no = b.no, order_date = b.tgl
from bernomor b
where o.id = b.id;

insert into order_counters (resto_id, order_date, last_no)
select resto_id, order_date, max(order_no)
from orders
where order_no is not null and order_date is not null
group by resto_id, order_date
on conflict (resto_id, order_date)
do update set last_no = greatest(order_counters.last_no, excluded.last_no);

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select order_date, resto_id, order_no, payment_status, total
--   from orders order by created_at desc limit 20;
--
-- Tidak boleh ada yang kembar:
--
--   select resto_id, order_date, order_no, count(*)
--   from orders where order_no is not null
--   group by 1, 2, 3 having count(*) > 1;


-- ═══════════════════════════════════════════════════════════
-- 86. resto_facilities.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — fasilitas merchant.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Yang membuat orang memilih satu tempat dibanding tempat lain sering
-- bukan menunya: ada AC atau tidak, boleh merokok atau tidak, aman untuk
-- anak atau tidak. Selama ini tidak ada tempat menuliskannya, jadi
-- pelanggan baru tahu setelah sampai — dan yang salah pilih tidak
-- kembali.

begin;

-- Daftar bebas, bukan pilihan tetap.
--
-- Sempat terpikir membuat tabel acuan berisi nama fasilitas yang boleh
-- dipakai. Itu berarti tiap kali ada merchant yang punya sesuatu yang
-- belum terdaftar — mushola, colokan di tiap meja, parkir luas — dia
-- harus menunggu daftarnya ditambah orang lain. Daftar yang menghambat
-- pemiliknya menggambarkan tempatnya sendiri lebih buruk daripada
-- daftar yang sesekali salah ketik.
alter table restaurants
  add column if not exists facilities jsonb not null default '[]'::jsonb;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Catatan
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang boleh mengubahnya sudah diatur kebijakan `restaurants` yang ada:
-- Super Admin, dan Admin/Owner merchant itu sendiri. Tidak ada kebijakan
-- baru di sini — menambahnya justru berisiko melonggarkan yang sudah
-- ketat, karena kebijakan permisif saling di-OR.
--
-- Memeriksanya:
--
--   select name, facilities from restaurants where jsonb_array_length(facilities) > 0;


-- ═══════════════════════════════════════════════════════════
-- 87. merchant_reviews.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — penilaian merchant oleh pelanggan, dan jam bukanya.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Dua hal yang paling sering menentukan orang jadi datang atau tidak,
-- dan keduanya belum punya tempat: apa kata orang yang sudah ke sana,
-- dan apakah tempatnya sedang buka.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Jam buka
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan sebagai satu objek per merchant, bukan tujuh baris tabel
-- terpisah. Yang dibaca dan ditulis selalu tujuh-tujuhnya sekaligus —
-- tidak ada satu pun layar yang menanyakan "jam buka hari Rabu saja".
--
-- Bentuknya: {"1": {"buka":"08:00","tutup":"22:00"}, ...} dengan 1 =
-- Senin sampai 7 = Minggu, mengikuti penomoran ISO. Hari yang tidak ada
-- kuncinya berarti tutup — itu lebih jujur daripada menyimpan
-- "00:00-00:00" yang bisa terbaca sebagai buka 24 jam.
alter table restaurants
  add column if not exists opening_hours jsonb not null default '{}'::jsonb;

-- ─────────────────────────────────────────────────────────────────────
-- Penilaian
-- ─────────────────────────────────────────────────────────────────────

create table if not exists merchant_reviews (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  -- Email pelanggan. Penilaian menempel pada orang, bukan pada
  -- perangkat: yang menilai di HP lama harus tetap menemukannya di HP
  -- baru, dan yang membacanya berhak tahu itu orang yang berbeda-beda.
  customer_email text not null,

  -- Namanya disalin saat menilai, tidak dibaca ulang dari profilnya.
  -- Profil bisa berganti nama besok; ulasan yang tiba-tiba berganti
  -- penulis adalah ulasan yang tidak bisa dipercaya.
  customer_name text not null,

  rating smallint not null check (rating between 1 and 5),
  comment text,

  -- Foto, base64, paling banyak tiga. Disimpan di kolom seperti banner
  -- dan foto menu — satu ulasan tetap satu baris.
  photos jsonb not null default '[]'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Satu orang satu penilaian per merchant. Yang berubah pikiran
  -- mengubah penilaiannya, bukan menambah yang kedua — tanpa ini, satu
  -- orang yang kecewa bisa menenggelamkan rata-ratanya sendirian.
  unique (resto_id, customer_email)
);

create index if not exists merchant_reviews_resto_idx
  on merchant_reviews (resto_id, created_at desc);

alter table merchant_reviews enable row level security;

-- Dibaca siapa saja, termasuk tamu.
--
-- Ulasan memang untuk dibaca sebelum memutuskan, dan yang paling
-- membutuhkannya justru orang yang belum punya akun.
drop policy if exists "merchant_reviews: public read" on merchant_reviews;
create policy "merchant_reviews: public read" on merchant_reviews
  for select using (true);

-- Ditulis hanya oleh pemiliknya sendiri, dan hanya kalau sudah masuk.
drop policy if exists "merchant_reviews: own write" on merchant_reviews;
create policy "merchant_reviews: own write" on merchant_reviews
  for all using (customer_email = auth.jwt() ->> 'email')
  with check (customer_email = auth.jwt() ->> 'email');

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Rata-rata dan jumlahnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Dihitung server, bukan diunduh seluruh ulasannya lalu dijumlahkan di
-- HP. Daftar merchant menampilkan puluhan baris sekaligus; mengunduh
-- seluruh ulasan tiap merchant untuk satu angka bintang berarti layar
-- pilih merchant menarik ribuan baris tiap kali dibuka.

create or replace function merchant_rating_summary()
returns table (resto_id text, rata numeric, jumlah bigint)
language sql
stable
as $$
  select r.resto_id,
         round(avg(r.rating)::numeric, 1),
         count(*)
  from merchant_reviews r
  group by r.resto_id;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from merchant_rating_summary();
--
--   select m.name, r.customer_name, r.rating, r.comment, r.created_at
--   from merchant_reviews r join restaurants m on m.id = r.resto_id
--   order by r.created_at desc limit 20;


-- ═══════════════════════════════════════════════════════════
-- 88. review_prompt.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — mengajak pelanggan menilai, sejam sesudah membayar.
--
-- Jalankan SETELAH merchant_reviews.sql. Aman diulang.
--
-- Sejam, bukan seketika. Yang baru saja membayar biasanya sedang makan
-- atau sedang berjalan keluar — ajakan menilai di detik itu ditutup
-- tanpa dibaca. Sejam kemudian, makanannya sudah dicoba dan
-- pendapatnya sudah terbentuk.
--
-- Dan tidak lebih dari tiga jam: ajakan yang datang esok hari menanyakan
-- sesuatu yang sudah kabur, dan jawabannya jadi asal.

begin;

-- Yang sudah pernah diajak, supaya tidak diajak dua kali.
--
-- Barisnya per pesanan, bukan per merchant: orang yang makan di tempat
-- yang sama minggu depan boleh diajak lagi, karena kunjungannya memang
-- berbeda. Yang tidak boleh adalah satu kunjungan diajak berulang kali
-- tiap penjadwal berjalan.
create table if not exists review_prompts (
  order_id uuid primary key references orders (id) on delete cascade,
  sent_at timestamptz not null default now()
);

alter table review_prompts enable row level security;
-- Tidak ada kebijakan untuk siapa pun: yang menulisnya hanya penjadwal
-- di bawah, yang berjalan SECURITY DEFINER.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Penjadwalnya
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_review_prompts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  o record;
begin
  for o in
    select distinct on (ord.customer_label, ord.resto_id)
           ord.id, ord.customer_label, ord.resto_id, r.name as merchant
    from orders ord
    join restaurants r on r.id = ord.resto_id
    where ord.payment_status = 'paid'
      and ord.created_at < now() - interval '1 hour'
      and ord.created_at > now() - interval '3 hours'
      -- Hanya akun terdaftar. Pesanan kasir memakai nama tamu yang
      -- diketik di tempat; tidak ada perangkat yang bisa dituju.
      and exists (select 1 from customers c where c.email = ord.customer_label)
      -- Yang sudah menilai tempat ini tidak diajak lagi.
      and not exists (
        select 1 from merchant_reviews mr
        where mr.resto_id = ord.resto_id
          and mr.customer_email = ord.customer_label
      )
      and not exists (
        select 1 from review_prompts p where p.order_id = ord.id
      )
    order by ord.customer_label, ord.resto_id, ord.created_at desc
  loop
    insert into push_outbox (resto_id, event, payload) values (
      o.resto_id, 'review_prompt',
      jsonb_build_object(
        'audience', 'email',
        'email', o.customer_label,
        'resto_id', o.resto_id,
        'title', 'Gimana pesanan kamu di ' || o.merchant || '?',
        'body', 'Bikin nagih ga nih? Jangan lupa kasih ulasan untuk ' ||
                o.merchant || ' di MerchantPOS.'
      )
    );

    insert into review_prompts (order_id) values (o.id)
    on conflict (order_id) do nothing;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function queue_review_prompts() from public, anon, authenticated;

-- Tiap 20 menit. Ketepatan menitnya tidak penting di sini — yang
-- penting ajakannya datang saat makanannya masih diingat, dan rentang
-- satu sampai tiga jam sudah menjamin itu.
select cron.unschedule('review-prompts')
where exists (select 1 from cron.job where jobname = 'review-prompts');

select cron.schedule('review-prompts', '*/20 * * * *',
  $cron$select queue_review_prompts();$cron$);

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from review_prompts order by sent_at desc limit 10;
--
--   select event, payload ->> 'email', payload ->> 'title', created_at
--   from push_outbox where event = 'review_prompt'
--   order by created_at desc limit 10;


-- ═══════════════════════════════════════════════════════════
-- 89. order_cancel_kitchen.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pesanan yang batal berhenti punya status dapur.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Sampai sekarang `kitchen_status` berhenti di nilai terakhirnya saat
-- pesanannya dibatalkan. Datanya jadi berbunyi "sedang dimasak" untuk
-- pesanan yang sudah tidak akan pernah dimasak — dan tiap layar yang
-- membacanya harus ingat sendiri untuk mengabaikannya. Yang lupa
-- mengingat itu menampilkan "Sedang Dimasak" ke pelanggan yang
-- pesanannya sudah batal.
--
-- Lebih baik keadaannya ditulis apa adanya di datanya, sekali, daripada
-- diperbaiki berulang kali di tiap layar yang menampilkannya.

begin;

alter table orders drop constraint if exists orders_kitchen_status_check;
alter table orders add constraint orders_kitchen_status_check
  check (kitchen_status in ('waiting', 'onProgress', 'done', 'cancelled'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pemicunya
-- ─────────────────────────────────────────────────────────────────────
--
-- Berjalan saat status bayarnya berubah jadi batal atau hangus.
-- Keduanya berarti sama bagi dapur: makanannya tidak jadi dibuat.
--
-- Yang sudah 'done' tidak diubah. Pesanan yang sudah matang lalu
-- dibatalkan tetap pernah dimasak, dan menghapus jejak itu membuat
-- dapur kehilangan satu-satunya catatan bahwa bahannya sudah terpakai.

create or replace function sync_kitchen_on_cancel()
returns trigger
language plpgsql
as $$
begin
  if new.payment_status in ('cancelled', 'expired')
     and old.payment_status is distinct from new.payment_status
     and new.kitchen_status <> 'done' then
    new.kitchen_status := 'cancelled';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_kitchen_on_cancel on orders;
create trigger trg_sync_kitchen_on_cancel
  before update on orders
  for each row execute function sync_kitchen_on_cancel();

-- ─────────────────────────────────────────────────────────────────────
-- Yang sudah terlanjur tersimpan
-- ─────────────────────────────────────────────────────────────────────
--
-- Pesanan lama yang batal masih membawa status dapur yang tidak berlaku.
-- Tanggal berkas ini dijalankan bukan garis pemisah antara data yang
-- benar dan yang menyesatkan.

update orders
set kitchen_status = 'cancelled'
where payment_status in ('cancelled', 'expired')
  and kitchen_status in ('waiting', 'onProgress');

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
-- Tidak boleh ada yang tersisa:
--
--   select id, payment_status, kitchen_status from orders
--   where payment_status in ('cancelled', 'expired')
--     and kitchen_status in ('waiting', 'onProgress');
--
--   select kitchen_status, count(*) from orders group by 1;


-- ═══════════════════════════════════════════════════════════
-- 90. cashier_shift.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — buka dan tutup shift kasir.
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


-- ═══════════════════════════════════════════════════════════
-- 91. product_badges_reviews.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — label menu, penilaian menu, dan angka terjualnya.
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


-- ═══════════════════════════════════════════════════════════
-- 92. product_review_per_order.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — penilaian menu menempel pada pesanannya, bukan pada menunya.
--
-- Jalankan SETELAH product_badges_reviews.sql. Aman diulang.
--
-- Semula satu orang hanya boleh menilai sebuah menu satu kali. Terdengar
-- benar — sampai orang yang sama memesan nasi goreng untuk kedua
-- kalinya, membuka formulirnya, dan menemukan bintang lima dari bulan
-- lalu sudah terisi di sana. Yang mau bilang "kali ini keasinan" tidak
-- punya tempat untuk mengatakannya, dan yang membaca ulasannya tidak
-- pernah tahu menunya sudah berubah.
--
-- Satu pesanan satu penilaian. Yang memesan sepuluh kali punya sepuluh
-- kesempatan bicara, dan tiap-tiapnya menilai masakan hari itu saja.

begin;

alter table product_reviews
  add column if not exists order_id uuid references orders (id) on delete cascade;

-- Kunci lamanya dilepas. Selama ia masih ada, pesanan kedua atas menu
-- yang sama akan ditolak basis data — persis keluhan yang mau
-- diperbaiki.
alter table product_reviews
  drop constraint if exists product_reviews_product_id_customer_email_key;

-- Penggantinya dua indeks, dan itu bukan kelebihan.
--
-- Yang pertama harus berupa indeks atas KOLOMNYA LANGSUNG, bukan atas
-- ekspresi. `on conflict (order_id, product_id, customer_email)` —
-- yang dipakai aplikasi untuk menimpa penilaiannya sendiri — hanya mau
-- memakai indeks yang kolomnya persis sama. Indeks atas
-- `coalesce(order_id::text,'')` ditolak dengan galat 42P10 "there is no
-- unique or exclusion constraint matching the ON CONFLICT
-- specification", dan galatnya baru muncul saat orangnya menekan
-- Simpan.
drop index if exists product_reviews_per_order;

create unique index if not exists product_reviews_order_menu_orang
  on product_reviews (order_id, product_id, customer_email);

-- Yang kedua menjaga baris lama. Di dalam indeks unik, dua NULL dianggap
-- berbeda — tanpa ini, baris yang ditulis sebelum penilaian menempel
-- pada pesanan bisa berlipat ganda tanpa ketahuan. Aturan lamanya
-- ditegakkan apa adanya: satu per menu per orang, seperti yang memang
-- berlaku saat baris itu ditulis.
create unique index if not exists product_reviews_lama_satu_per_menu
  on product_reviews (product_id, customer_email)
  where order_id is null;

create index if not exists product_reviews_order_idx
  on product_reviews (order_id);

-- Aturan menulisnya ikut menyempit: bukan lagi "pernah memesan menu ini
-- di suatu tempat", melainkan "menu ini ada di pesanan ITU, dan pesanan
-- itu miliknya, dan sudah lunas".
--
-- Tanpa penyempitan ini, satu pesanan lunas berisi nasi goreng sudah
-- cukup untuk menulis penilaian sebanyak-banyaknya atas nama pesanan
-- lain mana pun.
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
        -- Baris lama tanpa order_id tetap boleh disunting pemiliknya.
        and (product_reviews.order_id is null
             or o.id = product_reviews.order_id)
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   -- Penilaian yang sudah masuk, berikut pesanannya:
--   select r.created_at, r.customer_email, p.name, r.rating, r.comment,
--          r.order_id
--   from product_reviews r
--   join products p on p.id = r.product_id
--   order by r.created_at desc limit 20;
--
--   -- Ringkasan yang dibaca kartu menu:
--   select * from product_stats('<resto_id>');


-- ═══════════════════════════════════════════════════════════
-- 93. cash_variance.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — GL Selisih Kasir, dan pelunasannya.
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
-- Ditulis pemicu, bukan oleh `close_shift`. Seluruh jurnal di MerchantPOS
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


-- ═══════════════════════════════════════════════════════════
-- 94. merchant_report.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — laporan penjualan untuk merchant sendiri.
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


-- ═══════════════════════════════════════════════════════════
-- 95. shift_opening_check.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — perkiraan modal awal saat shift dibuka.
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


-- ═══════════════════════════════════════════════════════════
-- 96. support_tickets.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pengaduan, tiket, dan percakapannya.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Selama ini satu-satunya jalan mengadu adalah WhatsApp ke nomor
-- MerchantPOS Admin. Itu bekerja saat merchantnya lima. Pada merchant
-- kelima puluh, tidak ada yang tahu keluhan mana yang sudah dijawab,
-- mana yang tenggelam di bawah percakapan lain, dan mana yang sebenarnya
-- masalah yang sama muncul untuk ketiga kalinya.
--
-- Tiket menjawab tiga hal yang tidak bisa dijawab gulungan obrolan:
-- keluhan ini sudah selesai atau belum, siapa yang sedang menunggu siapa,
-- dan sudah berapa lama.

begin;

create table if not exists support_tickets (
  id uuid primary key default gen_random_uuid(),

  -- Yang mengadu. Emailnya kunci — bukan perangkatnya: yang mengadu dari
  -- HP lama harus menemukan tiketnya di HP baru.
  reporter_email text not null,
  reporter_name text,

  -- 'customer' atau 'merchant'. Bukan sekadar catatan: keduanya datang
  -- dengan masalah yang berbeda, dan admin yang tahu ini sebelum membuka
  -- percakapannya menjawab lebih cepat.
  reporter_kind text not null default 'customer'
    check (reporter_kind in ('customer', 'merchant')),

  -- Diisi kalau yang mengadu pegawai merchant.
  resto_id text references restaurants (id) on delete set null,

  subject text not null,

  -- open           — masuk, belum disentuh admin
  -- on_progress    — admin sedang menanganinya
  -- confirm_customer — admin sudah menjawab, giliran pengadu menanggapi
  -- closed         — selesai
  status text not null default 'open'
    check (status in ('open', 'on_progress', 'confirm_customer', 'closed')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Pesan terakhir, untuk mengurutkan daftar tanpa membaca seluruh
  -- percakapan tiap tiket.
  last_message_at timestamptz,
  last_message_body text,
  last_message_from_admin boolean not null default false,

  -- Kapan tiap pihak terakhir membuka percakapannya. Penanda belum
  -- dibaca dihitung dari sini, bukan dari bendera per pesan: satu
  -- stempel waktu tidak bisa berbeda pendapat dengan dirinya sendiri.
  reporter_read_at timestamptz,
  admin_read_at timestamptz,

  closed_at timestamptz,
  closed_by text,

  -- Ditutup sendiri karena pengadunya tidak menanggapi. Dibedakan dari
  -- yang ditutup orang: tiket yang mati karena didiamkan bukan tiket
  -- yang selesai, dan yang membaca laporannya nanti berhak tahu bedanya.
  auto_closed boolean not null default false
);

create index if not exists support_tickets_reporter_idx
  on support_tickets (reporter_email, created_at desc);
create index if not exists support_tickets_status_idx
  on support_tickets (status, last_message_at desc);

create table if not exists support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support_tickets (id) on delete cascade,

  sender_email text not null,
  sender_name text,

  -- Siapa yang bicara. Disimpan, bukan disimpulkan dari emailnya saat
  -- dibaca: orang bisa berhenti jadi admin, dan percakapan lama tidak
  -- boleh berubah artinya karenanya.
  from_admin boolean not null default false,

  body text not null,

  -- Tangkapan layar keluhan, base64. Satu saja — pengaduan yang butuh
  -- lima gambar sebenarnya butuh percakapan, dan itu sudah tersedia di
  -- sini.
  photo_base64 text,

  -- Ditulis sistem, bukan orang: "Tiket ditutup otomatis", "Status
  -- diubah jadi Sedang Diproses". Ditandai supaya bisa ditampilkan
  -- berbeda dan tidak terbaca seolah admin yang mengetiknya.
  is_system boolean not null default false,

  created_at timestamptz not null default now()
);

create index if not exists support_messages_ticket_idx
  on support_messages (ticket_id, created_at);

alter table support_tickets enable row level security;
alter table support_messages enable row level security;

-- Pengadu melihat tiketnya sendiri; MerchantPOS Admin melihat semuanya.
--
-- Pegawai merchant lain TIDAK melihat pengaduan rekannya. Keluhan
-- sering berisi hal yang tidak ingin dibaca seruangan — termasuk
-- keluhan tentang orang di ruangan itu.
drop policy if exists "support_tickets: read" on support_tickets;
create policy "support_tickets: read" on support_tickets
  for select using (
    is_super_admin() or reporter_email = auth.jwt() ->> 'email'
  );

drop policy if exists "support_tickets: reporter insert" on support_tickets;
create policy "support_tickets: reporter insert" on support_tickets
  for insert with check (reporter_email = auth.jwt() ->> 'email');

-- Sengaja tidak ada policy update. Status dan penanda baca diubah lewat
-- fungsi di bawah — kalau barisnya bisa disunting langsung, pengadu bisa
-- menutup tiket atas nama admin, atau sebaliknya.

drop policy if exists "support_messages: read" on support_messages;
create policy "support_messages: read" on support_messages
  for select using (
    exists (
      select 1 from support_tickets t
      where t.id = support_messages.ticket_id
        and (is_super_admin() or t.reporter_email = auth.jwt() ->> 'email')
    )
  );

-- Menulis hanya ke tiket sendiri, dan hanya selama tiketnya belum
-- ditutup. Tiket tertutup yang masih bisa ditulisi adalah tiket yang
-- tidak pernah benar-benar selesai.
drop policy if exists "support_messages: write" on support_messages;
create policy "support_messages: write" on support_messages
  for insert with check (
    sender_email = auth.jwt() ->> 'email'
    and is_system = false
    and exists (
      select 1 from support_tickets t
      where t.id = support_messages.ticket_id
        and t.status <> 'closed'
        and (is_super_admin() or t.reporter_email = auth.jwt() ->> 'email')
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Realtime
-- ─────────────────────────────────────────────────────────────────────
--
-- Dibungkus penangkap galat: `add table` gagal kalau tabelnya sudah
-- terdaftar, dan galatnya menghentikan sisa bagiannya.
do $$ begin
  alter publication supabase_realtime add table support_messages;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table support_tickets;
exception when duplicate_object then null;
end $$;

-- ─────────────────────────────────────────────────────────────────────
-- Ringkasan tiket ikut pesan terakhirnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Ditulis pemicu supaya tidak pernah ada jalan mengirim pesan tanpa
-- daftar tiketnya ikut bergerak. Daftar yang urutannya bergantung pada
-- aplikasi yang ingat memperbaruinya adalah daftar yang cepat atau
-- lambat menampilkan tiket mati di paling atas.
create or replace function touch_support_ticket()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update support_tickets
     set last_message_at = new.created_at,
         last_message_body = left(new.body, 160),
         last_message_from_admin = new.from_admin,
         updated_at = new.created_at,
         -- Pesan dari pengadu membangunkan tiket yang sedang menunggu
         -- jawabannya. Tanpa ini, tiket yang baru saja dijawab pengadu
         -- tetap berstatus "menunggu pengadu" — lalu ditutup sendiri
         -- oleh penjadwal, tepat setelah orangnya membalas.
         status = case
           when status = 'confirm_customer' and new.from_admin = false
             then 'on_progress'
           else status
         end
   where id = new.ticket_id;
  return new;
end;
$$;

drop trigger if exists trg_touch_support_ticket on support_messages;
create trigger trg_touch_support_ticket
  after insert on support_messages
  for each row execute function touch_support_ticket();

-- ─────────────────────────────────────────────────────────────────────
-- Membuat tiket
-- ─────────────────────────────────────────────────────────────────────

create or replace function open_support_ticket(
  p_subject text,
  p_body text,
  p_kind text default 'customer',
  p_resto_id text default null,
  p_name text default null,
  p_photo text default null)
returns support_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row support_tickets;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu untuk membuat pengaduan.';
  end if;
  if btrim(coalesce(p_subject, '')) = '' then
    raise exception 'Judul pengaduannya belum diisi.';
  end if;
  if btrim(coalesce(p_body, '')) = '' then
    raise exception 'Ceritakan dulu keluhannya.';
  end if;

  insert into support_tickets (
    reporter_email, reporter_name, reporter_kind, resto_id, subject,
    reporter_read_at)
  values (
    v_email, p_name,
    case when p_kind = 'merchant' then 'merchant' else 'customer' end,
    p_resto_id, btrim(p_subject), now())
  returning * into v_row;

  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body, photo_base64)
  values (v_row.id, v_email, p_name, false, btrim(p_body), p_photo);

  select * into v_row from support_tickets where id = v_row.id;
  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Mengubah status
-- ─────────────────────────────────────────────────────────────────────
--
-- Admin boleh ke status mana pun. Pengadu hanya boleh menutup — dan itu
-- memang haknya: yang paling tahu keluhannya sudah selesai adalah orang
-- yang mengeluh.
create or replace function set_support_status(p_id uuid, p_status text)
returns support_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_admin boolean := is_super_admin();
  v_row support_tickets;
  v_label text;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  select * into v_row from support_tickets where id = p_id;
  if v_row is null then
    raise exception 'Tiketnya tidak ditemukan.';
  end if;

  if not v_admin and v_row.reporter_email <> v_email then
    raise exception 'Tiket ini bukan milikmu.';
  end if;

  if not v_admin and p_status <> 'closed' then
    raise exception 'Hanya MerchantPOS Admin yang bisa mengubah status ini.';
  end if;

  if p_status not in ('open', 'on_progress', 'confirm_customer', 'closed') then
    raise exception 'Status tidak dikenal.';
  end if;

  if v_row.status = p_status then
    return v_row;
  end if;

  v_label := case p_status
    when 'open' then 'Dibuka'
    when 'on_progress' then 'Sedang Diproses'
    when 'confirm_customer' then 'Menunggu Konfirmasi Pelapor'
    else 'Selesai'
  end;

  update support_tickets
     set status = p_status,
         updated_at = now(),
         closed_at = case when p_status = 'closed' then now() else null end,
         closed_by = case when p_status = 'closed' then v_email else null end,
         auto_closed = false
   where id = p_id
  returning * into v_row;

  -- Perubahan status ikut jadi pesan di percakapannya.
  --
  -- Status yang cuma berubah di kepala tabel tidak pernah terbaca orang
  -- yang sedang membuka percakapannya — dan justru itu satu-satunya
  -- layar yang dia buka.
  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body, is_system)
  values (p_id, v_email, null, v_admin, 'Status diubah jadi ' || v_label, true);

  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Penanda sudah dibaca
-- ─────────────────────────────────────────────────────────────────────

create or replace function mark_support_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then return; end if;

  if is_super_admin() then
    update support_tickets set admin_read_at = now() where id = p_id;
  else
    update support_tickets set reporter_read_at = now()
     where id = p_id and reporter_email = v_email;
  end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menutup sendiri tiket yang didiamkan
-- ─────────────────────────────────────────────────────────────────────
--
-- Hanya tiket yang sedang menunggu jawaban pengadunya, dan hanya kalau
-- pesan terakhirnya memang dari admin. Tiket yang pesan terakhirnya dari
-- pengadu berarti bolanya ada di MerchantPOS — menutupnya karena "tidak ada
-- jawaban" akan menghukum orang yang justru sudah menjawab.
create or replace function close_idle_support_tickets()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jumlah integer := 0;
  t record;
begin
  for t in
    select id from support_tickets
    where status = 'confirm_customer'
      and last_message_from_admin = true
      and coalesce(last_message_at, updated_at) < now() - interval '24 hours'
  loop
    update support_tickets
       set status = 'closed',
           closed_at = now(),
           closed_by = null,
           auto_closed = true,
           updated_at = now()
     where id = t.id;

    insert into support_messages (
      ticket_id, sender_email, sender_name, from_admin, body, is_system)
    values (t.id, 'system', null, true,
            'Tiket ditutup otomatis karena tidak ada tanggapan selama '
            '24 jam. Buat pengaduan baru kalau masalahnya belum selesai.',
            true);

    v_jumlah := v_jumlah + 1;
  end loop;

  return v_jumlah;
end;
$$;

select cron.unschedule('close-idle-support')
where exists (select 1 from cron.job where jobname = 'close-idle-support');

-- Tiap jam. Ketepatan menitnya tidak penting — yang dijanjikan "24 jam",
-- bukan "24 jam nol menit".
select cron.schedule('close-idle-support', '0 * * * *',
  $cron$select close_idle_support_tickets();$cron$);

grant execute on function open_support_ticket(text, text, text, text, text, text)
  to authenticated;
grant execute on function set_support_status(uuid, text) to authenticated;
grant execute on function mark_support_read(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select subject, reporter_email, status, last_message_at, auto_closed
--   from support_tickets order by last_message_at desc nulls last;
--
--   select t.subject, m.from_admin, m.is_system, m.body, m.created_at
--   from support_messages m join support_tickets t on t.id = m.ticket_id
--   order by m.created_at desc limit 20;
--
--   select close_idle_support_tickets();


-- ═══════════════════════════════════════════════════════════
-- 97. support_push.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — notifikasi untuk MerchantPOS Support.
--
-- Jalankan SETELAH support_tickets.sql dan push_notifications.sql.
-- Aman diulang.
--
-- Penanda di dalam aplikasi hanya terlihat oleh orang yang sedang
-- membuka aplikasinya. Yang mengadu lalu menutup HP-nya — dan itulah
-- yang dilakukan hampir semua orang setelah mengadu — tidak akan pernah
-- tahu keluhannya sudah dijawab sampai ia kebetulan membuka MerchantPOS
-- lagi. Balasan yang tidak sampai sama saja dengan tidak dibalas.

-- Satu pemicu untuk kedua arah.
--
-- Perubahan status pun ikut lewat sini, karena `set_support_status`
-- menuliskannya sebagai pesan sistem. Menambah pemicu terpisah di tabel
-- tiket berarti dua tempat yang harus sepakat soal siapa yang dikabari
-- — dan yang kedua akan tertinggal.
create or replace function queue_push_support()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t support_tickets;
  v_nama text;
  v_cuplikan text;
  v_admin record;
begin
  select * into t from support_tickets where id = new.ticket_id;
  if t is null then return new; end if;

  -- Isi pesannya dipotong, bukan dikirim utuh. Notifikasi Android
  -- memotongnya sendiri di tengah kata, dan pengaduan yang panjang jadi
  -- terbaca setengah kalimat tanpa ujung.
  v_cuplikan := left(regexp_replace(new.body, E'[\n\r]+', ' ', 'g'), 90);

  if new.from_admin then
    -- Ke pelapor. Tepat satu orang, jadi audiensnya email.
    insert into push_outbox (resto_id, event, payload) values (
      t.resto_id, 'support_message',
      jsonb_build_object(
        'audience', 'email',
        'email', t.reporter_email,
        'ticket_id', t.id::text,
        'title', 'MerchantPOS Support — ' || t.subject,
        'body', v_cuplikan
      )
    );
  else
    v_nama := coalesce(nullif(btrim(coalesce(t.reporter_name, '')), ''),
                       split_part(t.reporter_email, '@', 1));

    -- Ke MerchantPOS Admin, satu baris per orang, disasar lewat emailnya.
    --
    -- Sempat memakai audiens 'role' dengan peran super_admin, dan itu
    -- gagal dengan "tidak ada perangkat terdaftar": baris token hanya
    -- punya peran kalau perangkatnya mendaftar setelah orangnya masuk
    -- sebagai MerchantPOS Admin. Satu perangkat yang pernah dipakai masuk
    -- sebagai peran lain, atau yang barisnya ditulis versi lama, tidak
    -- akan pernah terjaring.
    --
    -- Emailnya jauh lebih tahan: ia ditulis di setiap pendaftaran token,
    -- apa pun peran yang sedang dipegang saat itu.
    --
    -- Konsekuensinya satu baris outbox per admin, bukan satu untuk
    -- semuanya. Jumlah MerchantPOS Admin dihitung jari, dan kabar yang
    -- sampai lebih berharga daripada satu baris yang rapi.
    for v_admin in
      select distinct e.email
      from employees e
      where e.role = 'super_admin'
        and coalesce(e.active, true) = true
        and e.email is not null
    loop
      insert into push_outbox (resto_id, event, payload) values (
        null, 'support_message',
        jsonb_build_object(
          'audience', 'email',
          'email', v_admin.email,
          'ticket_id', t.id::text,
          'title', 'Pengaduan dari ' || v_nama,
          'body', v_cuplikan
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_queue_push_support on support_messages;
create trigger trg_queue_push_support
  after insert on support_messages
  for each row execute function queue_push_support();

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select event, payload ->> 'title', payload ->> 'audience',
--          payload ->> 'ticket_id', sent_at, error
--   from push_outbox where event = 'support_message'
--   order by created_at desc limit 10;
--
--   -- Yang gagal terkirim menyisakan `error`; yang belum terkirim
--   -- menyisakan sent_at kosong.


-- ═══════════════════════════════════════════════════════════
-- 98. support_auto_reply.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — sapaan otomatis, dan penanda belum dibaca yang tahan
-- terhadapnya.
--
-- Jalankan SETELAH support_tickets.sql. Aman diulang.
--
-- Yang baru mengadu tidak tahu pengaduannya sampai atau tidak. Layar
-- yang diam sesudah tombol kirim ditekan terbaca sebagai "hilang", dan
-- yang merasa keluhannya hilang akan mengirimkannya lagi — atau berhenti
-- memakai aplikasinya sama sekali.
--
-- Tapi sapaan itu tidak boleh membuat tiketnya terlihat sudah dijawab.
-- Di sisi MerchantPOS Admin ia harus tetap berdiri sebagai pengaduan yang
-- belum dibaca, karena memang belum ada manusia yang membacanya.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Dua stempel waktu, bukan satu
-- ─────────────────────────────────────────────────────────────────────
--
-- Penanda belum dibaca semula disimpulkan dari `last_message_from_admin`:
-- ada kabar baru untuk admin kalau pesan terakhir BUKAN dari admin.
-- Cara itu runtuh begitu ada sapaan otomatis — pesan terakhirnya jadi
-- "dari admin", dan pengaduan yang belum dibaca siapa pun langsung
-- terlihat beres.
--
-- Yang benar: catat kapan masing-masing pihak terakhir bicara, lalu
-- bandingkan dengan kapan lawan bicaranya terakhir membaca. Dua
-- pertanyaan yang berbeda tidak bisa dijawab satu kolom.
alter table support_tickets
  add column if not exists last_reporter_at timestamptz,
  add column if not exists last_admin_at timestamptz;

-- Baris lama diisi dari percakapannya sendiri.
update support_tickets t
   set last_reporter_at = (
         select max(m.created_at) from support_messages m
         where m.ticket_id = t.id and m.from_admin = false),
       last_admin_at = (
         select max(m.created_at) from support_messages m
         where m.ticket_id = t.id and m.from_admin = true)
 where t.last_reporter_at is null and t.last_admin_at is null;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Ringkasan tiket
-- ─────────────────────────────────────────────────────────────────────

create or replace function touch_support_ticket()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update support_tickets
     set last_message_at = new.created_at,
         last_message_body = left(new.body, 160),
         last_message_from_admin = new.from_admin,
         last_reporter_at = case
           when new.from_admin then last_reporter_at else new.created_at end,
         last_admin_at = case
           when new.from_admin then new.created_at else last_admin_at end,
         updated_at = new.created_at,
         -- Pesan dari pengadu membangunkan tiket yang sedang menunggu
         -- jawabannya. Tanpa ini, tiket yang baru saja dijawab pengadu
         -- tetap berstatus "menunggu pengadu" — lalu ditutup sendiri
         -- oleh penjadwal, tepat setelah orangnya membalas.
         status = case
           when status = 'confirm_customer' and new.from_admin = false
             then 'on_progress'
           else status
         end
   where id = new.ticket_id;
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Membuka tiket, berikut sapaannya
-- ─────────────────────────────────────────────────────────────────────

create or replace function open_support_ticket(
  p_subject text,
  p_body text,
  p_kind text default 'customer',
  p_resto_id text default null,
  p_name text default null,
  p_photo text default null)
returns support_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row support_tickets;
  v_nama text;
  v_sebutan text;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu untuk membuat pengaduan.';
  end if;
  if btrim(coalesce(p_subject, '')) = '' then
    raise exception 'Judul pengaduannya belum diisi.';
  end if;
  if btrim(coalesce(p_body, '')) = '' then
    raise exception 'Ceritakan dulu keluhannya.';
  end if;

  insert into support_tickets (
    reporter_email, reporter_name, reporter_kind, resto_id, subject,
    reporter_read_at)
  values (
    v_email, p_name,
    case when p_kind = 'merchant' then 'merchant' else 'customer' end,
    p_resto_id, btrim(p_subject), now())
  returning * into v_row;

  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body, photo_base64)
  values (v_row.id, v_email, p_name, false, btrim(p_body), p_photo);

  v_nama := coalesce(nullif(btrim(coalesce(p_name, '')), ''),
                     split_part(v_email, '@', 1));

  -- Percakapan bebas disebut "chat", pengaduan disebut "pengaduan".
  -- Judulnya harus sama persis dengan `kSubjekChatUmum` di aplikasi;
  -- ada tes yang menjaga keduanya tidak berpisah.
  v_sebutan := case
    when btrim(p_subject) = 'Chat dengan MerchantPOS Admin' then 'chat'
    else 'pengaduan'
  end;

  -- Sapaannya dikirim sebagai pesan biasa dari admin, bukan pesan
  -- sistem: yang membacanya harus merasa disambut orang, bukan dibalas
  -- mesin.
  --
  -- Emailnya 'system:greeting' — dipakai pemicu notifikasi untuk
  -- melewatinya. Orang yang baru saja menekan kirim sedang menatap
  -- layarnya; membunyikan HP-nya detik itu juga bukan kabar, cuma
  -- kebisingan.
  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body)
  values (
    v_row.id, 'system:greeting', null, true,
    'Halo ' || v_nama || ', mohon bersabar MerchantPOS Admin akan meresponse '
      || v_sebutan || ' secepatnya, terimakasih sudah berkenan menunggu.');

  select * into v_row from support_tickets where id = v_row.id;
  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Notifikasi melewati sapaannya
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_push_support()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t support_tickets;
  v_nama text;
  v_cuplikan text;
  v_admin record;
begin
  -- Sapaan otomatis tidak dikabarkan. Lihat catatan di
  -- open_support_ticket.
  if new.sender_email = 'system:greeting' then
    return new;
  end if;

  select * into t from support_tickets where id = new.ticket_id;
  if t is null then return new; end if;

  v_cuplikan := left(regexp_replace(new.body, E'[\n\r]+', ' ', 'g'), 90);

  if new.from_admin then
    insert into push_outbox (resto_id, event, payload) values (
      t.resto_id, 'support_message',
      jsonb_build_object(
        'audience', 'email',
        'email', t.reporter_email,
        'ticket_id', t.id::text,
        'title', 'MerchantPOS Support — ' || t.subject,
        'body', v_cuplikan
      )
    );
  else
    v_nama := coalesce(nullif(btrim(coalesce(t.reporter_name, '')), ''),
                       split_part(t.reporter_email, '@', 1));

    for v_admin in
      select distinct e.email
      from employees e
      where e.role = 'super_admin'
        and coalesce(e.active, true) = true
        and e.email is not null
    loop
      insert into push_outbox (resto_id, event, payload) values (
        null, 'support_message',
        jsonb_build_object(
          'audience', 'email',
          'email', v_admin.email,
          'ticket_id', t.id::text,
          'title', 'Pengaduan dari ' || v_nama,
          'body', v_cuplikan
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   -- Tiket baru harus punya dua pesan: keluhannya, lalu sapaannya —
--   -- dan `last_reporter_at` tetap terisi walau pesan terakhirnya dari
--   -- admin.
--   select subject, last_reporter_at, last_admin_at, admin_read_at,
--          last_message_from_admin
--   from support_tickets order by created_at desc limit 3;
--
--   -- Sapaannya tidak boleh melahirkan baris push:
--   select count(*) from push_outbox
--   where payload ->> 'body' like 'Halo %mohon bersabar%';


-- ═══════════════════════════════════════════════════════════
-- 99. support_chat_rules.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — chat bebas bukan pengaduan, dan tiket kembar tidak lahir
-- dua kali.
--
-- Jalankan SETELAH support_auto_reply.sql. Aman diulang.

-- ─────────────────────────────────────────────────────────────────────
-- Tiket kembar
-- ─────────────────────────────────────────────────────────────────────
--
-- Dua ketukan cepat pada tombol Kirim melahirkan dua tiket berisi
-- kalimat yang sama persis. Aplikasi sudah menjaganya sejak 2.16.0, tapi
-- penjaga yang hanya ada di aplikasi bukan penjaga: HP yang belum
-- diperbarui, permintaan yang diulang jaringan, atau proses yang mati
-- lalu dicoba lagi semuanya lolos begitu saja.
--
-- Penjaganya di sini: pengaduan dengan judul dan isi yang sama, dari
-- orang yang sama, dalam sepuluh detik terakhir, dianggap satu — dan
-- yang kedua mengembalikan tiket yang pertama alih-alih membuat yang
-- baru.
--
-- Sepuluh detik, bukan satu jam. Yang benar-benar mengirim dua keluhan
-- serupa berjarak semenit sedang menambahkan sesuatu, bukan salah
-- pencet.
create or replace function open_support_ticket(
  p_subject text,
  p_body text,
  p_kind text default 'customer',
  p_resto_id text default null,
  p_name text default null,
  p_photo text default null)
returns support_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row support_tickets;
  v_nama text;
  v_sebutan text;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu untuk membuat pengaduan.';
  end if;
  if btrim(coalesce(p_subject, '')) = '' then
    raise exception 'Judul pengaduannya belum diisi.';
  end if;
  if btrim(coalesce(p_body, '')) = '' then
    raise exception 'Ceritakan dulu keluhannya.';
  end if;

  -- Kembar yang baru saja lahir.
  select t.* into v_row
  from support_tickets t
  join support_messages m on m.ticket_id = t.id
  where t.reporter_email = v_email
    and t.subject = btrim(p_subject)
    and t.created_at > now() - interval '10 seconds'
    and m.from_admin = false
    and m.body = btrim(p_body)
  order by t.created_at desc
  limit 1;

  if v_row.id is not null then
    return v_row;
  end if;

  insert into support_tickets (
    reporter_email, reporter_name, reporter_kind, resto_id, subject,
    reporter_read_at)
  values (
    v_email, p_name,
    case when p_kind = 'merchant' then 'merchant' else 'customer' end,
    p_resto_id, btrim(p_subject), now())
  returning * into v_row;

  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body, photo_base64)
  values (v_row.id, v_email, p_name, false, btrim(p_body), p_photo);

  v_nama := coalesce(nullif(btrim(coalesce(p_name, '')), ''),
                     split_part(v_email, '@', 1));

  v_sebutan := case
    when btrim(p_subject) = 'Chat dengan MerchantPOS Admin' then 'chat'
    else 'pengaduan'
  end;

  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body)
  values (
    v_row.id, 'system:greeting', null, true,
    'Halo ' || v_nama || ', mohon bersabar MerchantPOS Admin akan meresponse '
      || v_sebutan || ' secepatnya, terimakasih sudah berkenan menunggu.');

  select * into v_row from support_tickets where id = v_row.id;
  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Chat tidak pernah ditutup sendiri
-- ─────────────────────────────────────────────────────────────────────
--
-- Percakapan bebas tidak punya tahapan dan tidak menuntut keputusan
-- siapa pun. Menutupnya karena "tidak ada tanggapan selama 24 jam"
-- adalah menutup obrolan yang memang sudah selesai dengan sendirinya —
-- lalu memaksa orangnya membuka percakapan baru hanya untuk bertanya
-- lagi besok.
create or replace function close_idle_support_tickets()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jumlah integer := 0;
  t record;
begin
  for t in
    select id from support_tickets
    where status = 'confirm_customer'
      and subject <> 'Chat dengan MerchantPOS Admin'
      and last_message_from_admin = true
      and coalesce(last_message_at, updated_at) < now() - interval '24 hours'
  loop
    update support_tickets
       set status = 'closed',
           closed_at = now(),
           closed_by = null,
           auto_closed = true,
           updated_at = now()
     where id = t.id;

    insert into support_messages (
      ticket_id, sender_email, sender_name, from_admin, body, is_system)
    values (t.id, 'system', null, true,
            'Tiket ditutup otomatis karena tidak ada tanggapan selama '
            '24 jam. Buat pengaduan baru kalau masalahnya belum selesai.',
            true);

    v_jumlah := v_jumlah + 1;
  end loop;

  return v_jumlah;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Membersihkan tiket kembar yang terlanjur lahir
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang dibuang hanya yang benar-benar kembar: judul, pelapor, dan isi
-- pesan pertamanya sama, lahir dalam menit yang sama, dan BELUM pernah
-- dibalas manusia. Yang sudah ada percakapannya tidak disentuh —
-- menghapus percakapan yang sudah dijawab jauh lebih merugikan daripada
-- menyisakan satu baris kembar.
with kembar as (
  select t.id,
         row_number() over (
           partition by t.reporter_email, t.subject,
                        date_trunc('minute', t.created_at)
           order by t.created_at
         ) as urutan
  from support_tickets t
  where not exists (
    select 1 from support_messages m
    where m.ticket_id = t.id
      and m.from_admin = true
      and m.sender_email <> 'system:greeting'
  )
)
delete from support_tickets
where id in (select id from kembar where urutan > 1);

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select subject, count(*) from support_tickets
--   group by subject order by 2 desc;
--
--   -- Satu tiket harus berisi dua pesan saja saat baru dibuat:
--   select t.subject, count(m.id)
--   from support_tickets t join support_messages m on m.ticket_id = t.id
--   group by t.id, t.subject order by t.created_at desc limit 5;


-- ═══════════════════════════════════════════════════════════
-- 100. support_pesan_kembar.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — pesan kembar di dalam satu percakapan.
--
-- Jalankan SETELAH support_chat_rules.sql. Aman diulang.
--
-- Bagian 61 menjaga TIKET tidak lahir dua kali. Ia tidak menjaga
-- PESAN — dan percakapan yang sudah terlanjur berisi pesan ganda tetap
-- berisi pesan ganda selamanya, karena chat bebas memang sengaja
-- memakai percakapan yang sama terus-menerus.
--
-- Dua hal dikerjakan di sini: membersihkan yang sudah telanjur, dan
-- membuat pengulangannya mustahil.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Membersihkan yang sudah telanjur
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang dibuang hanya yang benar-benar kembar: percakapan yang sama,
-- pengirim yang sama, isi yang sama persis, dalam detik yang sama. Yang
-- tertua disimpan.
--
-- Batas satu detik sengaja sempit. Orang yang mengirim "iya" dua kali
-- berjarak beberapa detik memang mengirimnya dua kali, dan menghapus
-- yang kedua berarti menghapus ucapan yang benar-benar diucapkan.
with kembar as (
  select id,
         row_number() over (
           partition by ticket_id, sender_email, body,
                        date_trunc('second', timezone('UTC', created_at))
           order by created_at
         ) as urutan
  from support_messages
)
delete from support_messages
where id in (select id from kembar where urutan > 1);

-- ─────────────────────────────────────────────────────────────────────
-- Membuat pengulangannya mustahil
-- ─────────────────────────────────────────────────────────────────────
--
-- Bukan lagi bergantung pada urutan pemeriksaan di aplikasi maupun di
-- fungsi. Basis data yang menolak barisnya, dan penolakan itu berlaku
-- untuk semua jalan masuk sekaligus — tombol yang diketuk dua kali,
-- permintaan yang diulang jaringan, maupun proses yang mati lalu
-- mencoba lagi.
--
-- `timezone('UTC', ...)` dipakai supaya ekspresinya immutable; Postgres
-- menolak mengindeks `date_trunc` atas timestamptz apa adanya, karena
-- hasilnya bergantung zona waktu sesi.
create unique index if not exists support_messages_tanpa_kembar
  on support_messages (
    ticket_id,
    sender_email,
    md5(body),
    date_trunc('second', timezone('UTC', created_at)));

-- Sapaan otomatis paling banyak satu per percakapan.
--
-- Terpisah dari indeks di atas karena alasannya berbeda: yang ini bukan
-- soal ketukan ganda, melainkan soal sapaan yang tidak boleh muncul lagi
-- setiap kali fungsinya dijalankan ulang.
create unique index if not exists support_messages_satu_sapaan
  on support_messages (ticket_id)
  where sender_email = 'system:greeting';

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   -- Harus kosong:
--   select ticket_id, sender_email, body, count(*)
--   from support_messages
--   group by ticket_id, sender_email, body,
--            date_trunc('second', timezone('UTC', created_at))
--   having count(*) > 1;
--
--   -- Percakapan yang baru dibuat harus berisi tepat dua pesan:
--   select t.subject, count(m.id) as pesan
--   from support_tickets t join support_messages m on m.ticket_id = t.id
--   group by t.id, t.subject
--   order by max(m.created_at) desc limit 5;


-- ═══════════════════════════════════════════════════════════
-- 101. support_push_wording.sql
-- ═══════════════════════════════════════════════════════════

-- MerchantPOS — judul notifikasi chat tidak menyebut "pengaduan".
--
-- Jalankan SETELAH support_auto_reply.sql. Aman diulang.
--
-- Notifikasi chat selama ini berjudul "Pengaduan dari Budi". Yang
-- membacanya di layar kunci tidak punya cara tahu itu sebenarnya
-- pertanyaan biasa — dan yang mengirimnya merasa dituduh mengadu
-- padahal cuma bertanya.

create or replace function queue_push_support()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t support_tickets;
  v_nama text;
  v_cuplikan text;
  v_admin record;
  v_chat boolean;
begin
  -- Sapaan otomatis tidak dikabarkan: orang yang baru menekan kirim
  -- sedang menatap layarnya.
  if new.sender_email = 'system:greeting' then
    return new;
  end if;

  select * into t from support_tickets where id = new.ticket_id;
  if t is null then return new; end if;

  v_chat := t.subject = 'Chat dengan MerchantPOS Admin';

  v_cuplikan := left(regexp_replace(new.body, E'[\n\r]+', ' ', 'g'), 90);

  if new.from_admin then
    insert into push_outbox (resto_id, event, payload) values (
      t.resto_id, 'support_message',
      jsonb_build_object(
        'audience', 'email',
        'email', t.reporter_email,
        'ticket_id', t.id::text,
        'title', case
          when v_chat then 'Balasan MerchantPOS Admin'
          else 'MerchantPOS Support — ' || t.subject
        end,
        'body', v_cuplikan
      )
    );
  else
    v_nama := coalesce(nullif(btrim(coalesce(t.reporter_name, '')), ''),
                       split_part(t.reporter_email, '@', 1));

    for v_admin in
      select distinct e.email
      from employees e
      where e.role = 'super_admin'
        and coalesce(e.active, true) = true
        and e.email is not null
    loop
      insert into push_outbox (resto_id, event, payload) values (
        null, 'support_message',
        jsonb_build_object(
          'audience', 'email',
          'email', v_admin.email,
          'ticket_id', t.id::text,
          'title', case
            when v_chat then 'Chat dari ' || v_nama
            else 'Pengaduan dari ' || v_nama
          end,
          'body', v_cuplikan
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select payload ->> 'title', payload ->> 'email', sent_at, error
--   from push_outbox where event = 'support_message'
--   order by created_at desc limit 5;
--
--   -- Siapa saja yang dianggap MerchantPOS Admin, dan sudah punya perangkat
--   -- terdaftar atau belum:
--   select e.email, d.token is not null as punya_perangkat, d.updated_at
--   from employees e
--   left join device_tokens d on d.email = e.email
--   where e.role = 'super_admin';

