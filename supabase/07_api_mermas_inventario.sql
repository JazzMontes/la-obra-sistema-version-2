-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 07 · API: mermas (waste/), inventario (inventory/), costos (costs/) y fotos (files/)
-- =====================================================================

-- Valida una fecha opcional de la URL con el mensaje "<campo>: fecha inválida"
create or replace function la_obra_v2.qdate(q jsonb, k text, p_required boolean default false)
returns date language plpgsql immutable as $$
declare t text := la_obra_v2.qp(q, k);
begin
  if t is null and not p_required then return null; end if;
  if not la_obra_v2.is_date(t) then perform la_obra_v2.fail(422, k || ': fecha inválida'); end if;
  return t::date;
end $$;

-- Mermas con nombre del elemento afectado y del usuario
create or replace function la_obra_v2.waste_row_json(w la_obra_v2.waste_records)
returns jsonb language sql stable as $$
  select to_jsonb(w) || jsonb_build_object(
    'affected_name', coalesce(i.name, p.name, pr.name),
    'affected_unit', case when w.affected_type = 'input' then i.unit else null end,
    'user_name', u.name)
  from (select 1) x
  left join la_obra_v2.inputs i on i.id = w.input_id
  left join la_obra_v2.products p on p.id = w.product_id
  left join la_obra_v2.preparations pr on pr.id = w.preparation_id
  left join la_obra_v2.users u on u.id = w.user_id
$$;

create or replace function la_obra_v2.waste_totals(d_from date, d_to date)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'records', count(*),
    'estimated_loss', coalesce(sum(case when cost_status = 'calculated' then estimated_total_cost else 0 end), 0),
    'without_cost', sum(case when cost_status = 'unavailable' then 1 else 0 end))
  from la_obra_v2.waste_records where waste_date between d_from and d_to
$$;

-- waste/index.php — el empleado solo consulta sus registros del día
create or replace function la_obra_v2.ep_waste__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  d_from date;
  d_to date;
  f_type text := la_obra_v2.qp(q, 'affected_type');
  f_class text := la_obra_v2.qp(q, 'classification');
  emp boolean;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_user(tok, false, null, true);
  emp := u.role = 'employee';
  d_from := la_obra_v2.qdate(q, 'date_from');
  d_to := la_obra_v2.qdate(q, 'date_to');
  if d_from is not null and d_to is not null and d_from > d_to then perform la_obra_v2.fail(422, 'Rango de fechas inválido'); end if;
  if f_type is not null and f_type not in ('input', 'product', 'preparation') then perform la_obra_v2.fail(422, 'Tipo inválido'); end if;
  if f_class is not null and char_length(f_class) > 100 then perform la_obra_v2.fail(422, 'Clasificación inválida'); end if;
  return jsonb_build_object('success', true, 'message', 'Mermas consultadas',
    'scope', case when emp then 'today_own' else 'all' end,
    'waste_records', coalesce((
      select jsonb_agg(la_obra_v2.waste_row_json(w) order by w.waste_date desc, w.id desc)
      from la_obra_v2.waste_records w
      where (d_from is null or w.waste_date >= d_from)
        and (d_to is null or w.waste_date <= d_to)
        and (f_type is null or w.affected_type = f_type)
        and (f_class is null or w.classification = f_class)
        and (not emp or (w.user_id = u.id and w.waste_date = la_obra_v2.today_mx()))
    ), '[]'::jsonb));
end $$;

-- waste/show.php
create or replace function la_obra_v2.ep_waste__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  w la_obra_v2.waste_records;
  wid integer;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_user(tok, false, null, true);
  if la_obra_v2.jstr(q -> 'id') !~ '^[1-9][0-9]*$' or not la_obra_v2.is_int(q -> 'id') then
    perform la_obra_v2.fail(422, 'Identificador inválido');
  end if;
  wid := la_obra_v2.int_of(q -> 'id');
  select * into w from la_obra_v2.waste_records where id = wid;
  if w.id is null then perform la_obra_v2.fail(404, 'Merma no encontrada'); end if;
  if u.role = 'employee' and (w.user_id <> u.id or w.waste_date <> la_obra_v2.today_mx()) then
    perform la_obra_v2.fail(403, 'No tienes acceso a este registro');
  end if;
  return jsonb_build_object('success', true, 'message', 'Detalle consultado', 'waste', la_obra_v2.waste_row_json(w));
