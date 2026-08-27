-- KaataGo — Petty Cash journal mapping (run AFTER petty_cash.sql and
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
