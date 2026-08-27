-- KaataGo — Jurnal ulang (run AFTER journal_integrity.sql).
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
