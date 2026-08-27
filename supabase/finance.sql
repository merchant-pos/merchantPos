-- KaataGo — Finance role (run AFTER rls_hardening.sql and super_admin.sql).
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
