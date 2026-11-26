-- =====================================================================
-- La Obra v2 · 18 · Insumos: costo editable y unidades de compra
-- Supabase → SQL Editor → New query → pegar → Run. No borra datos y se puede volver a correr.
--
--  · Costo del insumo = el MÁS RECIENTE entre:
--      - la última compra de ese insumo, y
--      - el costo que tú escribas a mano en Insumos.
--  · Cada medida del insumo dice para qué sirve: recetas, compras o las dos.
--    En Compras solo aparecen la unidad principal y las medidas marcadas "para comprar".
--  · Al elegir un insumo en Compras se prellena con lo de tu última compra:
--    unidad, cantidad, lo que trae cada unidad y precio (todo se puede cambiar).
-- =====================================================================
set check_function_bodies = off;

-- La primera vez: las medidas de cocina (cucharada, puño…) quedan solo para recetas
do $$
declare v_new boolean := not exists (select 1 from information_schema.columns
                                      where table_schema = 'la_obra_v2' and table_name = 'input_units' and column_name = 'use_in');
begin
  alter table la_obra_v2.input_units add column if not exists use_in text not null default 'both';
  if v_new then
    update la_obra_v2.input_units set use_in = 'recipe'
     where lower(name) in ('cucharada','cucharadita','puño','tercio','pizca','taza','chorrito','rebanada','porción','media rebanada');
  end if;
end $$;
do $$ begin
  alter table la_obra_v2.input_units add constraint input_units_use_in_check check (use_in in ('recipe','purchase','both'));
exception when duplicate_object then null; end $$;

alter table la_obra_v2.inputs add column if not exists manual_cost numeric(14,4) null;
alter table la_obra_v2.inputs add column if not exists manual_cost_at timestamp null;
alter table la_obra_v2.purchase_items add column if not exists buy_unit varchar(30) null;

-- ---------- Medidas del insumo (ahora con use_in) ----------
create or replace function la_obra_v2.input_units_json(p_input int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'unit_amount', u.unit_amount::float8,
           'base_amount', u.base_amount::float8, 'factor', (u.base_amount / u.unit_amount)::float8, 'use_in', u.use_in)
           order by lower(u.name), u.id), '[]'::jsonb)
    from la_obra_v2.input_units u where u.input_id = p_input;
$$;

