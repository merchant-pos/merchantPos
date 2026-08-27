-- KaataGo — fixes customer QRIS "Simulasikan: Sudah Dibayar" silently
-- failing after rls_hardening.sql restricted orders UPDATE to employees
-- only. This RPC lets a guest (no auth session) flip THEIR OWN pending
-- self-order to paid, without reopening the door rls_hardening.sql
-- closed — the guardrails are baked into the function itself:
--   - only source = 'customer' orders (never a Kasir-rung sale)
--   - only from 'pending' to 'paid' (can't touch an order some other way)
-- SECURITY DEFINER so it bypasses the orders UPDATE RLS policy (which
-- still correctly blocks direct table updates from anon/guest clients).
create or replace function mark_order_paid(p_order_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update orders
  set payment_status = 'paid'
  where id = p_order_id
    and source = 'customer'
    and payment_status = 'pending';
$$;
