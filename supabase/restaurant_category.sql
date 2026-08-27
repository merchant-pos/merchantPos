-- Adds a category column to restaurants — run in Supabase SQL Editor.
alter table restaurants add column if not exists category text;
