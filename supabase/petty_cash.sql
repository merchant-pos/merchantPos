-- KaataGo — Petty Cash ledger (run AFTER finance.sql).
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
