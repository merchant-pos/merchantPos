-- KaataGo — GL account chart for EXPENSES (run AFTER finance.sql).
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
