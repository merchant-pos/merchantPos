-- KaataGo — customer name for pickup, required for Take Away orders
-- (dine-in doesn't need it — the table number identifies them instead).
alter table orders add column if not exists customer_name text;
