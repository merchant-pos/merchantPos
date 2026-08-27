-- KaataGo — lets a customer browse a resto's menu by picking it from a
-- list (instead of only via table QR scan). No table is known yet in
-- that case, so `sessions.table_number` must be nullable — it gets
-- filled in later, mandatorily, at checkout.
alter table sessions alter column table_number drop not null;
