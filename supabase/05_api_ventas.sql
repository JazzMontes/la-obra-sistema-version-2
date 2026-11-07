-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 05 · API: pedidos (orders/) y ventas (sales/)
-- =====================================================================

-- Productos de un pedido, como los devolvía PHP
create or replace function la_obra_v2.order_items_json(p_order_id integer)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('product_id', oi.product_id, 'name', p.name, 'quantity', oi.quantity,
                                               'unit_price', oi.unit_price, 'subtotal', oi.subtotal) order by oi.id), '[]'::jsonb)
  from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id
  where oi.order_id = p_order_id
$$;

create or replace function la_obra_v2.order_recalc(p_order_id integer)
returns void language sql as $$
  update la_obra_v2.orders
  set total = (select coalesce(sum(subtotal), 0) from la_obra_v2.order_items where order_id = p_order_id)
  where id = p_order_id
$$;

-- orders/active.php — confirmados con cobro o entrega pendiente
create or replace function la_obra_v2.ep_orders__active(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  return jsonb_build_object('success', true, 'orders', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', o.id, 'total', o.total, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name,
      'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'user_name', u.name,
      'items', la_obra_v2.order_items_json(o.id)) order by o.created_at, o.id)
    from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id
    where o.order_status = 'confirmed' and (o.payment_status = 'pending' or o.delivery_status = 'pending')
  ), '[]'::jsonb));
end $$;

-- orders/create.php
create or replace function la_obra_v2.ep_orders__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  md text := coalesce(b ->> 'delivery_mode', 'local');
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_user(tok);
  if md not in ('local', 'takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  insert into la_obra_v2.orders(user_id, order_status, payment_status, delivery_status, delivery_mode, total)
  values (u.id, 'open', 'pending', 'pending', md, 0) returning id into new_id;
  return la_obra_v2.ok('Pedido creado correctamente',
    jsonb_build_object('order', jsonb_build_object('id', new_id, 'status', 'open', 'total', 0.0)));
end $$;

-- orders/add-item.php
create or replace function la_obra_v2.ep_orders__add_item(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  oid integer; pid integer; qty integer;
  ost text;
  p record;
  sub numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok);
  if not la_obra_v2.is_int(b -> 'order_id') or la_obra_v2.int_of(b -> 'order_id') <= 0
     or not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.int_of(b -> 'product_id') <= 0
     or not la_obra_v2.is_int(b -> 'quantity') or la_obra_v2.int_of(b -> 'quantity') <= 0 then
    perform la_obra_v2.fail(422, 'Los datos del producto no son válidos');
  end if;
  oid := la_obra_v2.int_of(b -> 'order_id'); pid := la_obra_v2.int_of(b -> 'product_id'); qty := la_obra_v2.int_of(b -> 'quantity');
  select order_status into ost from la_obra_v2.orders where id = oid;
  if ost is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if ost <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  select id, price, status, is_available into p from la_obra_v2.products where id = pid;
  if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if p.status <> 'active' or not p.is_available then perform la_obra_v2.fail(422, 'El producto no está disponible'); end if;
  if exists (select 1 from la_obra_v2.order_items where order_id = oid and product_id = pid) then
    perform la_obra_v2.fail(409, 'El producto ya está en el pedido; modifica su cantidad');
  end if;
  sub := p.price * qty;
  insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal) values (oid, pid, qty, p.price, sub);
  perform la_obra_v2.order_recalc(oid);
  return la_obra_v2.ok('Producto agregado al pedido', jsonb_build_object('item', jsonb_build_object(
    'product_id', pid, 'quantity', qty, 'unit_price', p.price, 'subtotal', sub)));
end $$;

-- orders/update-item.php
create or replace function la_obra_v2.ep_orders__update_item(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  oid integer; pid integer; qty integer;
  ost text;
  price numeric;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok);
  if not la_obra_v2.is_int(b -> 'order_id') or la_obra_v2.int_of(b -> 'order_id') <= 0
     or not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.int_of(b -> 'product_id') <= 0
     or not la_obra_v2.is_int(b -> 'quantity') or la_obra_v2.int_of(b -> 'quantity') <= 0 then
    perform la_obra_v2.fail(422, 'Datos inválidos');
  end if;
  oid := la_obra_v2.int_of(b -> 'order_id'); pid := la_obra_v2.int_of(b -> 'product_id'); qty := la_obra_v2.int_of(b -> 'quantity');
  select order_status into ost from la_obra_v2.orders where id = oid;
  if ost is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if ost <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  select unit_price into price from la_obra_v2.order_items where order_id = oid and product_id = pid;
  if price is null then perform la_obra_v2.fail(404, 'El producto no está en el pedido'); end if;
  update la_obra_v2.order_items set quantity = qty, subtotal = price * qty where order_id = oid and product_id = pid;
  perform la_obra_v2.order_recalc(oid);
  return la_obra_v2.ok('Cantidad actualizada correctamente');
