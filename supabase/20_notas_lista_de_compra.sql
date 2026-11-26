-- =====================================================================
-- La Obra v2 · 20 · Notas con lista de compra
-- Supabase → SQL Editor → New query → pegar → Run. No borra datos y se puede volver a correr.
--
--  · Una nota puede llevar una lista de compra: insumos (o cosas sueltas) con cantidad, unidad
--    y un precio aproximado sacado del costo del insumo. La nota muestra el total aproximado.
--  · Es solo una nota: NO registra compras, gastos ni movimientos de dinero.
--  · notes/inputs: insumos activos con su costo y su última compra (unidad, cantidad y precio),
--    para cualquier usuario (empleados también). Al agregar un insumo a la lista se prellena con eso.
-- =====================================================================
set check_function_bodies = off;

alter table la_obra_v2.notes add column if not exists items jsonb not null default '[]'::jsonb;

-- Limpia la lista: [{ input_id?, name, qty, unit, price }]  (price = aproximado de ese renglón)
create or replace function la_obra_v2.note_items(v jsonb)
returns jsonb language plpgsql as $$
declare x jsonb; r jsonb := '[]'; v_name text; v_in int;
begin
  if v is null or jsonb_typeof(v) <> 'array' then return '[]'; end if;
  for x in select * from jsonb_array_elements(v) loop
    if jsonb_typeof(x) <> 'object' then continue; end if;
    v_in := case when la_obra_v2.is_int(x -> 'input_id') and la_obra_v2.num(x -> 'input_id') > 0 then la_obra_v2.num(x -> 'input_id')::int end;
    v_name := left(la_obra_v2.jstr(x -> 'name'), 120);
    if v_in is not null then select coalesce(nullif(v_name, ''), name) into v_name from la_obra_v2.inputs where id = v_in; end if;
    if coalesce(v_name, '') = '' then continue; end if;
    r := r || jsonb_build_array(jsonb_build_object(
      'input_id', v_in, 'name', v_name,
      'qty', case when la_obra_v2.is_num(x -> 'qty') then round(abs(la_obra_v2.num(x -> 'qty')), 3)::float8 end,
      'unit', nullif(left(la_obra_v2.jstr(x -> 'unit'), 30), ''),
      'price', case when la_obra_v2.is_num(x -> 'price') then round(abs(la_obra_v2.num(x -> 'price')), 2)::float8 end));
    if jsonb_array_length(r) >= 60 then exit; end if;
  end loop;
  return r;
end $$;

create or replace function la_obra_v2.note_json(p_id int)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', n.id, 'title', n.title, 'details', n.details,
    'assigned_to', n.assigned_to, 'assigned_name', ua.name,
    'remind_at', la_obra_v2.fmt_ts(n.remind_at), 'repeat', n.repeat, 'status', n.status,
    'done_by', n.done_by, 'done_by_name', ud.name, 'done_at', la_obra_v2.fmt_ts(n.done_at),
    'created_by', n.created_by, 'created_by_name', uc.name, 'created_at', la_obra_v2.fmt_ts(n.created_at),
    'overdue', n.status = 'pending' and n.remind_at is not null and n.remind_at <= localtimestamp,
    'items', coalesce(n.items, '[]'::jsonb),
    'items_total', (select coalesce(sum((x ->> 'price')::numeric), 0)::float8 from jsonb_array_elements(coalesce(n.items, '[]'::jsonb)) x
                     where x ->> 'price' is not null))
  from la_obra_v2.notes n
  left join la_obra_v2.users ua on ua.id = n.assigned_to
  left join la_obra_v2.users ud on ud.id = n.done_by
  left join la_obra_v2.users uc on uc.id = n.created_by
  where n.id = p_id;
$$;

