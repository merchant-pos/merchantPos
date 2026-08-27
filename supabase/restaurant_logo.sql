-- KaataGo — logo resto (run AFTER schema.sql).
--
-- Optional store logo, base64-encoded in the row itself — the same
-- approach product photos, customer photos and expense receipts already
-- use, so there's no storage bucket to provision.
--
-- Deliberately one shared column rather than per-role copies: whoever
-- uploads it (Super Admin when creating/editing the resto, or the Admin
-- from Info Resto) writes the same field, and either can clear it.
alter table restaurants add column if not exists logo_base64 text;