end $$;

-- orders/remove-item.php
create or replace function la_obra_v2.ep_orders__remove_item(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  oid integer; pid integer;
  ost text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok);
  if not la_obra_v2.is_int(b -> 'order_id') or la_obra_v2.int_of(b -> 'order_id') <= 0
     or not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.int_of(b -> 'product_id') <= 0 then
    perform la_obra_v2.fail(422, 'Datos inválidos');
  end if;
  oid := la_obra_v2.int_of(b -> 'order_id'); pid := la_obra_v2.int_of(b -> 'product_id');
  select order_status into ost from la_obra_v2.orders where id = oid;
  if ost is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if ost <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  if not exists (select 1 from la_obra_v2.order_items where order_id = oid and product_id = pid) then
    perform la_obra_v2.fail(404, 'El producto no está en el pedido');
  end if;
  delete from la_obra_v2.order_items where order_id = oid and product_id = pid;
  perform la_obra_v2.order_recalc(oid);
  return la_obra_v2.ok('Producto eliminado del pedido');
end $$;

-- orders/confirm.php — congela el costo estándar de cada producto
create or replace function la_obra_v2.ep_orders__confirm(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  oid integer;
  o record;
  line record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok);
  oid := la_obra_v2.pos_id(b -> 'order_id', 'El id del pedido no es válido');
  select order_status, delivery_mode into o from la_obra_v2.orders where id = oid for update;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'open' then perform la_obra_v2.fail(409, 'El pedido no está abierto'); end if;
  if not exists (select 1 from la_obra_v2.order_items where order_id = oid) then
    perform la_obra_v2.fail(422, 'No se puede confirmar un pedido vacío');
  end if;
  for line in select id, product_id from la_obra_v2.order_items where order_id = oid loop
    update la_obra_v2.order_items
    set standard_unit_cost = (la_obra_v2.product_cost(line.product_id, coalesce(o.delivery_mode, 'local')) ->> 'standard_cost')::numeric
    where id = line.id;
  end loop;
  update la_obra_v2.orders
  set total = (select coalesce(sum(subtotal), 0) from la_obra_v2.order_items where order_id = oid),
      order_status = 'confirmed', confirmed_at = la_obra_v2.now_mx()
  where id = oid;
  return la_obra_v2.ok('Pedido confirmado correctamente');
end $$;