-- notes/save.php · POST { id?, title, details?, assigned_to?, remind_at?, repeat?, items? }
create or replace function la_obra_v2.ep_notes__save(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; n la_obra_v2.notes; v_title text; v_details text; v_to int; v_at timestamp; v_rep text; v_items jsonb;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_items := la_obra_v2.note_items(b -> 'items');
  v_title := la_obra_v2.jstr(b -> 'title');
  -- Sin título pero con lista: "Comprar: Pan, Queso, Tomate…"
  if v_title = '' and jsonb_array_length(v_items) > 0 then
    v_title := left('Comprar: ' || (select string_agg(x ->> 'name', ', ') from (select * from jsonb_array_elements(v_items) limit 4) s(x))
                    || case when jsonb_array_length(v_items) > 4 then '…' else '' end, 200);
  end if;
  v_details := nullif(la_obra_v2.jstr(b -> 'details'), '');
  if v_title = '' then perform la_obra_v2.fail(422, 'Escribe qué hay que comprar o hacer'); end if;
  if char_length(v_title) > 200 then perform la_obra_v2.fail(422, 'El texto es demasiado largo (máximo 200 caracteres)'); end if;
  if char_length(coalesce(v_details, '')) > 1000 then perform la_obra_v2.fail(422, 'Los detalles son demasiado largos'); end if;
  v_to := null;
  if la_obra_v2.jtext(b -> 'assigned_to') is not null and la_obra_v2.jstr(b -> 'assigned_to') <> '' then
    v_to := la_obra_v2.positive_id(b -> 'assigned_to', 'La persona elegida no es válida');
    if not exists(select 1 from la_obra_v2.users where id = v_to and status = 'active') then
      perform la_obra_v2.fail(422, 'La persona elegida no tiene una cuenta activa');
    end if;
  end if;
  v_at := la_obra_v2.note_time(b -> 'remind_at');
  v_rep := coalesce(nullif(la_obra_v2.jstr(b -> 'repeat'), ''), 'none');
  if v_rep not in ('none','daily','weekly') then perform la_obra_v2.fail(422, 'La repetición no es válida'); end if;
  if v_rep <> 'none' and v_at is null then perform la_obra_v2.fail(422, 'Para repetir el recordatorio elige la fecha y hora'); end if;

  if la_obra_v2.jtext(b -> 'id') is not null and la_obra_v2.jstr(b -> 'id') <> '' then
    v_id := la_obra_v2.positive_id(b -> 'id', 'La nota no es válida');
    select * into n from la_obra_v2.notes where id = v_id for update;
    if n.id is null then perform la_obra_v2.fail(404, 'La nota ya no existe'); end if;
    if u.role <> 'admin' and n.created_by is distinct from u.id and n.assigned_to is distinct from u.id and n.assigned_to is not null then
      perform la_obra_v2.fail(403, 'Solo quien la creó, a quien se le asignó o un administrador pueden editarla');
    end if;
    update la_obra_v2.notes set title = v_title, details = v_details, assigned_to = v_to, remind_at = v_at, repeat = v_rep,
           items = case when b ? 'items' then v_items else items end, updated_at = localtimestamp where id = v_id;
    return la_obra_v2.ok(200, 'Nota actualizada', jsonb_build_object('note', la_obra_v2.note_json(v_id)));
  end if;
  insert into la_obra_v2.notes(title, details, assigned_to, remind_at, repeat, created_by, items)
  values (v_title, v_details, v_to, v_at, v_rep, u.id, v_items) returning id into v_id;
  return la_obra_v2.ok(201, 'Nota agregada', jsonb_build_object('note', la_obra_v2.note_json(v_id)));
end $$;

-- notes/inputs · GET · insumos activos con su costo y medidas (para armar la lista de compra)
create or replace function la_obra_v2.ep_notes__inputs(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  return la_obra_v2.ok(200, 'Insumos', jsonb_build_object('inputs', (
    select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'unit', i.unit,
             'unit_cost', round(la_obra_v2.input_cost(i.id), 4)::float8,
             'last_purchase', la_obra_v2.input_last_purchase(i.id),
             'units', la_obra_v2.input_units_json(i.id)) order by i.name, i.id), '[]')
      from la_obra_v2.inputs i where i.status = 'active')));
end $$;

-- ---------- Permisos ----------
revoke all on all tables in schema la_obra_v2 from public;
revoke all on all functions in schema la_obra_v2 from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all tables in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all functions in schema la_obra_v2 from anon, authenticated';
  end if;
end $$;
notify pgrst, 'reload schema';
select 'Notas con lista de compra listas' as resultado;