end $$;

-- waste/create.php — calcula el costo con el motor de costos y descuenta el inventario
create or replace function la_obra_v2.ep_waste__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  v_type text := b ->> 'affected_type';
  aid integer;
  v_qty numeric;
  v_approx boolean := la_obra_v2.truthy(b -> 'is_approximate');
  v_date date;
  v_reason text := la_obra_v2.jtrim(b -> 'reason');
  v_class text := la_obra_v2.jtrim(b -> 'classification');
  v_unit_cost numeric;
  v_total_cost numeric;
  ok boolean;
  new_id integer;
  part record;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_user(tok);
  if v_type is null or v_type not in ('input', 'product', 'preparation') then perform la_obra_v2.fail(422, 'Tipo de elemento inválido'); end if;
  aid := la_obra_v2.pos_id(b -> 'affected_id');
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)',
                 case v_type when 'input' then 'inputs' when 'product' then 'products' else 'preparations' end)
    into ok using aid;
  if not ok then perform la_obra_v2.fail(404, 'Elemento afectado no encontrado'); end if;
  if not la_obra_v2.is_num(b -> 'quantity') or la_obra_v2.num(b -> 'quantity') <= 0 or la_obra_v2.num(b -> 'quantity') > 999999999 then
    perform la_obra_v2.fail(422, 'Cantidad inválida');
  end if;
  v_qty := round(la_obra_v2.num(b -> 'quantity'), 3);
  v_date := la_obra_v2.dateval(coalesce(nullif(b -> 'waste_date', 'null'::jsonb), to_jsonb(to_char(la_obra_v2.today_mx(), 'YYYY-MM-DD'))));
  if v_date > la_obra_v2.today_mx() then perform la_obra_v2.fail(422, 'La fecha no puede ser futura'); end if;
  if v_reason = '' or char_length(v_reason) > 500 then perform la_obra_v2.fail(422, 'Escribe el motivo (máximo 500 caracteres)'); end if;
  if v_class = '' or char_length(v_class) > 100 then perform la_obra_v2.fail(422, 'Elige una clasificación'); end if;

  -- Costo unitario: insumo = última compra; preparación = costo por porción; producto = costo estándar
  if v_type = 'input' then
    v_unit_cost := la_obra_v2.input_cost(aid);
  elsif v_type = 'preparation' then
    v_unit_cost := (la_obra_v2.preparation_cost(aid) ->> 'unit_cost')::numeric;
  else
    v_unit_cost := (la_obra_v2.product_cost(aid, 'local') ->> 'standard_cost')::numeric;
  end if;
  v_total_cost := case when v_unit_cost is null then null else round(v_unit_cost * v_qty, 2) end;

  insert into la_obra_v2.waste_records(affected_type, input_id, product_id, preparation_id, quantity, is_approximate, waste_date,
                                       reason, classification, estimated_unit_cost, estimated_total_cost, cost_status, user_id)
  values (v_type,
          case when v_type = 'input' then aid end,
          case when v_type = 'product' then aid end,
          case when v_type = 'preparation' then aid end,
          v_qty, v_approx, v_date, v_reason, v_class,
          case when v_unit_cost is null then null else round(v_unit_cost, 4) end,
          v_total_cost,
          case when v_unit_cost is null then 'unavailable' else 'calculated' end,
          u.id)
  returning id into new_id;

  for part in
    select aid as input_id, 1.0::numeric as qty where v_type = 'input'
    union all select * from la_obra_v2.inv_preparation_parts(aid) where v_type = 'preparation'
    union all select * from la_obra_v2.inv_product_parts(aid, 'local') where v_type = 'product'
  loop
    perform la_obra_v2.inv_record(part.input_id, 'waste', -part.qty * v_qty, la_obra_v2.input_cost(part.input_id),
                                  'waste', new_id, v_class, u.id);
  end loop;
  return la_obra_v2.ok('Merma registrada y descontada del inventario',
    jsonb_build_object('waste', jsonb_build_object('id', new_id, 'estimated_total_cost', v_total_cost)));