-- orders/checkout.php — venta en un solo paso desde el punto de venta
create or replace function la_obra_v2.ep_orders__checkout(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  md text := coalesce(b ->> 'delivery_mode', 'local');
  customer text := la_obra_v2.jtrim(b -> 'customer_name');
  items jsonb := b -> 'items';
  it jsonb;
  pid integer;
  qv jsonb;
  lines jsonb := '{}'::jsonb;
  p record;
  pay jsonb := b -> 'payment';
  meth_id integer;
  meth_name text;
  deliver_now boolean := la_obra_v2.truthy(b -> 'deliver_now');
  new_id integer;
  v_total numeric := 0;
  sub numeric;
  ln record;
  cash numeric;
  change numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_user(tok);
  if md not in ('local', 'takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  if char_length(customer) > 80 then perform la_obra_v2.fail(422, 'Nombre del cliente demasiado largo'); end if;
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) = 0 then
    perform la_obra_v2.fail(422, 'Agrega al menos un producto');
  end if;
  -- Validar productos y juntar repetidos
  for it in select value from jsonb_array_elements(items) loop
    pid := la_obra_v2.pos_id(it -> 'product_id');
    qv := it -> 'quantity';
    if not la_obra_v2.is_int(qv) or la_obra_v2.int_of(qv) <= 0 or la_obra_v2.int_of(qv) > 999 then
      perform la_obra_v2.fail(422, 'Cantidad inválida');
    end if;
    lines := jsonb_set(lines, array[pid::text], to_jsonb(coalesce((lines ->> pid::text)::integer, 0) + la_obra_v2.int_of(qv)));
  end loop;
  for ln in select key::integer as pid from jsonb_each(lines) loop
    select id, name, price, status, is_available into p from la_obra_v2.products where id = ln.pid;
    if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
    if p.status <> 'active' or not p.is_available then perform la_obra_v2.fail(409, p.name || ' no está disponible'); end if;
  end loop;
  -- Validar el pago (opcional: se puede cobrar después)
  if pay is not null and jsonb_typeof(pay) <> 'null' then
    select id, name into meth_id, meth_name from la_obra_v2.payment_methods
    where id = la_obra_v2.pos_id(pay -> 'payment_method_id') and status = 'active';
    if meth_id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado o inactivo'); end if;
  end if;

  insert into la_obra_v2.orders(user_id, order_status, payment_status, delivery_status, delivery_mode, customer_name, total)
  values (u.id, 'open', 'pending', 'pending', md, nullif(customer, ''), 0) returning id into new_id;
  for ln in select key::integer as pid, value::text::integer as qty from jsonb_each(lines) loop
    select price into p from la_obra_v2.products where id = ln.pid;
    sub := round(p.price * ln.qty, 2);
    v_total := v_total + sub;
    insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal, standard_unit_cost)
    values (new_id, ln.pid, ln.qty, p.price, sub, (la_obra_v2.product_cost(ln.pid, md) ->> 'standard_cost')::numeric);
  end loop;
  v_total := round(v_total, 2);
  update la_obra_v2.orders set total = v_total, order_status = 'confirmed', confirmed_at = la_obra_v2.now_mx() where id = new_id;

  if meth_id is not null then
    if lower(btrim(meth_name)) = 'efectivo' then
      if pay ? 'cash_received' and jsonb_typeof(pay -> 'cash_received') <> 'null' then
        if not la_obra_v2.is_num(pay -> 'cash_received') or la_obra_v2.num(pay -> 'cash_received') < v_total then
          perform la_obra_v2.fail(422, 'El efectivo recibido debe cubrir el total ($' || to_char(v_total, 'FM999,999,990.00') || ')');
        end if;
        cash := la_obra_v2.num(pay -> 'cash_received');
      else
        cash := v_total;
      end if;
      change := round(cash - v_total, 2);
    end if;
    insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount)
    values (new_id, meth_id, v_total, cash, change);
    update la_obra_v2.orders set payment_status = 'paid' where id = new_id;
  end if;
  if deliver_now then
    update la_obra_v2.orders set delivery_status = 'delivered', delivered_at = la_obra_v2.now_mx() where id = new_id;
    perform la_obra_v2.inv_consume_order(new_id, u.id);
  end if;
  return la_obra_v2.ok('Venta registrada', jsonb_build_object('order', jsonb_build_object(
    'id', new_id, 'total', v_total, 'change_amount', change,
    'payment_status', case when meth_id is not null then 'paid' else 'pending' end,
    'delivery_status', case when deliver_now then 'delivered' else 'pending' end)));
end $$;

-- orders/deliver.php — al entregar se descuenta el inventario según la receta
create or replace function la_obra_v2.ep_orders__deliver(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  oid integer;
  o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_user(tok);
  oid := la_obra_v2.pos_id(b -> 'order_id', 'El id del pedido no es válido');
  select order_status, delivery_status into o from la_obra_v2.orders where id = oid for update;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'Solo se puede entregar un pedido confirmado'); end if;
  if o.delivery_status = 'delivered' then perform la_obra_v2.fail(409, 'El pedido ya fue entregado'); end if;
  update la_obra_v2.orders set delivery_status = 'delivered', delivered_at = la_obra_v2.now_mx() where id = oid;
  perform la_obra_v2.inv_consume_order(oid, u.id);
  return la_obra_v2.ok('Pedido entregado; inventario descontado');
end $$;

