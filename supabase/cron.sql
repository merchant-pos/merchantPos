-- Auto-end idle sessions — pure SQL + pg_cron, no Edge Function needed.
-- Run this in Supabase SQL Editor AFTER schema.sql and functions.sql.
--
-- First enable the pg_cron extension: Dashboard > Database > Extensions
-- > search "pg_cron" > Enable. Then run this file.

create extension if not exists pg_cron with schema extensions;

create or replace function auto_end_idle_sessions()
returns void
language plpgsql
as $$
begin
  update sessions s
  set active = false
  where s.active = true
    and s.last_order_at is not null
    and s.last_order_at <= now() - interval '5 minutes'
    -- has at least one order
    and exists (select 1 from orders o where o.session_id = s.id)
    -- and every order in it is done
    and not exists (
      select 1 from orders o
      where o.session_id = s.id and o.kitchen_status <> 'done'
    );
end;
$$;

-- Runs every 5 minutes, forever, entirely inside the free Supabase plan.
select cron.schedule(
  'auto-end-idle-sessions',
  '*/5 * * * *',
  $$select auto_end_idle_sessions();$$
);