create or replace function la_obra_v2.save_input_units(p_input int, p_units jsonb)
returns void language plpgsql as $$
declare v_base text; it jsonb; v_name text; v_ua numeric; v_ba numeric; v_id int; v_keep int[] := '{}'; v_names text[] := '{}'; v_use text;
begin
  if p_units is null or jsonb_typeof(p_units) = 'null' then return; end if;
  if jsonb_typeof(p_units) <> 'array' then perform la_obra_v2.fail(422, 'Medidas inválidas'); end if;
  select lower(btrim(unit)) into v_base from la_obra_v2.inputs where id = p_input;
  -- Validar todo antes de escribir
  for it in select * from jsonb_array_elements(p_units) loop
    v_name := la_obra_v2.jstr(it -> 'name');
    if v_name = '' or char_length(v_name) > 30 then perform la_obra_v2.fail(422, 'Escribe el nombre de cada medida (máximo 30 letras)'); end if;
    if lower(v_name) = v_base then perform la_obra_v2.fail(422, '"' || v_name || '" ya es la unidad principal del insumo'); end if;
    if lower(v_name) = any(v_names) then perform la_obra_v2.fail(422, 'La medida "' || v_name || '" está repetida'); end if;
    v_names := v_names || lower(v_name);
    if not la_obra_v2.is_num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)) or la_obra_v2.num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)) <= 0
       or not la_obra_v2.is_num(it -> 'base_amount') or la_obra_v2.num(it -> 'base_amount') <= 0 then
      perform la_obra_v2.fail(422, 'Indica a cuánto equivale la medida "' || v_name || '"');
    end if;
    v_use := coalesce(nullif(la_obra_v2.jstr(it -> 'use_in'), ''), 'both');
    if v_use not in ('recipe','purchase','both') then perform la_obra_v2.fail(422, 'Indica si "' || v_name || '" es para recetas, compras o ambas'); end if;
    if la_obra_v2.not_empty(it -> 'id') then
      v_id := la_obra_v2.positive_id(it -> 'id', 'Medida inválida');
      if not exists(select 1 from la_obra_v2.input_units where id = v_id and input_id = p_input) then perform la_obra_v2.fail(422, 'Medida inválida'); end if;
      v_keep := v_keep || v_id;
    end if;
  end loop;
  -- Medidas quitadas: sus ingredientes conservan la cantidad (ya está en la unidad principal)
  update la_obra_v2.preparation_inputs set unit_id = null, unit_quantity = null
   where unit_id in (select id from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep)));
  update la_obra_v2.product_components set unit_id = null, unit_quantity = null
   where unit_id in (select id from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep)));
  delete from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep));
  -- Evitar choque de nombres al renombrar
  update la_obra_v2.input_units set name = '~' || id where input_id = p_input;
  for it in select * from jsonb_array_elements(p_units) loop
    v_name := la_obra_v2.jstr(it -> 'name');
    v_ua := round(la_obra_v2.num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)), 3);
    v_ba := round(la_obra_v2.num(it -> 'base_amount'), 4);
    v_use := coalesce(nullif(la_obra_v2.jstr(it -> 'use_in'), ''), 'both');
    if v_ua <= 0 or v_ba <= 0 then perform la_obra_v2.fail(422, 'Indica a cuánto equivale la medida "' || v_name || '"'); end if;
    if la_obra_v2.not_empty(it -> 'id') then
      v_id := la_obra_v2.num(it -> 'id')::int;
      update la_obra_v2.input_units set name = v_name, unit_amount = v_ua, base_amount = v_ba, use_in = v_use where id = v_id;
      -- Si cambió la equivalencia, las recetas capturadas en esta medida se recalculan
      update la_obra_v2.preparation_inputs set quantity = greatest(round(unit_quantity * v_ba / v_ua, 3), 0.001)
       where unit_id = v_id and unit_quantity is not null;
      update la_obra_v2.product_components set quantity = greatest(round(unit_quantity * v_ba / v_ua, 3), 0.001)
       where unit_id = v_id and unit_quantity is not null;
    else
      insert into la_obra_v2.input_units(input_id, name, unit_amount, base_amount, use_in) values (p_input, v_name, v_ua, v_ba, v_use);
    end if;
  end loop;
end $$;

-- ---------- Costo del insumo ----------
-- Última compra de un insumo: cuándo, en qué unidad, cuánto y a qué precio
create or replace function la_obra_v2.input_last_purchase(p_input int)
returns jsonb language sql stable as $$
  select jsonb_build_object(
           'purchase_id', p.id, 'date', p.purchase_date,
           'at', to_char(coalesce(p.updated_at, p.created_at), 'YYYY-MM-DD HH24:MI:SS'),
           'buy_unit', coalesce(pi.buy_unit, nullif(nullif(i.package_type, i.unit), 'unidad')),
           'quantity', pi.quantity::float8, 'content_per_package', pi.content_per_package::float8,
           'unit_cost', pi.unit_cost::float8, 'subtotal', pi.subtotal::float8,
           'base_cost', case when pi.total_base_quantity > 0 then (pi.subtotal / pi.total_base_quantity)::float8 end,
           'supplier', p.supplier)
    from la_obra_v2.purchase_items pi
    join la_obra_v2.purchases p on p.id = pi.purchase_id
    join la_obra_v2.inputs i on i.id = pi.input_id
   where pi.input_id = p_input and pi.total_base_quantity > 0 and pi.subtotal >= 0
   order by p.purchase_date desc, p.id desc, pi.id desc limit 1;
$$;

