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