end $$;

-- waste/compare.php — dos periodos (solo admin)
create or replace function la_obra_v2.ep_waste__compare(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  p1s date; p1e date; p2s date; p2e date;
  t1 jsonb; t2 jsonb;
  diff numeric;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'Solo el administrador puede consultar esta información', true);
  p1s := la_obra_v2.qdate(q, 'period1_start', true);
  p1e := la_obra_v2.qdate(q, 'period1_end', true);
  p2s := la_obra_v2.qdate(q, 'period2_start', true);
  p2e := la_obra_v2.qdate(q, 'period2_end', true);
  if p1s > p1e or p2s > p2e then perform la_obra_v2.fail(422, 'El inicio no puede superar el final'); end if;
  t1 := la_obra_v2.waste_totals(p1s, p1e);
  t2 := la_obra_v2.waste_totals(p2s, p2e);
  diff := round((t2 ->> 'estimated_loss')::numeric - (t1 ->> 'estimated_loss')::numeric, 2);
  return jsonb_build_object('success', true, 'message', 'Comparación consultada', 'period1', t1, 'period2', t2,
    'difference', diff,
    'percentage_change', case when (t1 ->> 'estimated_loss')::numeric > 0
                              then round(diff / (t1 ->> 'estimated_loss')::numeric * 100, 2) else null end,
    'note', 'Los valores económicos excluyen pérdidas sin costo estimable');
end $$;

-- waste/indicators.php — merma contra ventas y compras del periodo (solo admin)
create or replace function la_obra_v2.ep_waste__indicators(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  d_from date; d_to date;
  w jsonb;
  loss numeric;
  revenue numeric;
  purchased numeric;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'Solo el administrador puede consultar esta información', true);
  d_from := la_obra_v2.qdate(q, 'date_from', true);
  d_to := la_obra_v2.qdate(q, 'date_to', true);
  if d_from > d_to then perform la_obra_v2.fail(422, 'El inicio no puede superar el final'); end if;
  w := la_obra_v2.waste_totals(d_from, d_to);
  loss := (w ->> 'estimated_loss')::numeric;
  select coalesce(sum(o.total), 0) into revenue from la_obra_v2.orders o
  where o.order_status = 'confirmed' and o.payment_status = 'paid'
    and exists (select 1 from la_obra_v2.payments pay where pay.order_id = o.id
                and pay.paid_at >= d_from and pay.paid_at < d_to + 1);
  select coalesce(sum(total), 0) into purchased from la_obra_v2.purchases where purchase_date between d_from and d_to;
  return jsonb_build_object('success', true, 'message', 'Indicadores consultados', 'waste', w,
    'sales_total', revenue, 'purchases_total', purchased,
    'loss_as_percent_of_sales', case when revenue > 0 then round(loss / revenue * 100, 2) else null end,
    'loss_as_percent_of_purchases', case when purchased > 0 then round(loss / purchased * 100, 2) else null end,
    'cost_basis', 'purchases_total es gasto en compras del periodo, no costo de ventas ni consumo real',
    'note', 'Los porcentajes se basan en pérdidas con costo calculable; los demás registros se cuentan por separado');
end $$;

