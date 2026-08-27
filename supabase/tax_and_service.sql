-- KaataGo — PPN & biaya service (run AFTER restaurant_phone.sql and
-- orders_gl_code.sql).
--
-- Products store their ORIGINAL (pre-tax) price. The bill is built up
-- from it in the order Indonesian restaurants actually use — service
-- charge on the base, then PPN on base + service, because service
-- charge is itself subject to PPN:
--
--     service = base × service%
--     ppn     = (base + service) × ppn%
--     total   = base + service + ppn
--
-- The menu price shown to the customer carries PPN only. Service is a
-- per-bill Dine In charge and is added at checkout, so the same dish
-- never shows two different prices depending on how it's ordered.
--
-- Rates live on the restaurant (a tax rate is set by the state and by
-- house policy, not per dish), with per-product opt-outs for the items
-- that genuinely differ.

-- Rates, as percentages: 11 means 11%.
alter table restaurants add column if not exists ppn_percent numeric(5,2) not null default 0;
alter table restaurants add column if not exists service_percent numeric(5,2) not null default 0;

-- Per-product opt-outs. Default false: everything is taxed unless a
-- product is deliberately excluded.
alter table products add column if not exists ppn_exempt boolean not null default false;
alter table products add column if not exists service_exempt boolean not null default false;

-- The split, stored on the order so a receipt reprinted months later
-- shows the same figures even if the resto has changed its rates since.
-- base + service + ppn always equals total exactly (see the Dart
-- calculator rounds per line and sums, so the three always tie out).
alter table orders add column if not exists base_amount integer;
alter table orders add column if not exists service_amount integer;
alter table orders add column if not exists ppn_amount integer;

-- PPN and service collected are liabilities owed onward, not revenue, so
-- they get their own GL accounts rather than being folded into the
-- income mapping.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance'));

-- Journalling a paid order now credits up to three accounts instead of
-- one: the payment method's income GL gets the base, and PPN/service go
-- to theirs. Falls back to crediting the whole total to income when the
-- order predates this split (base_amount null) or the rates were zero.
create or replace function log_order_paid_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_ppn_gl record;
  v_service_gl record;
  v_now timestamptz := now();
  v_date date;
  v_time time;
  v_method text;
  v_ref text;
  v_base integer;
begin
  if new.payment_status <> 'paid' then
    return new;
  end if;

  v_date := (v_now at time zone 'Asia/Jakarta')::date;
  v_time := (v_now at time zone 'Asia/Jakarta')::time;
  v_ref := upper(substr(new.id::text, 1, 8));
  v_base := coalesce(new.base_amount, new.total);

  v_method := _normalize_payment_method(new.source, new.payment_method);
  select * into v_gl from _gl_account_for(new.resto_id, v_method);
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time, v_gl.gl_code, v_gl.gl_name,
      'order', new.id::text, v_base, 'credit',
      'Pemasukan pesanan #' || v_ref
    );
  end if;

  if coalesce(new.service_amount, 0) > 0 then
    select * into v_service_gl from _gl_account_for(new.resto_id, 'service');
    if v_service_gl.gl_code is not null and v_service_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time, v_service_gl.gl_code, v_service_gl.gl_name,
        'order', new.id::text, new.service_amount, 'credit',
        'Biaya service pesanan #' || v_ref
      );
    end if;
  end if;

  if coalesce(new.ppn_amount, 0) > 0 then
    select * into v_ppn_gl from _gl_account_for(new.resto_id, 'ppn');
    if v_ppn_gl.gl_code is not null and v_ppn_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time, v_ppn_gl.gl_code, v_ppn_gl.gl_name,
        'order', new.id::text, new.ppn_amount, 'credit',
        'PPN pesanan #' || v_ref
      );
    end if;
  end if;

  return new;
end;
$$;
