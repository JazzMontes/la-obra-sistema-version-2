-- =====================================================================
-- La Obra v2 · 08 · purchases/* y expenses/*
-- =====================================================================
set check_function_bodies = off;

-- purchase($id) de service_helpers.php
create or replace function la_obra_v2.purchase_json(p_id int, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  if p_lock then perform 1 from la_obra_v2.purchases where id = p_id for update; end if;
  select to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name, 'items', (
      select coalesce(jsonb_agg(jsonb_build_object('id', pi.id, 'input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit,
        'quantity', pi.quantity, 'unit_cost', pi.unit_cost, 'subtotal', pi.subtotal, 'content_per_package', pi.content_per_package,
        'content_unit', pi.content_unit, 'total_base_quantity', pi.total_base_quantity) order by pi.id), '[]')
      from la_obra_v2.purchase_items pi join la_obra_v2.inputs i on i.id = pi.input_id where pi.purchase_id = p.id))
    into r from la_obra_v2.purchases p join la_obra_v2.users u on u.id = p.user_id join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
   where p.id = p_id;
  if r is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  return la_obra_v2.fix_dates(r);
end $$;

-- validItems(): devuelve {items:[...limpios], total}
create or replace function la_obra_v2.valid_items(p_items jsonb)
returns jsonb language plpgsql as $$
declare it jsonb; v_id int; seen int[] := '{}'; inp record; v_q numeric; v_content numeric; v_cj jsonb; v_cost numeric; v_sub numeric;
        v_total numeric := 0; clean jsonb := '[]';
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
    v_cj := it -> 'content_per_package';
    if v_cj is null or jsonb_typeof(v_cj) = 'null' or (jsonb_typeof(v_cj) = 'string' and v_cj #>> '{}' = '') then
      v_content := inp.package_quantity;
    else
      if not la_obra_v2.is_num(v_cj) or la_obra_v2.num(v_cj) <= 0 then perform la_obra_v2.fail(422, 'Contenido de presentación inválido'); end if;
      v_content := la_obra_v2.num(v_cj);
    end if;
    v_cost := la_obra_v2.money(it -> 'unit_cost', false);
    v_sub := round(v_q * v_cost, 2);
    v_total := v_total + v_sub;
    clean := clean || jsonb_build_object('input_id', v_id, 'quantity', round(v_q, 3), 'unit_cost', v_cost, 'subtotal', v_sub,
      'content_per_package', round(v_content, 3), 'content_unit', inp.unit, 'total_base_quantity', round(v_q * v_content, 3));
  end loop;
  if v_total > 9999999999.99 then perform la_obra_v2.fail(422, 'Total excede el límite'); end if;
  return jsonb_build_object('items', clean, 'total', round(v_total, 2));
end $$;

-- validPurchase(): {purchase_date, supplier, payment_method_id, items, total}
create or replace function la_obra_v2.valid_purchase(d jsonb)
returns jsonb language plpgsql as $$
declare v_date date; v_sup jsonb; v_pm int; vi jsonb;
begin
  v_date := la_obra_v2.dateval(d -> 'purchase_date');
  v_sup := d -> 'supplier';
  if v_sup is not null and jsonb_typeof(v_sup) <> 'null' and (jsonb_typeof(v_sup) <> 'string' or char_length(v_sup #>> '{}') > 150) then
    perform la_obra_v2.fail(422, 'Proveedor inválido');
  end if;
  v_pm := la_obra_v2.positive_id(d -> 'payment_method_id');
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_pm and status = 'active') then perform la_obra_v2.fail(404, 'Método de pago inexistente o inactivo'); end if;
  vi := la_obra_v2.valid_items(d -> 'items');
  return jsonb_build_object('purchase_date', v_date, 'supplier', case when jsonb_typeof(v_sup) = 'string' then v_sup else null end,
    'payment_method_id', v_pm, 'items', vi -> 'items', 'total', vi -> 'total');
end $$;

create or replace function la_obra_v2.valid_buyer(v jsonb)
returns text language plpgsql as $$
declare s text;
begin
  if v is null or jsonb_typeof(v) = 'null' then return null; end if;
  s := la_obra_v2.jstr(v);
  if s = '' then return null; end if;
  if char_length(s) > 100 then perform la_obra_v2.fail(422, 'Nombre del comprador demasiado largo'); end if;
  return s;
end $$;

create or replace function la_obra_v2.insert_purchase_items(p_id int, p_items jsonb)
returns void language sql as $$
  insert into la_obra_v2.purchase_items(purchase_id, input_id, quantity, unit_cost, subtotal, content_per_package, content_unit, total_base_quantity)
  select p_id, (i ->> 'input_id')::int, (i ->> 'quantity')::numeric, (i ->> 'unit_cost')::numeric, (i ->> 'subtotal')::numeric,
         (i ->> 'content_per_package')::numeric, i ->> 'content_unit', (i ->> 'total_base_quantity')::numeric
    from jsonb_array_elements(p_items) with ordinality x(i, n) order by n;
$$;

-- rememberPresentations(): guarda la presentación usada para prellenar la próxima compra
create or replace function la_obra_v2.remember_presentations(p_items jsonb)
returns void language plpgsql as $$
declare i jsonb; v_type text; v_c jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then return; end if;
  for i in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(i) <> 'object' then continue; end if;
    v_type := la_obra_v2.jstr(i -> 'package_type'); v_c := i -> 'content_per_package';
    if v_type = '' or char_length(v_type) > 40 or not la_obra_v2.is_int(i -> 'input_id') or la_obra_v2.num(i -> 'input_id') <= 0
       or not la_obra_v2.is_num(v_c) or la_obra_v2.num(v_c) <= 0 then continue; end if;
    update la_obra_v2.inputs set package_type = v_type, package_quantity = round(la_obra_v2.num(v_c), 3) where id = la_obra_v2.num(i -> 'input_id')::int;
  end loop;
end $$;

create or replace function la_obra_v2.ep_purchases__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_from date; v_to date;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  if la_obra_v2.qparam(q, 'date_from') is not null then v_from := la_obra_v2.dateval(q -> 'date_from'); end if;
  if la_obra_v2.qparam(q, 'date_to') is not null then v_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  return la_obra_v2.ok(200, 'Compras consultadas', jsonb_build_object('purchases', (
    select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name) order by p.purchase_date desc, p.id desc), '[]')
    from la_obra_v2.purchases p join la_obra_v2.users u on u.id = p.user_id join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where (v_from is null or p.purchase_date >= v_from) and (v_to is null or p.purchase_date <= v_to))));
end $$;

create or replace function la_obra_v2.ep_purchases__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  return la_obra_v2.ok(200, 'Compra consultada', jsonb_build_object('purchase', la_obra_v2.purchase_json(la_obra_v2.positive_id(q -> 'id'))));
end $$;

create or replace function la_obra_v2.ep_purchases__prices(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'input_id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok(200, 'Historial de precios consultado', jsonb_build_object('prices', (
    select coalesce(jsonb_agg(jsonb_build_object('input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit, 'purchase_id', p.id,
      'purchase_date', p.purchase_date, 'quantity', pi.quantity, 'unit_cost', pi.unit_cost) order by p.purchase_date desc, p.id desc, pi.id), '[]')
    from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id join la_obra_v2.inputs i on i.id = pi.input_id
    where pi.input_id = v_id)));
end $$;

create or replace function la_obra_v2.ep_purchases__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; vp jsonb; v_buyer text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  vp := la_obra_v2.valid_purchase(b);
  v_buyer := la_obra_v2.valid_buyer(b -> 'buyer');
  insert into la_obra_v2.purchases(purchase_date, supplier, buyer, payment_method_id, user_id, total)
  values ((vp ->> 'purchase_date')::date, vp ->> 'supplier', v_buyer, (vp ->> 'payment_method_id')::int, u.id, (vp ->> 'total')::numeric)
  returning id into v_id;
  perform la_obra_v2.insert_purchase_items(v_id, vp -> 'items');
  perform la_obra_v2.inv_sync_purchase(v_id, u.id);
  perform la_obra_v2.remember_presentations(b -> 'items');
  return la_obra_v2.ok(201, 'Compra registrada; el inventario se actualizó', jsonb_build_object('purchase', la_obra_v2.purchase_json(v_id)));
end $$;

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
              'unit_cost', i -> 'unit_cost', 'content_per_package', i -> 'content_per_package') order by n), '[]')
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

create or replace function la_obra_v2.ep_purchases__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_ticket text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select ticket_path into v_ticket from la_obra_v2.purchases where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  begin
    delete from la_obra_v2.inventory_movements where reference_type = 'purchase' and reference_id = v_id;
    delete from la_obra_v2.purchase_history where purchase_id = v_id;
    delete from la_obra_v2.purchase_items where purchase_id = v_id;
    delete from la_obra_v2.purchases where id = v_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'La compra tiene registros relacionados y no puede eliminarse');
  end;
  perform la_obra_v2.delete_file(v_ticket, 'tickets');
  return la_obra_v2.ok(200, 'Compra eliminada correctamente');
end $$;

create or replace function la_obra_v2.ep_purchases__upload_ticket(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text; v_path text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select ticket_path into v_old from la_obra_v2.purchases where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  v_path := la_obra_v2.save_image(b -> 'image', 'tickets', 'ticket_' || v_id);
  update la_obra_v2.purchases set ticket_path = v_path where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'tickets');
  return la_obra_v2.ok(200, 'Ticket guardado', jsonb_build_object('ticket_path', v_path));
end $$;

create or replace function la_obra_v2.ep_purchases__delete_ticket(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select ticket_path into v_old from la_obra_v2.purchases where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  update la_obra_v2.purchases set ticket_path = null where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'tickets');
  return la_obra_v2.ok(200, 'Ticket eliminado');
end $$;

-- ---------- Gastos ----------
create or replace function la_obra_v2.expense_json(p_id int, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  if p_lock then perform 1 from la_obra_v2.expenses where id = p_id for update; end if;
  select to_jsonb(e) || jsonb_build_object('user_name', u.name) into r
    from la_obra_v2.expenses e join la_obra_v2.users u on u.id = e.user_id where e.id = p_id;
  if r is null then perform la_obra_v2.fail(404, 'Gasto no encontrado'); end if;
  return la_obra_v2.fix_dates(r);
end $$;

create or replace function la_obra_v2.expense_access(e jsonb, u la_obra_v2.users)
returns void language plpgsql as $$
begin
  if u.role <> 'admin' and (e ->> 'user_id')::int <> u.id then perform la_obra_v2.fail(403, 'No puedes consultar o modificar gastos de otra persona'); end if;
end $$;

create or replace function la_obra_v2.ep_expenses__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_uid int; v_from date; v_to date; v_status text;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  if u.role <> 'employee' then
    if la_obra_v2.qparam(q, 'user_id') is not null then v_uid := la_obra_v2.positive_id(q -> 'user_id'); end if;
    if la_obra_v2.qparam(q, 'date_from') is not null then v_from := la_obra_v2.dateval(q -> 'date_from'); end if;
    if la_obra_v2.qparam(q, 'date_to') is not null then v_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  end if;
  v_status := la_obra_v2.jtext(la_obra_v2.qparam(q, 'status'));
  if v_status is not null and v_status not in ('active','cancelled') then perform la_obra_v2.fail(422, 'Estado inválido'); end if;
  return la_obra_v2.ok(200, 'Gastos consultados', jsonb_build_object('scope', case when u.role = 'admin' then 'all' else 'today_own' end, 'expenses', (
    select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('user_name', us.name) order by e.created_at desc, e.id desc), '[]')
    from la_obra_v2.expenses e join la_obra_v2.users us on us.id = e.user_id
    where (u.role <> 'employee' or (e.user_id = u.id and e.created_at::date = current_date))
      and (v_uid is null or e.user_id = v_uid) and (v_from is null or e.created_at::date >= v_from) and (v_to is null or e.created_at::date <= v_to)
      and (v_status is null or e.status = v_status))));
end $$;

create or replace function la_obra_v2.ep_expenses__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; e jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  v_id := la_obra_v2.positive_id(q -> 'id');
  e := la_obra_v2.expense_json(v_id);
  perform la_obra_v2.expense_access(e, u);
  if u.role = 'employee' and substr(e ->> 'created_at', 1, 10) <> to_char(current_date, 'YYYY-MM-DD') then
    perform la_obra_v2.fail(403, 'El empleado solo consulta gastos de su jornada actual');
  end if;
  if u.role = 'admin' then
    e := e || jsonb_build_object('history', (select coalesce(jsonb_agg(to_jsonb(h) order by h.changed_at desc, h.id desc), '[]') from la_obra_v2.expense_history h where h.expense_id = v_id));
  end if;
  return la_obra_v2.ok(200, 'Gasto consultado', jsonb_build_object('expense', e));
end $$;

create or replace function la_obra_v2.ep_expenses__history(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'id');
  perform la_obra_v2.expense_json(v_id);
  return la_obra_v2.ok(200, 'Historial consultado', jsonb_build_object('history', (
    select coalesce(jsonb_agg(to_jsonb(h) || jsonb_build_object('changed_by_name', u.name) order by h.changed_at desc, h.id desc), '[]')
    from la_obra_v2.expense_history h join la_obra_v2.users u on u.id = h.changed_by where h.expense_id = v_id)));
end $$;

create or replace function la_obra_v2.ep_expenses__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_amount numeric; v_reason text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_amount := la_obra_v2.money(b -> 'amount');
  v_reason := la_obra_v2.jstr(b -> 'reason');
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo inválido'); end if;
  insert into la_obra_v2.expenses(amount, reason, user_id, status) values (v_amount, v_reason, u.id, 'active') returning id into v_id;
  return la_obra_v2.ok(201, 'Gasto registrado correctamente', jsonb_build_object('expense', la_obra_v2.expense_json(v_id)));
end $$;

create or replace function la_obra_v2.ep_expenses__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_why text; v_old jsonb; v_amount numeric; v_reason text; v_new jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_why := la_obra_v2.jstr(b -> 'change_reason');
  if v_why = '' or char_length(v_why) > 255 then perform la_obra_v2.fail(422, 'El motivo de corrección es obligatorio'); end if;
  if not (b ? 'amount') and not (b ? 'reason') then perform la_obra_v2.fail(422, 'Debes enviar monto o motivo del gasto'); end if;
  v_old := la_obra_v2.expense_json(v_id, true);
  perform la_obra_v2.expense_access(v_old, u);
  if v_old ->> 'status' <> 'active' then perform la_obra_v2.fail(409, 'El gasto ya está cancelado'); end if;
  v_amount := case when b ? 'amount' then la_obra_v2.money(b -> 'amount') else (v_old ->> 'amount')::numeric end;
  v_reason := case when b ? 'reason' then la_obra_v2.jstr(b -> 'reason') else v_old ->> 'reason' end;
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo del gasto inválido'); end if;
  update la_obra_v2.expenses set amount = v_amount, reason = v_reason, updated_at = localtimestamp where id = v_id;
  v_new := la_obra_v2.expense_json(v_id);
  insert into la_obra_v2.expense_history(expense_id, action, previous_data, new_data, change_reason, changed_by)
  values (v_id, 'updated', v_old::text, v_new::text, v_why, u.id);
  return la_obra_v2.ok(200, 'Gasto actualizado correctamente', jsonb_build_object('expense', v_new));
end $$;

create or replace function la_obra_v2.ep_expenses__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_why text; v_old jsonb; v_new jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_why := la_obra_v2.jstr(b -> 'cancellation_reason');
  if v_why = '' or char_length(v_why) > 255 then perform la_obra_v2.fail(422, 'Motivo de cancelación obligatorio'); end if;
  v_old := la_obra_v2.expense_json(v_id, true);
  perform la_obra_v2.expense_access(v_old, u);
  if v_old ->> 'status' <> 'active' then perform la_obra_v2.fail(409, 'El gasto ya está cancelado'); end if;
  update la_obra_v2.expenses set status = 'cancelled', cancelled_by = u.id, cancelled_at = localtimestamp, cancellation_reason = v_why, updated_at = localtimestamp where id = v_id;
  v_new := la_obra_v2.expense_json(v_id);
  insert into la_obra_v2.expense_history(expense_id, action, previous_data, new_data, change_reason, changed_by)
  values (v_id, 'cancelled', v_old::text, v_new::text, v_why, u.id);
  return la_obra_v2.ok(200, 'Gasto cancelado correctamente', jsonb_build_object('expense', v_new));
end $$;
