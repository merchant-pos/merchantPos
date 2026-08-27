-- KaataGo — Super Admin role (run AFTER rls_hardening.sql).
--
-- Adds a 'super_admin' role that isn't tied to any single restaurant —
-- it can manage employees for ANY resto and create new restos from
-- inside the app (regular Admins can only manage their own resto's
-- employees, and can't create new restos at all).
--
-- BOOTSTRAPPING: just like the first regular Admin, the first Super
-- Admin must be inserted manually via the Dashboard/SQL Editor (which
-- runs as the Postgres owner and bypasses RLS):
--   insert into employees (email, role, resto_id, active)
--   values ('you@gmail.com', 'super_admin', null, true);

-- Allow resto_id to be null (a Super Admin isn't scoped to one resto)
-- and allow the new role value.
alter table employees alter column resto_id drop not null;
alter table employees drop constraint if exists employees_role_check;
alter table employees add constraint employees_role_check
  check (role in ('admin', 'kasir', 'chef', 'super_admin', 'finance', 'owner'));

-- ── Helper: is the currently-authenticated user an active super_admin?
create or replace function is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from employees e
    where e.email = auth.jwt()->>'email'
      and e.role = 'super_admin'
      and e.active = true
  );
$$;

-- ── employees: let super_admin manage any resto's employees ─────────
drop policy if exists "employees: read own or admin of resto" on employees;
create policy "employees: read own, resto admin, or super_admin" on employees
  for select using (
    email = auth.jwt()->>'email'
    or is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

drop policy if exists "employees: admin insert" on employees;
create policy "employees: admin or super_admin insert" on employees
  for insert with check (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

drop policy if exists "employees: admin update" on employees;
create policy "employees: admin or super_admin update" on employees
  for update using (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  )
  with check (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

drop policy if exists "employees: admin delete" on employees;
create policy "employees: admin or super_admin delete" on employees
  for delete using (
    is_super_admin()
    or (resto_id is not null and is_resto_employee(resto_id, array['admin']))
  );

-- ── restaurants: let super_admin create new restos + edit any resto ──
create policy "restaurants: super_admin insert" on restaurants
  for insert with check (is_super_admin());

drop policy if exists "restaurants: admin update own" on restaurants;
create policy "restaurants: admin or super_admin update" on restaurants
  for update using (is_super_admin() or is_resto_employee(id, array['admin']))
  with check (is_super_admin() or is_resto_employee(id, array['admin']));
