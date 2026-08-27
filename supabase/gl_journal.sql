-- KaataGo — GL Journal (run AFTER finance.sql; petty_cash.sql not required).
--
-- One table capturing every real money movement, written automatically
-- by triggers rather than the app deciding when to log it — so it stays
-- consistent no matter which flow marks an order paid (Kasir sale,
-- customer QRIS "Simulasikan: Sudah Dibayar", the mark_order_paid RPC),
-- and no matter which screen records an expense.
--
-- Only orders/expenses that actually resolve to a configured GL account
-- get journaled (Mapping GL Account for orders, an expense's own
-- optional GL tag for expenses) — nothing to book against otherwise.
create table if not exists gl_journal_entries (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),
  entry_date date not null,
  entry_time time not null,
  gl_code text not null,
  reference_type text not null check (reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance'));
create index if not exists idx_gl_journal_entries_resto on gl_journal_entries(resto_id);
create index if not exists idx_gl_journal_entries_ref on gl_journal_entries(reference_type, reference_id);

alter table gl_journal_entries enable row level security;

create policy "gl_journal_entries: finance/admin read" on gl_journal_entries
  for select using (is_resto_employee(resto_id, array['admin', 'finance']));
-- Deliberately no insert/update/delete policy for any role — every row
-- is written only by the SECURITY DEFINER trigger functions below, never
-- directly by the app, so the journal can't drift from what actually
-- happened on `orders`/`expenses`.

-- Normalizes an order into 'cash' | 'qris' | 'transfer', matching the
-- Dart-side `_methodKey()` in finance_income_screen.dart: customer
-- self-orders never set payment_method (always QRIS in practice), and
-- Kasir sales store the display label ('QRIS'/'Transfer'/'Tunai'), not
-- the lowercase key `gl_accounts` is keyed on.
create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_source = 'customer' then 'qris'
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    else 'cash'
  end;
$$;

create or replace function log_order_paid_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl_code text;
  v_now timestamptz := now();
  v_method text;
begin
  if new.payment_status = 'paid' then
    v_method := _normalize_payment_method(new.source, new.payment_method);
    select gl_code into v_gl_code
    from gl_accounts
    where resto_id = new.resto_id and payment_method = v_method
    limit 1;

    if v_gl_code is not null and v_gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id,
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl_code, 'order', new.id::text, new.total, 'credit',
        'Pemasukan pesanan #' || upper(substr(new.id::text, 1, 8))
      );
    end if;
  end if;
  return new;
end;
$$;

-- Covers both: an order inserted already-paid (Kasir sales always are),
-- and one that starts pending and flips to paid later (customer QRIS).
drop trigger if exists trg_log_order_paid_journal_insert on orders;
create trigger trg_log_order_paid_journal_insert
  after insert on orders
  for each row execute function log_order_paid_journal();

drop trigger if exists trg_log_order_paid_journal_update on orders;
create trigger trg_log_order_paid_journal_update
  after update of payment_status on orders
  for each row
  when (new.payment_status = 'paid' and old.payment_status is distinct from 'paid')
  execute function log_order_paid_journal();

create or replace function log_expense_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  if new.gl_code is not null and new.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id,
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      new.gl_code, 'expense', new.id::text, new.amount, 'debit', new.description
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_expense_journal on expenses;
create trigger trg_log_expense_journal
  after insert on expenses
  for each row execute function log_expense_journal();
