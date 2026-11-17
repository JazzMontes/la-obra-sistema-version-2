-- =====================================================================
-- La Obra v2 · 09 · inventory/*, costs/*, dashboard/*
-- =====================================================================
set check_function_bodies = off;

create or replace function la_obra_v2.ep_inventory__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_items jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  v_items := la_obra_v2.inv_list();
  return la_obra_v2.ok(200, 'Inventario consultado', jsonb_build_object('inventory', v_items, 'summary', jsonb_build_object(
    'total_value', (select round(coalesce(sum((x ->> 'stock_value')::numeric), 0), 2) from jsonb_array_elements(v_items) x),
    'low', (select count(*) from jsonb_array_elements(v_items) x where x ->> 'status' = 'active' and x ->> 'level' = 'low'),
    'out', (select count(*) from jsonb_array_elements(v_items) x where x ->> 'status' = 'active' and x ->> 'level' = 'out'))));
end $$;

create or replace function la_obra_v2.ep_inventory__movements(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_input jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  v_id := la_obra_v2.positive_id(q -> 'input_id');
  select jsonb_build_object('id', id, 'name', name, 'unit', unit) into v_input from la_obra_v2.inputs where id = v_id;
  if v_input is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok(200, 'Movimientos consultados', jsonb_build_object('input', v_input, 'stock', la_obra_v2.inv_stock(v_id)::float8, 'movements', (
    select coalesce(jsonb_agg(x order by rn), '[]') from (
      select jsonb_build_object('id', mv.id, 'movement_type', mv.movement_type, 'quantity', mv.quantity::float8, 'unit_cost', mv.unit_cost::float8,
        'reference_type', mv.reference_type, 'reference_id', mv.reference_id, 'note', mv.note, 'created_at', mv.created_at, 'user_name', u.name) x,
        row_number() over (order by mv.created_at desc, mv.id desc) rn
      from la_obra_v2.inventory_movements mv left join la_obra_v2.users u on u.id = mv.user_id where mv.input_id = v_id
      order by mv.created_at desc, mv.id desc limit 200) s)));
end $$;

create or replace function la_obra_v2.ep_inventory__adjust(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_counted numeric; v_note text; v_before numeric; v_diff numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'input_id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  if not la_obra_v2.is_num(b -> 'counted_quantity') or la_obra_v2.num(b -> 'counted_quantity') < 0 then perform la_obra_v2.fail(422, 'Indica la cantidad contada'); end if;
  v_counted := la_obra_v2.num(b -> 'counted_quantity');
  v_note := la_obra_v2.jstr(b -> 'note');
  if char_length(v_note) > 255 then perform la_obra_v2.fail(422, 'La nota es demasiado larga'); end if;
  v_before := la_obra_v2.inv_stock(v_id);
  v_diff := round(v_counted - v_before, 3);
  if abs(v_diff) < 0.0005 then
    return la_obra_v2.ok(200, 'Sin diferencias: el inventario ya coincide', jsonb_build_object('stock', v_before::float8, 'difference', 0));
  end if;
  perform la_obra_v2.inv_record(v_id, 'adjustment', v_diff, la_obra_v2.input_cost(v_id), 'adjustment', null, coalesce(nullif(v_note, ''), 'Conteo físico'), u.id);
  return la_obra_v2.ok(200, 'Inventario ajustado', jsonb_build_object('stock', la_obra_v2.inv_stock(v_id)::float8, 'difference', v_diff::float8));
end $$;

-- inventory/count.php · POST {items: [{input_id, counted_quantity, unit_id?}], note?}
-- Captura de existencias: registra lo que hay HOY de varios insumos a la vez, aunque no tengan
-- compras ni costo registrado. Por cada insumo con diferencia se guarda un "Ajuste por conteo";
-- no toca compras, recetas ni costos. Los insumos que se dejan vacíos no se modifican.
create or replace function la_obra_v2.ep_inventory__count(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; it jsonb; v_id int; v_counted numeric; v_note text; v_before numeric; v_diff numeric; v_seen int[] := '{}';
        v_changed int := 0; v_same int := 0; un la_obra_v2.input_units;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  if jsonb_typeof(b -> 'items') is distinct from 'array' or jsonb_array_length(b -> 'items') = 0 then
    perform la_obra_v2.fail(422, 'Escribe la existencia de al menos un insumo');
  end if;
  v_note := la_obra_v2.jstr(b -> 'note');
  if char_length(v_note) > 255 then perform la_obra_v2.fail(422, 'La nota es demasiado larga'); end if;
  for it in select * from jsonb_array_elements(b -> 'items') loop
    v_id := la_obra_v2.positive_id(it -> 'input_id', 'Insumo inválido');
    if v_id = any(v_seen) then perform la_obra_v2.fail(422, 'Hay un insumo repetido en la captura'); end if;
    v_seen := v_seen || v_id;
    if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado: ' || v_id); end if;
    if not la_obra_v2.is_num(it -> 'counted_quantity') or la_obra_v2.num(it -> 'counted_quantity') < 0 then
      perform la_obra_v2.fail(422, 'Las existencias no pueden ser negativas');
    end if;
    v_counted := la_obra_v2.num(it -> 'counted_quantity');
    if la_obra_v2.not_empty(it -> 'unit_id') then
      select * into un from la_obra_v2.input_units where id = la_obra_v2.positive_id(it -> 'unit_id', 'Medida inválida');
      if un.id is null or un.input_id <> v_id then perform la_obra_v2.fail(422, 'La medida elegida no corresponde al insumo'); end if;
      v_counted := v_counted * un.base_amount / un.unit_amount;
    end if;
    v_before := la_obra_v2.inv_stock(v_id);
    v_diff := round(v_counted - v_before, 3);
    if abs(v_diff) < 0.0005 then v_same := v_same + 1; continue; end if;
    perform la_obra_v2.inv_record(v_id, 'adjustment', v_diff, la_obra_v2.input_cost(v_id), 'adjustment', null,
      coalesce(nullif(v_note, ''), 'Captura de existencias'), u.id);
    v_changed := v_changed + 1;
  end loop;
  return la_obra_v2.ok(200, case when v_changed = 0 then 'Sin cambios: las existencias ya coincidían'
                                 else 'Existencias guardadas: ' || v_changed || ' insumo(s) actualizado(s)' end,
    jsonb_build_object('updated', v_changed, 'unchanged', v_same));
end $$;

create or replace function la_obra_v2.cost_mode(q jsonb)
returns text language plpgsql as $$
declare v text := coalesce(la_obra_v2.jtext(q -> 'delivery_mode'), 'local');
begin
  if v not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  return v;
end $$;

create or replace function la_obra_v2.ep_costs__product(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_mode text; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'product_id');
  v_mode := la_obra_v2.cost_mode(q);
  r := la_obra_v2.product_cost(v_id, v_mode);
  if r is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok(200, 'Costo consultado', jsonb_build_object('cost', r, 'product_cost', r));
end $$;

create or replace function la_obra_v2.ep_costs__detail(m text, q jsonb, b jsonb, t text)
returns jsonb language sql as $$ select la_obra_v2.ep_costs__product(m, q, b, t); $$;

create or replace function la_obra_v2.ep_costs__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_mode text; v_list jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_mode := la_obra_v2.cost_mode(q);
  select coalesce(jsonb_agg(c || jsonb_build_object('category_name', s.category_name, 'image_path', s.image_path,
           'has_recipe', jsonb_array_length(c -> 'components') > 0) order by s.category_name, s.name, s.id), '[]')
    into v_list
    from (select p.id, p.name, p.image_path, cat.name as category_name from la_obra_v2.products p join la_obra_v2.categories cat on cat.id = p.category_id where p.status = 'active') s
    cross join lateral (select la_obra_v2.product_cost(s.id, v_mode) c) x;
  return la_obra_v2.ok(200, 'Costos consultados', jsonb_build_object('products', v_list, 'summary', jsonb_build_object(
    'products', jsonb_array_length(v_list),
    'without_recipe', (select count(*) from jsonb_array_elements(v_list) x where not (x ->> 'has_recipe')::boolean),
    'missing_prices', (select count(*) from jsonb_array_elements(v_list) x where (x ->> 'has_recipe')::boolean and not (x ->> 'complete')::boolean),
    'average_margin', (select round(avg((x ->> 'gross_margin')::numeric), 2) from jsonb_array_elements(v_list) x where jsonb_typeof(x -> 'gross_margin') = 'number'))));
end $$;

create or replace function la_obra_v2.ep_dashboard__summary(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_admin boolean; v_today record; v_yesterday numeric; v_pending record; v_top jsonb; v_data jsonb; v_stock jsonb; v_month date := date_trunc('month', current_date)::date;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  v_admin := u.role = 'admin';
  select count(*) as orders, coalesce(sum(o.total), 0) as sales,
         coalesce(sum((select sum(oi.quantity * coalesce(oi.standard_unit_cost, 0)) from la_obra_v2.order_items oi where oi.order_id = o.id)), 0) as cost
    into v_today from la_obra_v2.orders o
   where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date = current_date and (v_admin or o.user_id = u.id);
  select coalesce(sum(o.total), 0) into v_yesterday from la_obra_v2.orders o
   where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date = current_date - 1 and (v_admin or o.user_id = u.id);
  select count(*) filter (where payment_status = 'pending') as to_charge, count(*) filter (where delivery_status = 'pending') as to_deliver
    into v_pending from la_obra_v2.orders where order_status = 'confirmed' and (payment_status = 'pending' or delivery_status = 'pending');
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'quantity', quantity, 'revenue', revenue::float8) order by quantity desc, name), '[]') into v_top from (
    select p.name, sum(oi.quantity)::int as quantity, sum(oi.subtotal) as revenue
      from la_obra_v2.order_items oi join la_obra_v2.orders o on o.id = oi.order_id join la_obra_v2.products p on p.id = oi.product_id
     where o.order_status = 'confirmed' and o.created_at::date = current_date and (v_admin or o.user_id = u.id)
     group by p.id, p.name order by quantity desc, p.name limit 5) s;
  v_data := jsonb_build_object(
    'today', jsonb_build_object('sales', round(v_today.sales, 2)::float8, 'orders', v_today.orders,
      'average_ticket', case when v_today.orders > 0 then round(v_today.sales / v_today.orders, 2)::float8 else 0 end,
      'yesterday_sales', round(v_yesterday, 2)::float8),
    'pending', jsonb_build_object('to_charge', v_pending.to_charge, 'to_deliver', v_pending.to_deliver),
    'top_products', v_top);
  select coalesce(jsonb_agg(x order by x ->> 'level', x ->> 'name'), '[]') into v_stock
    from jsonb_array_elements(la_obra_v2.inv_list()) x where x ->> 'status' = 'active' and x ->> 'level' <> 'ok';
  v_data := v_data || jsonb_build_object(
    'stock_alerts', (select coalesce(jsonb_agg(jsonb_build_object('id', x -> 'id', 'name', x -> 'name', 'stock', x -> 'stock', 'unit', x -> 'unit',
                       'min_stock', x -> 'min_stock', 'level', x -> 'level') order by n), '[]')
                       from jsonb_array_elements(v_stock) with ordinality a(x, n) where n <= 6),
    'stock_alerts_total', jsonb_array_length(v_stock));
  if v_admin then
    v_data := jsonb_set(v_data, '{today,gross_profit}', to_jsonb(round(v_today.sales - v_today.cost, 2)::float8));
    v_data := v_data || jsonb_build_object('month', jsonb_build_object(
      'purchases', (select coalesce(sum(total), 0)::float8 from la_obra_v2.purchases where purchase_date >= v_month),
      'expenses', (select coalesce(sum(amount), 0)::float8 from la_obra_v2.expenses where status = 'active' and created_at::date >= v_month),
      'sales', (select coalesce(sum(total), 0)::float8 from la_obra_v2.orders where order_status = 'confirmed' and payment_status = 'paid' and created_at::date >= v_month)));
  end if;
  return la_obra_v2.ok(200, 'Resumen consultado', jsonb_build_object('summary', v_data));
end $$;
