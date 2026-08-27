-- KaataGo — lets Super Admin activate/deactivate a restaurant.
-- Inactive restos: hidden from the customer's "Pilih Resto" list, and
-- their employees are blocked from logging in (see AuthProvider).
alter table restaurants add column if not exists active boolean not null default true;
