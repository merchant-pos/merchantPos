-- KaataGo — nomor HP resto (run AFTER schema.sql).
--
-- Printed on the receipt under the address, so a customer has a way to
-- reach the shop about their order. Optional: a resto that hasn't set one
-- just prints without that line.
alter table restaurants add column if not exists phone text;
