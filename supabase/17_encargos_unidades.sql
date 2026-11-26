-- =====================================================================
-- La Obra v2 · 17 · Encargos con cantidad y unidad (pza, kg, paquete, caja…)
-- Supabase → SQL Editor → New query → pegar → Run. No borra datos.
-- Los encargos anteriores siguen viéndose igual.
-- =====================================================================
set check_function_bodies = off;

-- Limpia la lista: [{ name, qty?, unit?, estimate?, real? }]
-- qty: número (ej. 1.5) — unit: pza, kg, g, L, paquete, caja, bolsa… (texto libre, máx. 20)
-- estimate / real: costo de ese renglón completo (no por unidad)
create or replace function la_obra_v2.errand_items(v jsonb)
returns jsonb language plpgsql as $$
declare x jsonb; r jsonb := '[]'; v_name text;
begin
  if v is null or jsonb_typeof(v) <> 'array' then return '[]'; end if;
  for x in select * from jsonb_array_elements(v) loop
    v_name := left(la_obra_v2.jstr(x -> 'name'), 120);
    if v_name = '' then continue; end if;
    r := r || jsonb_build_array(jsonb_build_object('name', v_name,
           'qty', case when la_obra_v2.is_num(x -> 'qty') then to_jsonb(round(abs(la_obra_v2.num(x -> 'qty')), 3)::float8)
                       else to_jsonb(nullif(left(la_obra_v2.jstr(x -> 'qty'), 40), '')) end,
           'unit', nullif(left(la_obra_v2.jstr(x -> 'unit'), 20), ''),
           'estimate', case when la_obra_v2.is_num(x -> 'estimate') then round(abs(la_obra_v2.num(x -> 'estimate')), 2)::float8 end,
           'real', case when la_obra_v2.is_num(x -> 'real') then round(abs(la_obra_v2.num(x -> 'real')), 2)::float8 end));
  end loop;
  return r;
end $$;

revoke all on all functions in schema la_obra_v2 from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all functions in schema la_obra_v2 from anon, authenticated';
  end if;
end $$;
notify pgrst, 'reload schema';
select 'Encargos con unidades listos' as resultado;
