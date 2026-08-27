-- KaataGo — adds Nama (name) and NIP (employee ID number) to employees.
alter table employees add column if not exists name text;
alter table employees add column if not exists nip text;
