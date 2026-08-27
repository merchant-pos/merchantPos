-- KaataGo — Kasir bisa lihat saldo & catat pengeluaran
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