-- orders/cancel.php — pedido abierto o confirmado que todavía no se cobra
create or replace function la_obra_v2.ep_orders__cancel(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  oid integer;
  o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_user(tok);
  oid := la_obra_v2.pos_id(b -> 'order_id', 'El id del pedido no es válido');
  select order_status, payment_status into o from la_obra_v2.orders where id = oid for update;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status = 'cancelled' or o.payment_status = 'paid' then
    perform la_obra_v2.fail(409, 'Solo se puede cancelar un pedido que no se ha cobrado');
  end if;
  update la_obra_v2.orders set order_status = 'cancelled', cancelled_at = la_obra_v2.now_mx() where id = oid;
  perform la_obra_v2.inv_reverse_order(oid, u.id);
  return la_obra_v2.ok('Pedido cancelado correctamente');
end $$;

-- orders/show.php
create or replace function la_obra_v2.ep_orders__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  oid integer;
  j jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  oid := la_obra_v2.pos_id(q -> 'id', 'El id del pedido no es válido');
  select jsonb_build_object('id', o.id, 'user_id', o.user_id, 'user_name', u.name, 'order_status', o.order_status,
    'payment_status', o.payment_status, 'delivery_status', o.delivery_status, 'delivery_mode', o.delivery_mode,
    'customer_name', o.customer_name, 'total', o.total, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at,
    'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at, 'items', la_obra_v2.order_items_json(o.id))
  into j from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id where o.id = oid;
  if j is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  return jsonb_build_object('success', true, 'order', j);
end $$;

-- sales/index.php — el empleado ve solo SU historial del día; el admin, todo
create or replace function la_obra_v2.ep_sales__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  f_pay text := la_obra_v2.qp(q, 'payment_status');
  f_del text := la_obra_v2.qp(q, 'delivery_status');
  f_ord text := la_obra_v2.qp(q, 'order_status');
  f_pm text := la_obra_v2.qp(q, 'payment_method_id');
  f_date text := la_obra_v2.qp(q, 'date');
  pm integer;
  emp boolean;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_user(tok);
  emp := u.role = 'employee';
  if f_pay is not null and f_pay not in ('pending', 'paid') then perform la_obra_v2.fail(422, 'Filtro payment_status inválido'); end if;
  if f_del is not null and f_del not in ('pending', 'delivered') then perform la_obra_v2.fail(422, 'Filtro delivery_status inválido'); end if;
  if f_ord is not null and f_ord not in ('open', 'confirmed', 'cancelled') then perform la_obra_v2.fail(422, 'Filtro order_status inválido'); end if;
  if f_pm is not null then
    if not la_obra_v2.is_int(to_jsonb(f_pm)) or la_obra_v2.int_of(to_jsonb(f_pm)) <= 0 then
      perform la_obra_v2.fail(422, 'Filtro payment_method_id inválido');
    end if;
    pm := la_obra_v2.int_of(to_jsonb(f_pm));
  end if;
  if not emp and f_date is not null and not la_obra_v2.is_date(f_date) then
    perform la_obra_v2.fail(422, 'Filtro date inválido');
  end if;
  return jsonb_build_object('success', true, 'scope', case when emp then 'today_own' else 'all' end, 'sales', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', o.id, 'user_id', o.user_id, 'user_name', u2.name, 'delivery_mode', o.delivery_mode,
      'customer_name', o.customer_name, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at,
      'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at, 'total', o.total,
      'order_status', o.order_status, 'payment_status', o.payment_status, 'delivery_status', o.delivery_status,
      'payment_method_id', pmt.id, 'payment_method', pmt.name, 'paid_at', p.paid_at,
      'items', la_obra_v2.order_items_json(o.id)) order by o.created_at desc, o.id desc)
    from la_obra_v2.orders o
    join la_obra_v2.users u2 on u2.id = o.user_id
    left join la_obra_v2.payments p on p.order_id = o.id
    left join la_obra_v2.payment_methods pmt on pmt.id = p.payment_method_id
    where (f_pay is null or o.payment_status = f_pay)
      and (f_del is null or o.delivery_status = f_del)
      and (f_ord is null or o.order_status = f_ord)
      and (pm is null or p.payment_method_id = pm)
      and (not emp or (o.user_id = u.id and o.created_at::date = la_obra_v2.today_mx()))
      and (emp or f_date is null or o.created_at::date = f_date::date)
  ), '[]'::jsonb));
end $$;

