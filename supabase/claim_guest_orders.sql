-- KaataGo — mengalihkan riwayat pesanan tamu ke email yang baru login
-- (run AFTER rls_hardening.sql).
--
-- A guest's orders are labelled 'Tamu' and only tracked by ids saved on
-- their own device (see lib/db/guest_order_store.dart). When that person
-- later signs in, those orders should follow them — but only when the
-- email is genuinely new to KaataGo. If the email already has history,
-- the two are left completely separate: the account keeps its own
-- orders, and the guest list stays on the device so it's still there
-- after logging out again.
--
-- Needs SECURITY DEFINER because rls_hardening.sql restricts UPDATE on
-- `orders` to employees — a customer has no such privilege. The
-- guardrails that make that safe are all inside the function:
--
--   - the target email is read from the caller's own JWT, never passed
--     in, so nobody can claim orders into someone else's account;
--   - only rows still labelled 'Tamu' are touched, so an order already
--     belonging to an account can't be stolen;
--   - only source = 'customer' rows, never a Kasir-rung sale;
--   - nothing happens at all if the email already has any orders.
--
-- Returns how many orders were claimed (0 when the email already had
-- history), which is what the app uses to decide whether to clear its
-- local guest list.
create or replace function claim_guest_orders(p_order_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_claimed integer;
begin
  if v_email is null or v_email = '' then
    raise exception 'Harus login untuk mengklaim riwayat pesanan';
  end if;

  if p_order_ids is null or array_length(p_order_ids, 1) is null then
    return 0;
  end if;

  -- Existing account: leave both histories exactly as they are.
  if exists (select 1 from orders where customer_label = v_email) then
    return 0;
  end if;

  update orders
  set customer_label = v_email
  where id = any(p_order_ids)
    and source = 'customer'
    and customer_label = 'Tamu';

  get diagnostics v_claimed = row_count;
  return v_claimed;
end;
$$;