-- Costo por unidad principal: lo más reciente entre la última compra y el costo puesto a mano
create or replace function la_obra_v2.input_cost(p_input int)
returns numeric language sql stable as $$
  with lp as (
    select pi.subtotal / pi.total_base_quantity as cost, coalesce(p.updated_at, p.created_at) as at
      from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id
     where pi.input_id = p_input and pi.total_base_quantity > 0 and pi.subtotal >= 0
     order by p.purchase_date desc, p.id desc, pi.id desc limit 1
  ), man as (
    select manual_cost as cost, manual_cost_at as at from la_obra_v2.inputs where id = p_input and manual_cost is not null
  )
  select case
           when (select cost from man) is null then (select cost from lp)
           when (select cost from lp) is null then (select cost from man)
           when (select at from man) >= (select at from lp) then (select cost from man)
           else (select cost from lp) end;
$$;

create or replace function la_obra_v2.input_cost_source(p_input int)
returns text language sql stable as $$
  select case
           when i.manual_cost is not null and (lp is null or i.manual_cost_at >= (lp ->> 'at')::timestamp) then 'manual'
           when lp is not null then 'purchase' end
    from la_obra_v2.inputs i cross join lateral (select la_obra_v2.input_last_purchase(i.id) lp) x
   where i.id = p_input;
$$;

-- ---------- inputs/index (ahora con costo y última compra) ----------
create or replace function la_obra_v2.ep_inputs__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true);
  return la_obra_v2.ok(200, 'Insumos', jsonb_build_object('inputs', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'unit', unit, 'status', status, 'package_type', package_type,
      'package_quantity', package_quantity, 'package_content_unit', package_content_unit, 'min_stock', min_stock,
      'unit_cost', round(la_obra_v2.input_cost(id), 4)::float8,
      'cost_source', la_obra_v2.input_cost_source(id),
      'manual_cost', manual_cost::float8, 'manual_cost_at', to_char(manual_cost_at, 'YYYY-MM-DD HH24:MI:SS'),
      'last_purchase', la_obra_v2.input_last_purchase(id),
      'units', la_obra_v2.input_units_json(id)) order by name, id), '[]')
    from la_obra_v2.inputs)));
end $$;

