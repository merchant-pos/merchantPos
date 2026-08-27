-- KaataGo — tarif PPN & biaya service dipindah ke Finance
-- (run AFTER tax_and_service.sql).
--
-- The rates sit on `restaurants`, but setting them is a Finance job, not
-- an Admin one: they belong with the GL accounts the tax is booked to,
-- which is why the app now edits them from Mapping GL Account.
--
-- Rather than widening the restaurants UPDATE policy to Finance — which
-- would also let them rename the resto, change its address or flip it
-- inactive — this exposes exactly the two columns through a definer
-- function that checks the role itself.

-- restaurants.id is text, not uuid, and so is is_resto_employee's first
-- argument. An earlier uuid-typed version of this function failed at
-- call time because Postgres won't implicitly cast uuid to text.
drop function if exists set_tax_rates(uuid, numeric, numeric);

create or replace function set_tax_rates(
  p_resto_id text,
  p_ppn_percent numeric,
  p_service_percent numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['finance', 'admin'])) then
    raise exception 'Tidak punya akses mengubah tarif PPN/service';
  end if;

  -- A negative rate would silently produce negative tax on every bill;
  -- the upper bound is a typo guard (entering 110 instead of 11).
  if p_ppn_percent < 0 or p_ppn_percent > 100
     or p_service_percent < 0 or p_service_percent > 100 then
    raise exception 'Tarif harus antara 0 dan 100';
  end if;

  update restaurants
     set ppn_percent = p_ppn_percent,
         service_percent = p_service_percent
   where id = p_resto_id;
end;
$$;

revoke all on function set_tax_rates(text, numeric, numeric) from public;
grant execute on function set_tax_rates(text, numeric, numeric) to authenticated;
