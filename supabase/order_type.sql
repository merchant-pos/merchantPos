-- KaataGo — adds Dine In / Take Away to orders, chosen at checkout by
-- both the customer app and the Kasir.
alter table orders add column if not exists order_type text not null default 'dine_in'
  check (order_type in ('dine_in', 'take_away'));
