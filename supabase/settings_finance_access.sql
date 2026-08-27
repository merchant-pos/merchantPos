-- KaataGo — lets Finance edit payment settings too (previously admin-only).
-- Admin's own "Pengaturan Pembayaran" screen is now view-only in the
-- app; Finance is the one who actually edits it.
drop policy if exists "settings: admin insert" on settings;
create policy "settings: admin or finance insert" on settings
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance']));

drop policy if exists "settings: admin update" on settings;
create policy "settings: admin or finance update" on settings
  for update using (is_resto_employee(resto_id, array['admin', 'finance']))
  with check (is_resto_employee(resto_id, array['admin', 'finance']));
