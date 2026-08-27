-- Additional Postgres function(s) — run this in Supabase SQL Editor
-- AFTER schema.sql.

-- Atomically decrements a product's stock (a single UPDATE ... SET
-- stock = stock - qty is inherently atomic per row in Postgres, so this
-- safely handles two simultaneous orders without oversell — the same
-- guarantee the old Firestore transaction gave us).
create or replace function decrement_stock(p_id text, qty int)
returns void
language sql
as $$
  update products set stock = stock - qty where id = p_id;
$$;
