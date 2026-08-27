-- Product categories — run this in Supabase SQL Editor after schema.sql.

create table if not exists categories (
  id text primary key,
  resto_id text not null references restaurants(id),
  name text not null
);
create index if not exists idx_categories_resto on categories(resto_id);

alter table categories enable row level security;
create policy "public read/write categories" on categories for all using (true) with check (true);
