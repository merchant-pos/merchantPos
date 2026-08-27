-- Adds description + photo_base64 columns to products — run in Supabase SQL Editor.
alter table products add column if not exists description text;
alter table products add column if not exists photo_base64 text;
