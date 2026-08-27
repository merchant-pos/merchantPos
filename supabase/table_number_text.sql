-- KaataGo — nomor meja jadi teks (run AFTER customer_browse_resto.sql).
--
-- Table "numbers" aren't numbers in practice: restaurants label tables
-- A01, B07, VIP-2 and so on. Storing them as integer silently made those
-- impossible to enter.
--
-- Converting integer → text preserves every existing value ("7" stays
-- "7"), and QR stickers already printed keep working — the scanner's
-- parser no longer insists on digits, so an old `TABLE:7` payload reads
-- as the string "7" and matches the migrated row.
alter table orders alter column table_number type text using table_number::text;
alter table sessions alter column table_number type text using table_number::text;