-- waste/ranking.php — elementos con más pérdida (solo admin)
create or replace function la_obra_v2.ep_waste__ranking(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  d_from date; d_to date;
  f_type text := la_obra_v2.qp(q, 'affected_type');
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'Solo el administrador puede consultar esta información', true);
  d_from := la_obra_v2.qdate(q, 'date_from', true);
  d_to := la_obra_v2.qdate(q, 'date_to', true);
  if d_from > d_to then perform la_obra_v2.fail(422, 'El inicio no puede superar el final'); end if;
  if f_type is not null and f_type not in ('input', 'product', 'preparation') then perform la_obra_v2.fail(422, 'Tipo inválido'); end if;
  return jsonb_build_object('success', true, 'message', 'Ranking consultado', 'ranking', coalesce((
    select jsonb_agg(r order by (r ->> 'estimated_loss')::numeric desc, (r ->> 'records')::integer desc)
    from (
      select jsonb_build_object(
        'affected_type', w.affected_type, 'input_id', w.input_id, 'product_id', w.product_id, 'preparation_id', w.preparation_id,
        'affected_name', coalesce(i.name, p.name, pr.name),
        'affected_unit', case when w.affected_type = 'input' then i.unit else null end,
        'records', count(*), 'total_quantity', sum(w.quantity),
        'estimated_loss', coalesce(sum(case when w.cost_status = 'calculated' then w.estimated_total_cost else 0 end), 0),
        'without_cost', sum(case when w.cost_status = 'unavailable' then 1 else 0 end)) as r
      from la_obra_v2.waste_records w
      left join la_obra_v2.inputs i on i.id = w.input_id
      left join la_obra_v2.products p on p.id = w.product_id
      left join la_obra_v2.preparations pr on pr.id = w.preparation_id
      where w.waste_date between d_from and d_to and (f_type is null or w.affected_type = f_type)
      group by w.affected_type, w.input_id, w.product_id, w.preparation_id, i.name, p.name, pr.name, i.unit
    ) s), '[]'::jsonb),
    'note', 'Las cantidades solo se suman dentro de un mismo elemento; los costos no disponibles se reportan por separado');
end $$;

-- ---------------------------------------------------------------------
-- INVENTARIO
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.ep_inventory__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare items jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  items := la_obra_v2.inv_list();
  return la_obra_v2.ok('Inventario consultado', jsonb_build_object('inventory', items, 'summary', (
    select jsonb_build_object(
      'total_value', round(coalesce(sum(coalesce((x ->> 'stock_value')::numeric, 0)), 0), 2),
      'low', count(*) filter (where x ->> 'status' = 'active' and x ->> 'level' = 'low'),
      'out', count(*) filter (where x ->> 'status' = 'active' and x ->> 'level' = 'out'))
    from jsonb_array_elements(items) x)));
end $$;

