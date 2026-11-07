-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 06 · API: compras (purchases/) y gastos (expenses/)
-- =====================================================================

-- purchases/index.php
create or replace function la_obra_v2.ep_purchases__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  d_from date;
  d_to date;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  if la_obra_v2.qp(q, 'date_from') is not null then d_from := la_obra_v2.dateval(q -> 'date_from'); end if;
  if la_obra_v2.qp(q, 'date_to') is not null then d_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  return la_obra_v2.ok('Compras consultadas', jsonb_build_object('purchases', coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name)
                     order by p.purchase_date desc, p.id desc)
    from la_obra_v2.purchases p
    join la_obra_v2.users u on u.id = p.user_id
    join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where (d_from is null or p.purchase_date >= d_from) and (d_to is null or p.purchase_date <= d_to)
  ), '[]'::jsonb)));
end $$;

-- purchases/show.php
create or replace function la_obra_v2.ep_purchases__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  return la_obra_v2.ok('Compra consultada', jsonb_build_object('purchase', la_obra_v2.purchase_json(la_obra_v2.pos_id(q -> 'id'))));
end $$;

-- purchases/prices.php — historial de precios de un insumo
create or replace function la_obra_v2.ep_purchases__prices(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare iid integer;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  iid := la_obra_v2.pos_id(q -> 'input_id');
  if not exists (select 1 from la_obra_v2.inputs where id = iid) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok('Historial de precios consultado', jsonb_build_object('prices', coalesce((
    select jsonb_agg(jsonb_build_object('input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit, 'purchase_id', p.id,
                                        'purchase_date', p.purchase_date, 'quantity', pi.quantity, 'unit_cost', pi.unit_cost)
                     order by p.purchase_date desc, p.id desc)
    from la_obra_v2.purchase_items pi
    join la_obra_v2.purchases p on p.id = pi.purchase_id
    join la_obra_v2.inputs i on i.id = pi.input_id
    where pi.input_id = iid), '[]'::jsonb)));
end $$;

-- purchases/create.php — cada renglón entra al inventario y alimenta los costos
create or replace function la_obra_v2.ep_purchases__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  v jsonb;
  v_buyer text;
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_user(tok, true);
  v := la_obra_v2.valid_purchase(b);
  v_buyer := la_obra_v2.valid_buyer(b -> 'buyer');
  insert into la_obra_v2.purchases(purchase_date, supplier, buyer, payment_method_id, user_id, total)
  values ((v ->> 'purchase_date')::date, v ->> 'supplier', v_buyer, (v ->> 'payment_method_id')::integer, u.id, (v ->> 'total')::numeric)
  returning id into new_id;
  perform la_obra_v2.insert_items(new_id, v -> 'items');
  perform la_obra_v2.inv_sync_purchase(new_id, u.id);
  perform la_obra_v2.remember_presentations(b -> 'items');
  return la_obra_v2.ok('Compra registrada; el inventario se actualizó', jsonb_build_object('purchase', la_obra_v2.purchase_json(new_id)));
end $$;

-- purchases/update.php — guarda el antes y el después y rehace el inventario
create or replace function la_obra_v2.ep_purchases__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  pid integer;
  old jsonb;
  merged jsonb;
  v jsonb;
  v_buyer text;
  nw jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  if not (b ?| array['purchase_date', 'supplier', 'buyer', 'payment_method_id', 'items']) then
    perform la_obra_v2.fail(422, 'No hay cambios para actualizar');
  end if;
  old := la_obra_v2.fix_ts(la_obra_v2.purchase_json(pid, true));
  merged := jsonb_build_object(
    'purchase_date', coalesce(nullif(b -> 'purchase_date', 'null'::jsonb), old -> 'purchase_date'),
    'supplier', case when b ? 'supplier' then b -> 'supplier' else old -> 'supplier' end,
    'payment_method_id', coalesce(nullif(b -> 'payment_method_id', 'null'::jsonb), old -> 'payment_method_id'),
    'items', coalesce(nullif(b -> 'items', 'null'::jsonb), (
      select coalesce(jsonb_agg(jsonb_build_object('input_id', i -> 'input_id', 'quantity', i -> 'quantity',
                                                   'unit_cost', i -> 'unit_cost', 'content_per_package', i -> 'content_per_package')
                                order by o), '[]'::jsonb)
      from jsonb_array_elements(old -> 'items') with ordinality e(i, o))));
  v := la_obra_v2.valid_purchase(merged);
  v_buyer := case when b ? 'buyer' then la_obra_v2.valid_buyer(b -> 'buyer') else old ->> 'buyer' end;
  update la_obra_v2.purchases
  set purchase_date = (v ->> 'purchase_date')::date, supplier = v ->> 'supplier', buyer = v_buyer,
      payment_method_id = (v ->> 'payment_method_id')::integer, total = (v ->> 'total')::numeric,
      updated_at = la_obra_v2.now_mx()
  where id = pid;
  delete from la_obra_v2.purchase_items where purchase_id = pid;
  perform la_obra_v2.insert_items(pid, v -> 'items');
  perform la_obra_v2.inv_sync_purchase(pid, u.id);
  if b ? 'items' then perform la_obra_v2.remember_presentations(b -> 'items'); end if;
  nw := la_obra_v2.fix_ts(la_obra_v2.purchase_json(pid));
  insert into la_obra_v2.purchase_history(purchase_id, changed_by, previous_data, new_data, change_reason)
  values (pid, u.id, old::text, nw::text, case when b ? 'change_reason' and jsonb_typeof(b -> 'change_reason') <> 'null'
                                              then la_obra_v2.jtrim(b -> 'change_reason') else null end);
  return la_obra_v2.ok('Compra actualizada; el inventario se recalculó', jsonb_build_object('purchase', nw));
end $$;

-- purchases/delete.php — compra, renglones, historial, inventario y foto del ticket
create or replace function la_obra_v2.ep_purchases__delete(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  found_id integer;
  ticket text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  select id, ticket_path into found_id, ticket from la_obra_v2.purchases where id = pid;
  if found_id is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  begin
    delete from la_obra_v2.inventory_movements where reference_type = 'purchase' and reference_id = pid;
    delete from la_obra_v2.purchase_history where purchase_id = pid;
    delete from la_obra_v2.purchase_items where purchase_id = pid;
    delete from la_obra_v2.purchases where id = pid;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'La compra tiene registros relacionados y no puede eliminarse');
  end;
  perform la_obra_v2.delete_upload(ticket, 'tickets');
  return la_obra_v2.ok('Compra eliminada correctamente');
end $$;

-- purchases/upload-ticket.php — antes multipart; ahora {id, image: data URL}
create or replace function la_obra_v2.ep_purchases__upload_ticket(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  found_id integer;
  old text;
  path text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  select id, ticket_path into found_id, old from la_obra_v2.purchases where id = pid;
  if found_id is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  path := la_obra_v2.save_image(b -> 'image', 'tickets', 'ticket_' || pid);
  update la_obra_v2.purchases set ticket_path = path where id = pid;
  perform la_obra_v2.delete_upload(old, 'tickets');
  return la_obra_v2.ok('Ticket guardado', jsonb_build_object('ticket_path', path));
end $$;

-- purchases/delete-ticket.php
create or replace function la_obra_v2.ep_purchases__delete_ticket(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  found_id integer;
  old text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  select id, ticket_path into found_id, old from la_obra_v2.purchases where id = pid;
  if found_id is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  update la_obra_v2.purchases set ticket_path = null where id = pid;
  perform la_obra_v2.delete_upload(old, 'tickets');
  return la_obra_v2.ok('Ticket eliminado');
end $$;

-- ---------------------------------------------------------------------
-- GASTOS Y SALIDAS DE CAJA
-- ---------------------------------------------------------------------

-- expenses/index.php — el empleado ve solo sus gastos del día
create or replace function la_obra_v2.ep_expenses__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  emp boolean;
  f_user integer;
  d_from date;
  d_to date;
  st text := la_obra_v2.qp(q, 'status');
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_user(tok);
  emp := u.role = 'employee';
  if not emp then
    if la_obra_v2.qp(q, 'user_id') is not null then f_user := la_obra_v2.pos_id(q -> 'user_id'); end if;
    if la_obra_v2.qp(q, 'date_from') is not null then d_from := la_obra_v2.dateval(q -> 'date_from'); end if;
    if la_obra_v2.qp(q, 'date_to') is not null then d_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  end if;
  if st is not null and st not in ('active', 'cancelled') then perform la_obra_v2.fail(422, 'Estado inválido'); end if;
  return la_obra_v2.ok('Gastos consultados', jsonb_build_object(
    'scope', case when emp then 'today_own' else 'all' end,
    'expenses', coalesce((
      select jsonb_agg(to_jsonb(e) || jsonb_build_object('user_name', us.name) order by e.created_at desc, e.id desc)
      from la_obra_v2.expenses e join la_obra_v2.users us on us.id = e.user_id
      where (not emp or (e.user_id = u.id and e.created_at::date = la_obra_v2.today_mx()))
        and (f_user is null or e.user_id = f_user)
        and (d_from is null or e.created_at::date >= d_from)
        and (d_to is null or e.created_at::date <= d_to)
        and (st is null or e.status = st)
    ), '[]'::jsonb)));
end $$;

-- expenses/show.php
create or replace function la_obra_v2.ep_expenses__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  e jsonb;
  eid integer;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_user(tok);
  eid := la_obra_v2.pos_id(q -> 'id');
  e := la_obra_v2.expense_json(eid);
  perform la_obra_v2.expense_access(e, u);
  if u.role = 'employee' and (e ->> 'created_at')::timestamp::date <> la_obra_v2.today_mx() then
    perform la_obra_v2.fail(403, 'El empleado solo consulta gastos de su jornada actual');
  end if;
  if u.role = 'admin' then
    e := e || jsonb_build_object('history', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.changed_at desc, h.id desc)
      from la_obra_v2.expense_history h where h.expense_id = eid), '[]'::jsonb));
  end if;
  return la_obra_v2.ok('Gasto consultado', jsonb_build_object('expense', e));
