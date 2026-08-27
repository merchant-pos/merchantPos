-- KaataGo — RLS hardening (run in Supabase SQL Editor AFTER schema.sql,
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