-- inventory/movements.php — kárdex de un insumo (últimos 200)
create or replace function la_obra_v2.ep_inventory__movements(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  iid integer;
  inp jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  iid := la_obra_v2.pos_id(q -> 'input_id');
  select jsonb_build_object('id', id, 'name', name, 'unit', unit) into inp from la_obra_v2.inputs where id = iid;
  if inp is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok('Movimientos consultados', jsonb_build_object('input', inp, 'stock', la_obra_v2.inv_stock(iid),
    'movements', coalesce((
      select jsonb_agg(x order by o) from (
        select row_number() over (order by mv.created_at desc, mv.id desc) as o,
               jsonb_build_object('id', mv.id, 'movement_type', mv.movement_type, 'quantity', mv.quantity,
                 'unit_cost', mv.unit_cost, 'reference_type', mv.reference_type, 'reference_id', mv.reference_id,
                 'note', mv.note, 'created_at', mv.created_at, 'user_name', u.name) as x
        from la_obra_v2.inventory_movements mv left join la_obra_v2.users u on u.id = mv.user_id
        where mv.input_id = iid
        order by mv.created_at desc, mv.id desc
        limit 200) s), '[]'::jsonb)));
end $$;

-- inventory/adjust.php — conteo físico: registra la diferencia
create or replace function la_obra_v2.ep_inventory__adjust(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  iid integer;
  v_note text := la_obra_v2.jtrim(b -> 'note');
  before numeric;
  diff numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_user(tok, true);
  iid := la_obra_v2.pos_id(b -> 'input_id');
  if not exists (select 1 from la_obra_v2.inputs where id = iid) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  if not la_obra_v2.is_num(b -> 'counted_quantity') or la_obra_v2.num(b -> 'counted_quantity') < 0 then
    perform la_obra_v2.fail(422, 'Indica la cantidad contada');
  end if;
  if char_length(v_note) > 255 then perform la_obra_v2.fail(422, 'La nota es demasiado larga'); end if;
  before := la_obra_v2.inv_stock(iid);
  diff := round(la_obra_v2.num(b -> 'counted_quantity') - before, 3);
  if abs(diff) < 0.0005 then
    return la_obra_v2.ok('Sin diferencias: el inventario ya coincide', jsonb_build_object('stock', before, 'difference', 0));
  end if;
  perform la_obra_v2.inv_record(iid, 'adjustment', diff, la_obra_v2.input_cost(iid), 'adjustment', null,
                                coalesce(nullif(v_note, ''), 'Conteo físico'), u.id);
  return la_obra_v2.ok('Inventario ajustado', jsonb_build_object('stock', la_obra_v2.inv_stock(iid), 'difference', diff));
end $$;

-- ---------------------------------------------------------------------
-- COSTOS
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.ep_costs__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  v_mode text := coalesce(la_obra_v2.qp(q, 'delivery_mode'), 'local');
  list jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  if v_mode not in ('local', 'takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  select coalesce(jsonb_agg(c || jsonb_build_object('category_name', cat, 'image_path', img,
                                                    'has_recipe', jsonb_array_length(c -> 'components') > 0)
                            order by lower(cat), lower(nm)), '[]'::jsonb)
  into list
  from (
    select la_obra_v2.product_cost(p.id, v_mode) as c, ct.name as cat, p.image_path as img, p.name as nm
    from la_obra_v2.products p join la_obra_v2.categories ct on ct.id = p.category_id
    where p.status = 'active'
  ) s;
  return la_obra_v2.ok('Costos consultados', jsonb_build_object('products', list, 'summary', (
    select jsonb_build_object(
      'products', count(*),
      'without_recipe', count(*) filter (where not (x ->> 'has_recipe')::boolean),
      'missing_prices', count(*) filter (where (x ->> 'has_recipe')::boolean and not (x ->> 'complete')::boolean),
      'average_margin', round(avg((x ->> 'gross_margin')::numeric), 2))
    from jsonb_array_elements(list) x)));
end $$;

create or replace function la_obra_v2.ep_costs__product(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  v_mode text := coalesce(la_obra_v2.qp(q, 'delivery_mode'), 'local');
  r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(q -> 'product_id');
  if v_mode not in ('local', 'takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  r := la_obra_v2.product_cost(pid, v_mode);
  if r is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok('Costo consultado', jsonb_build_object('cost', r, 'product_cost', r));
end $$;

create or replace function la_obra_v2.ep_costs__detail(m text, q jsonb, b jsonb, tok text)
returns jsonb language sql as $$
  select la_obra_v2.ep_costs__product(m, q, b, tok)
$$;

-- ---------------------------------------------------------------------
-- FOTOS
-- files/image.php — devuelve la foto como data URL dentro de JSON
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.ep_files__image(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  v_path text := la_obra_v2.jstr(q -> 'path');
  f record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  if v_path !~ '^uploads/(products|tickets)/[A-Za-z0-9_.-]+$' then perform la_obra_v2.fail(422, 'Ruta de imagen inválida'); end if;
  select mime, data into f from la_obra_v2.files where path = v_path;
  if f.mime is null then perform la_obra_v2.fail(404, 'La imagen no existe en el servidor'); end if;
  return la_obra_v2.ok('Imagen', jsonb_build_object('data_url',
    'data:' || f.mime || ';base64,' || replace(encode(f.data, 'base64'), E'\n', '')));
end $$;