-- sales/show.php
create or replace function la_obra_v2.ep_sales__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  oid integer;
  o record;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_user(tok);
  oid := la_obra_v2.pos_id(q -> 'id', 'El id no es válido');
  select o2.*, u2.name as user_name, p.id as payment_id, p.amount, p.cash_received, p.change_amount, p.paid_at,
         pmt.id as pm_id, pmt.name as pm_name
  into o
  from la_obra_v2.orders o2 join la_obra_v2.users u2 on u2.id = o2.user_id
  left join la_obra_v2.payments p on p.order_id = o2.id
  left join la_obra_v2.payment_methods pmt on pmt.id = p.payment_method_id
  where o2.id = oid;
  if o.id is null then perform la_obra_v2.fail(404, 'Venta o pedido no encontrado'); end if;
  if u.role = 'employee' and (o.user_id <> u.id or o.created_at::date <> la_obra_v2.today_mx()) then
    perform la_obra_v2.fail(403, 'Solo puedes consultar tus pedidos del día');
  end if;
  return jsonb_build_object('success', true, 'sale', jsonb_build_object(
    'id', o.id, 'user', jsonb_build_object('id', o.user_id, 'name', o.user_name),
    'order_status', o.order_status, 'payment_status', o.payment_status, 'delivery_status', o.delivery_status,
    'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name,
    'total', o.total, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at,
    'cancelled_at', o.cancelled_at, 'items', la_obra_v2.order_items_json(o.id),
    'payment', case when o.payment_id is null then null else jsonb_build_object(
      'id', o.payment_id, 'payment_method_id', o.pm_id, 'payment_method', o.pm_name, 'amount', o.amount,
      'cash_received', o.cash_received, 'change_amount', o.change_amount, 'paid_at', o.paid_at) end));
end $$;

-- sales/payment.php — registrar el cobro de un pedido confirmado
create or replace function la_obra_v2.ep_sales__payment(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  oid integer; mid integer;
  o record;
  meth record;
  cash numeric;
  change numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok);
  if not la_obra_v2.is_int(b -> 'order_id') or la_obra_v2.int_of(b -> 'order_id') <= 0
     or not la_obra_v2.is_int(b -> 'payment_method_id') or la_obra_v2.int_of(b -> 'payment_method_id') <= 0 then
    perform la_obra_v2.fail(422, 'Datos de pago inválidos');
  end if;
  oid := la_obra_v2.int_of(b -> 'order_id'); mid := la_obra_v2.int_of(b -> 'payment_method_id');
  select id, total, order_status, payment_status into o from la_obra_v2.orders where id = oid for update;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'El pedido debe estar confirmado antes de registrar el pago'); end if;
  if o.payment_status = 'paid' then perform la_obra_v2.fail(409, 'El pedido ya está pagado'); end if;
  select id, name, status into meth from la_obra_v2.payment_methods where id = mid;
  if meth.id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
  if meth.status <> 'active' then perform la_obra_v2.fail(409, 'El método de pago está inactivo'); end if;
  if lower(btrim(meth.name)) = 'efectivo' then
    if not la_obra_v2.is_num(b -> 'cash_received') or la_obra_v2.num(b -> 'cash_received') < o.total then
      perform la_obra_v2.fail(422, 'El efectivo recibido debe ser igual o mayor al total');
    end if;
    cash := la_obra_v2.num(b -> 'cash_received');
    change := round(cash - o.total, 2);
  end if;
  insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount)
  values (oid, mid, o.total, cash, change);
  update la_obra_v2.orders set payment_status = 'paid' where id = oid;
  return la_obra_v2.ok('Pago registrado correctamente', jsonb_build_object('payment', jsonb_build_object(
    'order_id', oid, 'payment_method', meth.name, 'amount', o.total, 'cash_received', cash, 'change_amount', change)));
end $$;

-- sales/cancel.php — cancelar una venta cobrada (solo admin); devuelve inventario
create or replace function la_obra_v2.ep_sales__cancel(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  oid integer;
  o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  oid := la_obra_v2.pos_id(b -> 'order_id', 'El id no es válido');
  select order_status, payment_status into o from la_obra_v2.orders where id = oid for update;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Venta no encontrada'); end if;
  if o.order_status = 'cancelled' then perform la_obra_v2.fail(409, 'La venta ya está cancelada'); end if;
  if o.payment_status <> 'paid' then perform la_obra_v2.fail(422, 'El pedido no tiene un pago registrado'); end if;
  update la_obra_v2.orders set order_status = 'cancelled', cancelled_at = la_obra_v2.now_mx() where id = oid;
  perform la_obra_v2.inv_reverse_order(oid, u.id);
  return la_obra_v2.ok('Venta cancelada correctamente');
end $$;
