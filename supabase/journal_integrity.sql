-- KaataGo — Journal integrity (run AFTER orders_gl_code.sql and
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
