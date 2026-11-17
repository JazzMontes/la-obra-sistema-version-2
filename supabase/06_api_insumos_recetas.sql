-- =====================================================================
-- La Obra v2 · 06 · inputs/*, recipes/*, preparations/*
-- =====================================================================
set check_function_bodies = off;

-- validInput() de service_helpers.php → (name, unit, package_type, package_quantity, min_stock)
create or replace function la_obra_v2.valid_input(d jsonb, out o_name text, out o_unit text, out o_ptype text, out o_pqty numeric, out o_min numeric)
language plpgsql as $$
declare v_qty jsonb; v_min jsonb;
begin
  o_name := la_obra_v2.jstr(d -> 'name'); o_unit := la_obra_v2.jstr(d -> 'unit');
  if o_name = '' or char_length(o_name) > 100 then perform la_obra_v2.fail(422, 'Escribe el nombre del insumo'); end if;
  if o_unit = '' or char_length(o_unit) > 20 then perform la_obra_v2.fail(422, 'Indica la unidad de medida'); end if;
  o_ptype := la_obra_v2.jstr(d -> 'package_type');
  if o_ptype = '' then o_ptype := o_unit; end if;
  if char_length(o_ptype) > 40 then perform la_obra_v2.fail(422, 'Presentación inválida'); end if;
  v_qty := coalesce(nullif(d -> 'package_quantity', 'null'::jsonb), '1'::jsonb);
  if not la_obra_v2.is_num(v_qty) or la_obra_v2.num(v_qty) <= 0 or la_obra_v2.num(v_qty) > 999999999 then
    perform la_obra_v2.fail(422, 'Indica cuántas unidades trae cada presentación');
  end if;
  o_pqty := round(la_obra_v2.num(v_qty), 3);
  v_min := d -> 'min_stock';
  if v_min is null or jsonb_typeof(v_min) = 'null' or (jsonb_typeof(v_min) = 'string' and v_min #>> '{}' = '') then
    o_min := null;
  else
    if not la_obra_v2.is_num(v_min) or la_obra_v2.num(v_min) < 0 then perform la_obra_v2.fail(422, 'Existencia mínima inválida'); end if;
    o_min := la_obra_v2.num(v_min);
  end if;
end $$;

create or replace function la_obra_v2.ep_inputs__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true);
  return la_obra_v2.ok(200, 'Insumos', jsonb_build_object('inputs', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'unit', unit, 'status', status, 'package_type', package_type,
      'package_quantity', package_quantity, 'package_content_unit', package_content_unit, 'min_stock', min_stock,
      'units', la_obra_v2.input_units_json(id)) order by name, id), '[]')
    from la_obra_v2.inputs)));
end $$;

create or replace function la_obra_v2.ep_inputs__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(q -> 'id') or la_obra_v2.num(q -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id')::int;
  select jsonb_build_object('id', id, 'name', name, 'unit', unit, 'status', status, 'package_type', package_type,
         'package_quantity', package_quantity, 'package_content_unit', package_content_unit, 'units', la_obra_v2.input_units_json(id))
    into r from la_obra_v2.inputs where id = v_id;
  if r is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok(200, 'Insumo', jsonb_build_object('input', r));
end $$;

create or replace function la_obra_v2.ep_inputs__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v record; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  select * into v from la_obra_v2.valid_input(b);
  if exists(select 1 from la_obra_v2.inputs where lower(name) = lower(v.o_name)) then perform la_obra_v2.fail(409, 'Ya existe un insumo con ese nombre'); end if;
  insert into la_obra_v2.inputs(name, unit, package_type, package_quantity, package_content_unit, min_stock, status)
  values (v.o_name, v.o_unit, v.o_ptype, v.o_pqty, v.o_unit, v.o_min, 'active') returning id into v_id;
  perform la_obra_v2.save_input_units(v_id, b -> 'units');
  return la_obra_v2.ok(201, 'Insumo registrado correctamente', jsonb_build_object('input', jsonb_build_object(
    'id', v_id, 'name', v.o_name, 'unit', v.o_unit, 'package_type', v.o_ptype, 'package_quantity', v.o_pqty::float8, 'min_stock', v.o_min, 'status', 'active',
    'stock', 0, 'unit_cost', null, 'stock_value', null, 'level', 'out', 'units', la_obra_v2.input_units_json(v_id))));
end $$;

create or replace function la_obra_v2.ep_inputs__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; o la_obra_v2.inputs; v record; merged jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select * into o from la_obra_v2.inputs where id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  merged := jsonb_build_object(
    'name', coalesce(nullif(b -> 'name', 'null'::jsonb), to_jsonb(o.name)),
    'unit', coalesce(nullif(b -> 'unit', 'null'::jsonb), to_jsonb(o.unit)),
    'package_type', coalesce(nullif(b -> 'package_type', 'null'::jsonb), to_jsonb(o.package_type)),
    'package_quantity', coalesce(nullif(b -> 'package_quantity', 'null'::jsonb), to_jsonb(o.package_quantity)),
    'min_stock', case when b ? 'min_stock' then b -> 'min_stock' else to_jsonb(o.min_stock) end);
  select * into v from la_obra_v2.valid_input(merged);
  if exists(select 1 from la_obra_v2.inputs where lower(name) = lower(v.o_name) and id <> v_id) then perform la_obra_v2.fail(409, 'Ya existe un insumo con ese nombre'); end if;
  update la_obra_v2.inputs set name = v.o_name, unit = v.o_unit, package_type = v.o_ptype, package_quantity = v.o_pqty,
         package_content_unit = v.o_unit, min_stock = v.o_min where id = v_id;
  if b ? 'units' then perform la_obra_v2.save_input_units(v_id, b -> 'units'); end if;
  return la_obra_v2.ok(200, 'Insumo actualizado correctamente', jsonb_build_object('units', la_obra_v2.input_units_json(v_id)));
end $$;

create or replace function la_obra_v2.ep_inputs__activate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  update la_obra_v2.inputs set status = 'active' where id = v_id;
  return la_obra_v2.ok(200, 'Insumo activado correctamente');
end $$;

create or replace function la_obra_v2.ep_inputs__deactivate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.inputs where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  if v_status <> 'active' then perform la_obra_v2.fail(422, 'El insumo ya está inactivo'); end if;
  update la_obra_v2.inputs set status = 'inactive' where id = v_id;
  return la_obra_v2.ok(200, 'Insumo desactivado correctamente');
end $$;

create or replace function la_obra_v2.ep_inputs__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  if exists(select 1 from la_obra_v2.inventory_movements where input_id = v_id)
     or exists(select 1 from la_obra_v2.purchase_items where input_id = v_id)
     or exists(select 1 from la_obra_v2.product_components where input_id = v_id)
     or exists(select 1 from la_obra_v2.preparation_inputs where input_id = v_id) then
    perform la_obra_v2.fail(409, 'Este insumo ya tiene compras, recetas o movimientos de inventario. Desactívalo para conservar el historial.');
  end if;
  return la_obra_v2.delete_or_conflict('inputs', v_id);
end $$;

-- inputs/dependencies.php?type=input|product|preparation|...&id=N
create or replace function la_obra_v2.ep_inputs__dependencies(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_type text := coalesce(la_obra_v2.jtext(q -> 'type'), 'input'); v_id int; v_table text; v_found boolean; rel jsonb := '[]';
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'id');
  v_table := case v_type when 'input' then 'inputs' when 'product' then 'products' when 'preparation' then 'preparations'
    when 'waste' then 'waste_records' when 'recipe' then 'recipes' when 'component' then 'product_components'
    when 'preparation_input' then 'preparation_inputs' when 'purchase_item' then 'purchase_items' when 'order_item' then 'order_items' end;
  if v_table is null then perform la_obra_v2.fail(422, 'Tipo de registro inválido'); end if;
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)', v_table) into v_found using v_id;
  if not v_found then perform la_obra_v2.fail(404, 'El registro ya no existe'); end if;

  if v_type = 'input' then
    select coalesce(jsonb_agg(x order by n), '[]') into rel from (
      select 1 n, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Producto que utiliza el insumo','deletable',true) x from la_obra_v2.recipes r join la_obra_v2.products p on p.id = r.product_id where r.input_id = v_id
      union all select 2, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Componente de producto','deletable',true) from la_obra_v2.product_components pc join la_obra_v2.products p on p.id = pc.product_id where pc.input_id = v_id
      union all select 3, jsonb_build_object('type','preparation','id',pr.id,'label',pr.name,'detail','Preparación que utiliza el insumo','deletable',true) from la_obra_v2.preparation_inputs pi join la_obra_v2.preparations pr on pr.id = pi.preparation_id where pi.input_id = v_id
      union all select 4, jsonb_build_object('type','waste','id',w.id,'label','Merma del ' || w.waste_date,'detail','Registro de merma','deletable',true) from la_obra_v2.waste_records w where w.input_id = v_id
      union all select 5, jsonb_build_object('type','purchase_item','id',pi.id,'label','Compra del ' || p.purchase_date,'detail','Movimiento histórico de compra','deletable',false) from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id where pi.input_id = v_id
    ) s;
  elsif v_type = 'product' then
    select coalesce(jsonb_agg(x order by n), '[]') into rel from (
      select 1 n, jsonb_build_object('type','recipe','id',r.id,'label','Ingrediente de receta #' || r.id,'detail','Relación con insumo','deletable',true) x from la_obra_v2.recipes r where r.product_id = v_id
      union all select 2, jsonb_build_object('type','component','id',pc.id,'label','Componente #' || pc.id,'detail','Composición del producto','deletable',true) from la_obra_v2.product_components pc where pc.product_id = v_id
      union all select 3, jsonb_build_object('type','waste','id',w.id,'label','Merma del ' || w.waste_date,'detail','Registro de merma','deletable',true) from la_obra_v2.waste_records w where w.product_id = v_id
      union all select 4, jsonb_build_object('type','order_item','id',oi.id,'label','Venta #' || oi.order_id,'detail','Historial de venta protegido','deletable',false) from la_obra_v2.order_items oi where oi.product_id = v_id
    ) s;
  elsif v_type = 'preparation' then
    select coalesce(jsonb_agg(x order by n), '[]') into rel from (
      select 1 n, jsonb_build_object('type','preparation_input','id',pi.id,'label','Ingrediente de preparación #' || pi.id,'detail','Componente de preparación','deletable',true) x from la_obra_v2.preparation_inputs pi where pi.preparation_id = v_id
      union all select 2, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Producto que utiliza la preparación','deletable',true) from la_obra_v2.product_components pc join la_obra_v2.products p on p.id = pc.product_id where pc.preparation_id = v_id
      union all select 3, jsonb_build_object('type','waste','id',w.id,'label','Merma del ' || w.waste_date,'detail','Registro de merma','deletable',true) from la_obra_v2.waste_records w where w.preparation_id = v_id
    ) s;
  end if;
  -- Quitar repetidos (mismo tipo e id): se queda el último, como en PHP
  select coalesce(jsonb_agg(x order by first_n), '[]') into rel from (
    select distinct on (x ->> 'type', x ->> 'id') x, min(n) over (partition by x ->> 'type', x ->> 'id') first_n, n
      from jsonb_array_elements(rel) with ordinality a(x, n) order by x ->> 'type', x ->> 'id', n desc) d;
  return la_obra_v2.ok(200, 'Relaciones consultadas', jsonb_build_object('type', v_type, 'id', v_id, 'relations', rel));
end $$;

create or replace function la_obra_v2.ep_inputs__delete_related(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_type text; v_id int; v_table text; v_found boolean;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_type := coalesce(la_obra_v2.jtext(b -> 'type'), '');
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_table := case v_type when 'input' then 'inputs' when 'product' then 'products' when 'preparation' then 'preparations'
    when 'waste' then 'waste_records' when 'recipe' then 'recipes' when 'component' then 'product_components'
    when 'preparation_input' then 'preparation_inputs' end;
  if v_table is null then perform la_obra_v2.fail(422, 'Tipo de registro no permitido'); end if;
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)', v_table) into v_found using v_id;
  if not v_found then perform la_obra_v2.fail(404, 'El registro ya no existe'); end if;
  begin
    execute format('delete from la_obra_v2.%I where id = $1', v_table) using v_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'Este registro todavía tiene relaciones. Revisa la lista y elimínalas individualmente.');
  end;
  return la_obra_v2.ok(200, 'Registro eliminado correctamente', jsonb_build_object('type', v_type, 'id', v_id));
end $$;

-- ---------- Recetas (tabla recipes, formato anterior) ----------
create or replace function la_obra_v2.recipe_items_check(p_inputs jsonb)
returns void language plpgsql as $$
declare i jsonb; v_iid int; v_st text;
begin
  for i in select * from jsonb_array_elements(p_inputs) loop
    if not la_obra_v2.is_int(i -> 'input_id') or la_obra_v2.num(i -> 'input_id') <= 0 or not la_obra_v2.is_num(i -> 'quantity') or la_obra_v2.num(i -> 'quantity') <= 0 then
      perform la_obra_v2.fail(422, 'Datos de insumo inválidos');
    end if;
    v_iid := la_obra_v2.num(i -> 'input_id')::int;
    select status into v_st from la_obra_v2.inputs where id = v_iid;
    if v_st is null then perform la_obra_v2.fail(404, 'Insumo no encontrado: ' || v_iid); end if;
    if v_st <> 'active' then perform la_obra_v2.fail(422, 'El insumo ' || v_iid || ' está inactivo'); end if;
  end loop;
end $$;

create or replace function la_obra_v2.ep_recipes__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_pid int; v_type text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.num(b -> 'product_id') <= 0 or jsonb_typeof(b -> 'inputs') is distinct from 'array' or jsonb_array_length(b -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Producto e insumos válidos son obligatorios');
  end if;
  v_pid := la_obra_v2.num(b -> 'product_id')::int;
  select type into v_type from la_obra_v2.products where id = v_pid;
  if v_type is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_type <> 'prepared' then perform la_obra_v2.fail(422, 'Solo los productos preparados pueden tener receta'); end if;
  if exists(select 1 from la_obra_v2.recipes where product_id = v_pid) then perform la_obra_v2.fail(409, 'El producto ya tiene una receta registrada'); end if;
  perform la_obra_v2.recipe_items_check(b -> 'inputs');
  insert into la_obra_v2.recipes(product_id, input_id, quantity)
  select v_pid, la_obra_v2.num(i -> 'input_id')::int, round(la_obra_v2.num(i -> 'quantity'), 3) from jsonb_array_elements(b -> 'inputs') i;
  return la_obra_v2.ok(201, 'Receta registrada correctamente');
end $$;

create or replace function la_obra_v2.ep_recipes__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_pid int; v_type text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.num(b -> 'product_id') <= 0 or jsonb_typeof(b -> 'inputs') is distinct from 'array' or jsonb_array_length(b -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Producto e insumos válidos son obligatorios');
  end if;
  v_pid := la_obra_v2.num(b -> 'product_id')::int;
  select type into v_type from la_obra_v2.products where id = v_pid;
  if v_type is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_type <> 'prepared' then perform la_obra_v2.fail(422, 'Solo los productos preparados pueden tener receta'); end if;
  if not exists(select 1 from la_obra_v2.recipes where product_id = v_pid) then perform la_obra_v2.fail(404, 'Receta no encontrada'); end if;
  perform la_obra_v2.recipe_items_check(b -> 'inputs');
  delete from la_obra_v2.recipes where product_id = v_pid;
  insert into la_obra_v2.recipes(product_id, input_id, quantity)
  select v_pid, la_obra_v2.num(i -> 'input_id')::int, round(la_obra_v2.num(i -> 'quantity'), 3) from jsonb_array_elements(b -> 'inputs') i;
  return la_obra_v2.ok(200, 'Receta actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_recipes__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_pid int; p record; v_rows jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(q -> 'product_id') or la_obra_v2.num(q -> 'product_id') <= 0 then perform la_obra_v2.fail(422, 'El id del producto no es válido'); end if;
  v_pid := la_obra_v2.num(q -> 'product_id')::int;
  select id, name, type into p from la_obra_v2.products where id = v_pid;
  if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if p.type <> 'prepared' then perform la_obra_v2.fail(422, 'El producto no es de tipo prepared'); end if;
  select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'quantity', r.quantity::float8, 'unit', i.unit) order by i.name)
    into v_rows from la_obra_v2.recipes r join la_obra_v2.inputs i on i.id = r.input_id where r.product_id = v_pid;
  if v_rows is null then perform la_obra_v2.fail(404, 'El producto no tiene receta registrada'); end if;
  return la_obra_v2.ok(200, 'Receta', jsonb_build_object('recipe', jsonb_build_object('product', jsonb_build_object('id', p.id, 'name', p.name), 'inputs', v_rows)));
end $$;

-- ---------- Preparaciones ----------
create or replace function la_obra_v2.ep_preparations__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  return la_obra_v2.ok(200, 'Preparaciones consultadas', jsonb_build_object('preparations', (
    select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object(
      'yield_quantity', p.yield_quantity::float8,
      'inputs', (select coalesce(jsonb_agg(jsonb_build_object('input_id', pi.input_id, 'quantity', pi.quantity::float8, 'is_estimated', pi.is_estimated,
                   'name', i.name, 'unit', i.unit, 'unit_id', pi.unit_id, 'unit_quantity', pi.unit_quantity::float8, 'unit_name', un.name) order by i.name), '[]')
                   from la_obra_v2.preparation_inputs pi join la_obra_v2.inputs i on i.id = pi.input_id
                   left join la_obra_v2.input_units un on un.id = pi.unit_id where pi.preparation_id = p.id),
      'batch_cost', c -> 'batch_cost', 'unit_cost', c -> 'unit_cost', 'missing_prices', coalesce(c -> 'missing', '[]'))
      order by p.name, p.id), '[]')
    from la_obra_v2.preparations p cross join lateral (select la_obra_v2.preparation_cost(p.id) c) x)));
end $$;

create or replace function la_obra_v2.prep_validate(d jsonb, out o_name text, out o_desc text, out o_yield numeric, out o_unit text)
language plpgsql as $$
declare i jsonb; v_iid int; seen int[] := '{}';
begin
  o_name := la_obra_v2.jstr(d -> 'name'); o_desc := la_obra_v2.jstr(d -> 'description');
  o_unit := la_obra_v2.jtext(d -> 'yield_unit');
  if o_name = '' or char_length(o_name) > 120 or char_length(o_desc) > 255 or not la_obra_v2.is_num(d -> 'yield_quantity')
     or la_obra_v2.num(d -> 'yield_quantity') <= 0 or (d -> 'yield_unit') is null or jsonb_typeof(d -> 'yield_unit') <> 'string'
     or o_unit not in ('portion','piece','g','ml') or jsonb_typeof(d -> 'inputs') is distinct from 'array' or jsonb_array_length(d -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Nombre, rendimiento e ingredientes válidos son obligatorios');
  end if;
  o_yield := round(la_obra_v2.num(d -> 'yield_quantity'), 3);
  for i in select * from jsonb_array_elements(d -> 'inputs') loop
    v_iid := la_obra_v2.positive_id(i -> 'input_id');
    if v_iid = any(seen) or not la_obra_v2.is_num(coalesce(nullif(i -> 'unit_quantity', 'null'::jsonb), i -> 'quantity'))
       or la_obra_v2.num(coalesce(nullif(i -> 'unit_quantity', 'null'::jsonb), i -> 'quantity')) <= 0 then
      perform la_obra_v2.fail(422, 'Insumos duplicados o cantidades inválidas');
    end if;
    seen := seen || v_iid;
    if not exists(select 1 from la_obra_v2.inputs where id = v_iid and status = 'active') then perform la_obra_v2.fail(422, 'Insumo inexistente o inactivo'); end if;
    perform la_obra_v2.item_quantity(v_iid, i);  -- valida la medida (pieza, cucharada…) si viene
  end loop;
end $$;

-- Cada ingrediente se guarda en la unidad principal (quantity) y, si se capturó en otra medida,
-- también la medida y la cantidad tal como se escribió (unit_id, unit_quantity).
create or replace function la_obra_v2.prep_save_inputs(p_id int, d jsonb)
returns void language plpgsql as $$
declare i jsonb; n bigint; v_iid int; v_qty numeric; v_uid int; v_uqty numeric;
begin
  delete from la_obra_v2.preparation_inputs where preparation_id = p_id;
  for i, n in select x.i, x.n from jsonb_array_elements(d -> 'inputs') with ordinality x(i, n) order by x.n loop
    v_iid := la_obra_v2.num(i -> 'input_id')::int;
    select o_qty, o_unit_id, o_unit_qty into v_qty, v_uid, v_uqty from la_obra_v2.item_quantity(v_iid, i);
    insert into la_obra_v2.preparation_inputs(preparation_id, input_id, quantity, is_estimated, unit_id, unit_quantity)
    values (p_id, v_iid, v_qty, la_obra_v2.not_empty(i -> 'is_estimated'), v_uid, v_uqty);
  end loop;
end $$;

create or replace function la_obra_v2.ep_preparations__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v record; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  select * into v from la_obra_v2.prep_validate(b);
  insert into la_obra_v2.preparations(name, description, yield_quantity, yield_unit, yield_estimated)
  values (v.o_name, v.o_desc, v.o_yield, v.o_unit, la_obra_v2.not_empty(b -> 'yield_estimated')) returning id into v_id;
  perform la_obra_v2.prep_save_inputs(v_id, b);
  return la_obra_v2.ok(200, 'Preparación guardada', jsonb_build_object('id', v_id));
end $$;

create or replace function la_obra_v2.ep_preparations__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v record; v_id int;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select * into v from la_obra_v2.prep_validate(b);
  if not exists(select 1 from la_obra_v2.preparations where id = v_id) then perform la_obra_v2.fail(404, 'Preparación no encontrada'); end if;
  update la_obra_v2.preparations set name = v.o_name, description = v.o_desc, yield_quantity = v.o_yield, yield_unit = v.o_unit,
         yield_estimated = la_obra_v2.not_empty(b -> 'yield_estimated'), updated_at = localtimestamp where id = v_id;
  perform la_obra_v2.prep_save_inputs(v_id, b);
  return la_obra_v2.ok(200, 'Preparación guardada', jsonb_build_object('id', v_id));
end $$;

create or replace function la_obra_v2.ep_preparations__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  perform 1 from la_obra_v2.preparations where id = v_id for update;
  if not found then perform la_obra_v2.fail(404, 'La preparación no existe o ya fue eliminada'); end if;
  if exists(select 1 from la_obra_v2.product_components where preparation_id = v_id) then
    perform la_obra_v2.fail(409, 'No se puede eliminar: esta preparación está utilizada en un producto. Retírala de la composición del producto antes de eliminarla.');
  end if;
  begin
    delete from la_obra_v2.preparation_inputs where preparation_id = v_id;
    delete from la_obra_v2.preparations where id = v_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque la preparación está relacionada con otros registros o con el historial.');
  end;
  return la_obra_v2.ok(200, 'Preparación eliminada correctamente', jsonb_build_object('id', v_id));
end $$;