end $$;

-- expenses/history.php
create or replace function la_obra_v2.ep_expenses__history(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare eid integer;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  eid := la_obra_v2.pos_id(q -> 'id');
  perform la_obra_v2.expense_json(eid);
  return la_obra_v2.ok('Historial consultado', jsonb_build_object('history', coalesce((
    select jsonb_agg(to_jsonb(h) || jsonb_build_object('changed_by_name', u.name) order by h.changed_at desc, h.id desc)
    from la_obra_v2.expense_history h join la_obra_v2.users u on u.id = h.changed_by
    where h.expense_id = eid), '[]'::jsonb)));
end $$;

-- expenses/create.php
create or replace function la_obra_v2.ep_expenses__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  v_amount numeric;
  v_reason text := la_obra_v2.jtrim(b -> 'reason');
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_user(tok);
  v_amount := la_obra_v2.money(b -> 'amount');
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo inválido'); end if;
  insert into la_obra_v2.expenses(amount, reason, user_id, status) values (v_amount, v_reason, u.id, 'active') returning id into new_id;
  return la_obra_v2.ok('Gasto registrado correctamente', jsonb_build_object('expense', la_obra_v2.expense_json(new_id)));
end $$;

-- expenses/update.php — corrección con motivo; se guarda el antes y el después
create or replace function la_obra_v2.ep_expenses__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  eid integer;
  why text := la_obra_v2.jtrim(b -> 'change_reason');
  old jsonb;
  nw jsonb;
  v_amount numeric;
  v_reason text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_user(tok);
  eid := la_obra_v2.pos_id(b -> 'id');
  if why = '' or char_length(why) > 255 then perform la_obra_v2.fail(422, 'El motivo de corrección es obligatorio'); end if;
  if not (b ? 'amount') and not (b ? 'reason') then perform la_obra_v2.fail(422, 'Debes enviar monto o motivo del gasto'); end if;
  old := la_obra_v2.fix_ts(la_obra_v2.expense_json(eid, true));
  perform la_obra_v2.expense_access(old, u);
  perform la_obra_v2.expense_editable(old);
  v_amount := case when b ? 'amount' then la_obra_v2.money(b -> 'amount') else (old ->> 'amount')::numeric end;
  v_reason := case when b ? 'reason' then la_obra_v2.jtrim(b -> 'reason') else old ->> 'reason' end;
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo del gasto inválido'); end if;
  update la_obra_v2.expenses set amount = v_amount, reason = v_reason, updated_at = la_obra_v2.now_mx() where id = eid;
  nw := la_obra_v2.fix_ts(la_obra_v2.expense_json(eid));
  insert into la_obra_v2.expense_history(expense_id, action, previous_data, new_data, change_reason, changed_by)
  values (eid, 'updated', old::text, nw::text, why, u.id);
  return la_obra_v2.ok('Gasto actualizado correctamente', jsonb_build_object('expense', nw));
end $$;

-- expenses/cancel.php
create or replace function la_obra_v2.ep_expenses__cancel(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  eid integer;
  why text := la_obra_v2.jtrim(b -> 'cancellation_reason');
  old jsonb;
  nw jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_user(tok);
  eid := la_obra_v2.pos_id(b -> 'id');
  if why = '' or char_length(why) > 255 then perform la_obra_v2.fail(422, 'Motivo de cancelación obligatorio'); end if;
  old := la_obra_v2.fix_ts(la_obra_v2.expense_json(eid, true));
  perform la_obra_v2.expense_access(old, u);
  perform la_obra_v2.expense_editable(old);
  update la_obra_v2.expenses
  set status = 'cancelled', cancelled_by = u.id, cancelled_at = la_obra_v2.now_mx(), cancellation_reason = why,
      updated_at = la_obra_v2.now_mx()
  where id = eid;
  nw := la_obra_v2.fix_ts(la_obra_v2.expense_json(eid));
  insert into la_obra_v2.expense_history(expense_id, action, previous_data, new_data, change_reason, changed_by)
  values (eid, 'cancelled', old::text, nw::text, why, u.id);
  return la_obra_v2.ok('Gasto cancelado correctamente', jsonb_build_object('expense', nw));
end $$;