-- ---------- inputs/set-cost { id, cost } (costo por unidad principal; null = volver al de las compras) ----------
create or replace function la_obra_v2.ep_inputs__set_cost(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_cost numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  if not exists (select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  if b -> 'cost' is null or jsonb_typeof(b -> 'cost') = 'null' then
    update la_obra_v2.inputs set manual_cost = null, manual_cost_at = null where id = v_id;
    return la_obra_v2.ok(200, 'Se usa el costo de la última compra', jsonb_build_object('unit_cost', la_obra_v2.input_cost(v_id)::float8));
  end if;
  if not la_obra_v2.is_num(b -> 'cost') or la_obra_v2.num(b -> 'cost') < 0 then perform la_obra_v2.fail(422, 'Costo inválido'); end if;
  v_cost := round(la_obra_v2.num(b -> 'cost'), 4);
  update la_obra_v2.inputs set manual_cost = v_cost, manual_cost_at = localtimestamp where id = v_id;
  return la_obra_v2.ok(200, 'Costo actualizado', jsonb_build_object('unit_cost', v_cost::float8));
end $$;

-- ---------- Compras: guardan en qué unidad se compró (buy_unit) ----------
create or replace function la_obra_v2.valid_items(p_items jsonb)
returns jsonb language plpgsql as $$
declare it jsonb; v_id int; seen int[] := '{}'; inp record; v_q numeric; v_content numeric; v_cj jsonb; v_cost numeric; v_sub numeric;
        v_total numeric := 0; clean jsonb := '[]'; v_bu text;
begin
  if p_items is null or jsonb_typeof(p_items) not in ('array','object') or p_items in ('[]'::jsonb, '{}'::jsonb) then
    perform la_obra_v2.fail(422, 'Debes enviar al menos un insumo');
  end if;
  if jsonb_typeof(p_items) = 'object' then p_items := (select jsonb_agg(v) from jsonb_each(p_items) e(k, v)); end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it) <> 'object' then perform la_obra_v2.fail(422, 'Insumo inválido'); end if;
    v_id := la_obra_v2.positive_id(it -> 'input_id');
    if v_id = any(seen) then perform la_obra_v2.fail(422, 'No repitas el mismo insumo en una compra'); end if;
    seen := seen || v_id;
    select id, unit, package_quantity into inp from la_obra_v2.inputs where id = v_id and status = 'active';
    if inp.id is null then perform la_obra_v2.fail(404, 'Insumo no encontrado o inactivo'); end if;
    if not la_obra_v2.is_scalar(it -> 'quantity') or not la_obra_v2.is_num(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0
       or round(la_obra_v2.num(it -> 'quantity'), 3) <> la_obra_v2.num(it -> 'quantity') then
      perform la_obra_v2.fail(422, 'Cantidad inválida');
    end if;
    v_q := la_obra_v2.num(it -> 'quantity');
    v_bu := nullif(left(la_obra_v2.jstr(coalesce(it -> 'buy_unit', it -> 'package_type')), 30), '');
    v_cj := it -> 'content_per_package';
    if v_cj is null or jsonb_typeof(v_cj) = 'null' or (jsonb_typeof(v_cj) = 'string' and v_cj #>> '{}' = '') then
      v_content := case when v_bu is null or lower(v_bu) = lower(inp.unit) then 1 else inp.package_quantity end;
    else
      if not la_obra_v2.is_num(v_cj) or la_obra_v2.num(v_cj) <= 0 then perform la_obra_v2.fail(422, 'Contenido de presentación inválido'); end if;
      v_content := la_obra_v2.num(v_cj);
    end if;
    v_cost := la_obra_v2.money(it -> 'unit_cost', false);
    v_sub := round(v_q * v_cost, 2);
    v_total := v_total + v_sub;
    clean := clean || jsonb_build_object('input_id', v_id, 'quantity', round(v_q, 3), 'unit_cost', v_cost, 'subtotal', v_sub,
      'content_per_package', round(v_content, 3), 'content_unit', inp.unit, 'total_base_quantity', round(v_q * v_content, 3),
      'buy_unit', coalesce(v_bu, inp.unit));
  end loop;
  if v_total > 9999999999.99 then perform la_obra_v2.fail(422, 'Total excede el límite'); end if;
  return jsonb_build_object('items', clean, 'total', round(v_total, 2));
end $$;

create or replace function la_obra_v2.insert_purchase_items(p_id int, p_items jsonb)
returns void language sql as $$
  insert into la_obra_v2.purchase_items(purchase_id, input_id, quantity, unit_cost, subtotal, content_per_package, content_unit, total_base_quantity, buy_unit)
  select p_id, (i ->> 'input_id')::int, (i ->> 'quantity')::numeric, (i ->> 'unit_cost')::numeric, (i ->> 'subtotal')::numeric,
         (i ->> 'content_per_package')::numeric, i ->> 'content_unit', (i ->> 'total_base_quantity')::numeric, i ->> 'buy_unit'
    from jsonb_array_elements(p_items) with ordinality x(i, n) order by n;
$$;

-- Recordar la presentación (también cuando se compra en la unidad principal)
create or replace function la_obra_v2.remember_presentations(p_items jsonb)
returns void language plpgsql as $$
declare i jsonb; v_type text; v_c jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then return; end if;
  for i in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(i) <> 'object' then continue; end if;
    v_type := la_obra_v2.jstr(coalesce(i -> 'buy_unit', i -> 'package_type')); v_c := i -> 'content_per_package';
    if v_type = '' or char_length(v_type) > 40 or not la_obra_v2.is_int(i -> 'input_id') or la_obra_v2.num(i -> 'input_id') <= 0
       or not la_obra_v2.is_num(v_c) or la_obra_v2.num(v_c) <= 0 then continue; end if;
    update la_obra_v2.inputs set package_type = v_type, package_quantity = round(la_obra_v2.num(v_c), 3) where id = la_obra_v2.num(i -> 'input_id')::int;
  end loop;
end $$;

create or replace function la_obra_v2.purchase_json(p_id int, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  if p_lock then perform 1 from la_obra_v2.purchases where id = p_id for update; end if;
  select to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name, 'items', (
      select coalesce(jsonb_agg(jsonb_build_object('id', pi.id, 'input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit,
        'quantity', pi.quantity, 'unit_cost', pi.unit_cost, 'subtotal', pi.subtotal, 'content_per_package', pi.content_per_package,
        'content_unit', pi.content_unit, 'total_base_quantity', pi.total_base_quantity,
        'buy_unit', coalesce(pi.buy_unit, case when pi.content_per_package = 1 then i.unit end)) order by pi.id), '[]')
      from la_obra_v2.purchase_items pi join la_obra_v2.inputs i on i.id = pi.input_id where pi.purchase_id = p.id))
    into r from la_obra_v2.purchases p join la_obra_v2.users u on u.id = p.user_id join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
   where p.id = p_id;
  if r is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  return la_obra_v2.fix_dates(r);
end $$;

-- Al editar una compra sin mandar los artículos, se conservan con su unidad
create or replace function la_obra_v2.ep_purchases__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_old jsonb; merged jsonb; vp jsonb; v_buyer text; v_new jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  if not (b ?| array['purchase_date','supplier','buyer','payment_method_id','items']) then perform la_obra_v2.fail(422, 'No hay cambios para actualizar'); end if;
  v_old := la_obra_v2.purchase_json(v_id, true);
  merged := jsonb_build_object(
    'purchase_date', coalesce(nullif(b -> 'purchase_date', 'null'::jsonb), v_old -> 'purchase_date'),
    'supplier', case when b ? 'supplier' then b -> 'supplier' else v_old -> 'supplier' end,
    'payment_method_id', coalesce(nullif(b -> 'payment_method_id', 'null'::jsonb), v_old -> 'payment_method_id'),
    'items', coalesce(nullif(b -> 'items', 'null'::jsonb), (select coalesce(jsonb_agg(jsonb_build_object('input_id', i -> 'input_id', 'quantity', i -> 'quantity',
              'unit_cost', i -> 'unit_cost', 'content_per_package', i -> 'content_per_package', 'buy_unit', i -> 'buy_unit') order by n), '[]')
              from jsonb_array_elements(v_old -> 'items') with ordinality x(i, n))));
  vp := la_obra_v2.valid_purchase(merged);
  v_buyer := case when b ? 'buyer' then la_obra_v2.valid_buyer(b -> 'buyer') else v_old ->> 'buyer' end;
  update la_obra_v2.purchases set purchase_date = (vp ->> 'purchase_date')::date, supplier = vp ->> 'supplier', buyer = v_buyer,
         payment_method_id = (vp ->> 'payment_method_id')::int, total = (vp ->> 'total')::numeric, updated_at = localtimestamp where id = v_id;
  delete from la_obra_v2.purchase_items where purchase_id = v_id;
  perform la_obra_v2.insert_purchase_items(v_id, vp -> 'items');
  perform la_obra_v2.inv_sync_purchase(v_id, u.id);
  if b ? 'items' then perform la_obra_v2.remember_presentations(b -> 'items'); end if;
  v_new := la_obra_v2.purchase_json(v_id);
  insert into la_obra_v2.purchase_history(purchase_id, changed_by, previous_data, new_data, change_reason)
  values (v_id, u.id, v_old::text, v_new::text, case when b ? 'change_reason' and jsonb_typeof(b -> 'change_reason') <> 'null' then la_obra_v2.jstr(b -> 'change_reason') end);
  return la_obra_v2.ok(200, 'Compra actualizada; el inventario se recalculó', jsonb_build_object('purchase', v_new));
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
select 'Insumos con costo editable y unidades de compra listos' as resultado;
