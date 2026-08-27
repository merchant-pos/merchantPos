-- KaataGo — orders.gl_code (run AFTER gl_journal.sql — reuses its
-- _normalize_payment_method() helper).
--
-- Adds a `gl_code` column directly on `orders`, kept in sync by trigger
-- rather than looked up ad hoc each time: the moment an order's
-- payment_method is known (or it's a customer self-order, always QRIS),
-- its gl_code is filled in from that resto's Mapping GL Account
-- (`gl_accounts.gl_code`, joined on the normalized payment_method) —
-- e.g. an order with payment_method = 'qris' gets whatever gl_code this
-- resto has mapped to QRIS. Stays null if that GL isn't configured yet.
--
-- This is the "flat" per-order record (handy for exports/filtering
-- directly on `orders`); gl_journal_entries (see gl_journal.sql) is the
-- append-only ledger of the same fact, journaled only once payment_status
-- actually reaches 'paid'. The two don't conflict: this column reflects
-- the *intended* GL as soon as it's knowable, the journal reflects money
-- that's *actually* moved.

alter table orders add column if not exists gl_code text;

-- Fixes _normalize_payment_method() (originally from gl_journal.sql):
-- orders.payment_method is now written as the lowercase gl_accounts key
-- directly ('cash'/'qris'/'transfer' — see cart_provider.dart and
-- customer_cart_provider.dart) instead of the display label, but the
-- old function only recognized the capitalized labels and silently
-- mapped any lowercase 'qris'/'transfer' to 'cash'. This still honors
-- the old capitalized labels too, for orders recorded before that
-- change. Safe to rerun even if gl_journal.sql already defined this.
create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_source = 'customer' then 'qris'
    when p_payment_method in ('cash', 'qris', 'transfer') then p_payment_method
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    else 'cash'
  end;
$$;

create or replace function order_set_gl_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_method text;
begin
  v_method := _normalize_payment_method(new.source, new.payment_method);
  select gl_code into new.gl_code
  from gl_accounts
  where resto_id = new.resto_id and payment_method = v_method
  limit 1;
  return new;
end;
$$;

drop trigger if exists trg_order_set_gl_code_insert on orders;
create trigger trg_order_set_gl_code_insert
  before insert on orders
  for each row execute function order_set_gl_code();

drop trigger if exists trg_order_set_gl_code_update on orders;
create trigger trg_order_set_gl_code_update
  before update of payment_method, payment_status on orders
  for each row execute function order_set_gl_code();

-- Backfill every existing order with whatever GL is mapped today.
update orders o
set gl_code = (
  select g.gl_code
  from gl_accounts g
  where g.resto_id = o.resto_id
    and g.payment_method = _normalize_payment_method(o.source, o.payment_method)
  limit 1
)
where o.gl_code is null;
