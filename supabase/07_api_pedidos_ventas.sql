-- =====================================================================
-- La Obra v2 · 07 · orders/* y sales/*
-- =====================================================================
set check_function_bodies = off;

create or replace function la_obra_v2.order_items_json(p_order int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('product_id', oi.product_id, 'name', p.name, 'quantity', oi.quantity,
    'unit_price', oi.unit_price::float8, 'subtotal', oi.subtotal::float8) order by oi.id), '[]')
  from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id where oi.order_id = p_order;
$$;

create or replace function la_obra_v2.order_recalc(p_order int)
returns void language sql as $$
  update la_obra_v2.orders set total = (select coalesce(sum(subtotal), 0) from la_obra_v2.order_items where order_id = p_order) where id = p_order;
$$;

create or replace function la_obra_v2.int_arg(v jsonb)
returns boolean language sql immutable as $$ select la_obra_v2.is_int(v) and la_obra_v2.num(v) > 0; $$;

create or replace function la_obra_v2.ep_orders__active(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Pedidos en curso', jsonb_build_object('orders', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'total', o.total::float8, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name, 'created_at', o.created_at,
      'confirmed_at', o.confirmed_at, 'user_name', u.name, 'items', la_obra_v2.order_items_json(o.id)) order by o.created_at, o.id), '[]')
    from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id
    where o.order_status = 'confirmed' and (o.payment_status = 'pending' or o.delivery_status = 'pending'))));
end $$;

create or replace function la_obra_v2.ep_orders__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_mode text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t);
  if b is null or jsonb_typeof(b) <> 'object' then b := '{}'; end if;
  v_mode := coalesce(la_obra_v2.jtext(b -> 'delivery_mode'), 'local');
  if v_mode not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  insert into la_obra_v2.orders(user_id, order_status, payment_status, delivery_status, delivery_mode, total)
  values (u.id, 'open', 'pending', 'pending', v_mode, 0) returning id into v_id;
  return la_obra_v2.ok(201, 'Pedido creado correctamente', jsonb_build_object('order', jsonb_build_object('id', v_id, 'status', 'open', 'total', 0.0)));
end $$;

create or replace function la_obra_v2.ep_orders__add_item(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_p int; v_q int; v_st text; pr record; v_sub numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'product_id') or not la_obra_v2.int_arg(b -> 'quantity') then
    perform la_obra_v2.fail(422, 'Los datos del producto no son válidos');
  end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_p := la_obra_v2.num(b -> 'product_id'); v_q := la_obra_v2.num(b -> 'quantity');
  select order_status into v_st from la_obra_v2.orders where id = v_o;
  if v_st is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if v_st <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  select id, price, status, is_available into pr from la_obra_v2.products where id = v_p;
  if pr.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if pr.status <> 'active' or not pr.is_available then perform la_obra_v2.fail(422, 'El producto no está disponible'); end if;
  if exists(select 1 from la_obra_v2.order_items where order_id = v_o and product_id = v_p) then
    perform la_obra_v2.fail(409, 'El producto ya está en el pedido; modifica su cantidad');
  end if;
  v_sub := pr.price * v_q;
  insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal) values (v_o, v_p, v_q, pr.price, v_sub);
  perform la_obra_v2.order_recalc(v_o);
  return la_obra_v2.ok(201, 'Producto agregado al pedido', jsonb_build_object('item', jsonb_build_object('product_id', v_p, 'quantity', v_q,
    'unit_price', pr.price::float8, 'subtotal', v_sub::float8)));
end $$;

create or replace function la_obra_v2.ep_orders__update_item(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_p int; v_q int; v_st text; v_price numeric;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'product_id') or not la_obra_v2.int_arg(b -> 'quantity') then
    perform la_obra_v2.fail(422, 'Datos inválidos');
  end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_p := la_obra_v2.num(b -> 'product_id'); v_q := la_obra_v2.num(b -> 'quantity');
  select order_status into v_st from la_obra_v2.orders where id = v_o;
  if v_st is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if v_st <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  select unit_price into v_price from la_obra_v2.order_items where order_id = v_o and product_id = v_p;
  if v_price is null then perform la_obra_v2.fail(404, 'El producto no está en el pedido'); end if;
  update la_obra_v2.order_items set quantity = v_q, subtotal = v_price * v_q where order_id = v_o and product_id = v_p;
  perform la_obra_v2.order_recalc(v_o);
  return la_obra_v2.ok(200, 'Cantidad actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_orders__remove_item(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_p int; v_st text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'product_id') then perform la_obra_v2.fail(422, 'Datos inválidos'); end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_p := la_obra_v2.num(b -> 'product_id');
  select order_status into v_st from la_obra_v2.orders where id = v_o;
  if v_st is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if v_st <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  if not exists(select 1 from la_obra_v2.order_items where order_id = v_o and product_id = v_p) then perform la_obra_v2.fail(404, 'El producto no está en el pedido'); end if;
  delete from la_obra_v2.order_items where order_id = v_o and product_id = v_p;
  perform la_obra_v2.order_recalc(v_o);
  return la_obra_v2.ok(200, 'Producto eliminado del pedido');
end $$;

create or replace function la_obra_v2.ep_orders__confirm(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; o record; l record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, delivery_mode into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'open' then perform la_obra_v2.fail(409, 'El pedido no está abierto'); end if;
  if not exists(select 1 from la_obra_v2.order_items where order_id = v_id) then perform la_obra_v2.fail(422, 'No se puede confirmar un pedido vacío'); end if;
  for l in select id, product_id from la_obra_v2.order_items where order_id = v_id loop
    update la_obra_v2.order_items set standard_unit_cost = (la_obra_v2.product_cost(l.product_id, coalesce(nullif(o.delivery_mode, ''), 'local')) ->> 'standard_cost')::numeric where id = l.id;
  end loop;
  perform la_obra_v2.order_recalc(v_id);
  update la_obra_v2.orders set order_status = 'confirmed', confirmed_at = localtimestamp where id = v_id;
  return la_obra_v2.ok(200, 'Pedido confirmado correctamente');
end $$;

create or replace function la_obra_v2.ep_orders__deliver(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, delivery_status into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'Solo se puede entregar un pedido confirmado'); end if;
  if o.delivery_status = 'delivered' then perform la_obra_v2.fail(409, 'El pedido ya fue entregado'); end if;
  update la_obra_v2.orders set delivery_status = 'delivered', delivered_at = localtimestamp where id = v_id;
  perform la_obra_v2.inv_consume_order(v_id, u.id);
  return la_obra_v2.ok(200, 'Pedido entregado; inventario descontado');
end $$;

create or replace function la_obra_v2.ep_orders__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, payment_status into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status = 'cancelled' or o.payment_status = 'paid' then perform la_obra_v2.fail(409, 'Solo se puede cancelar un pedido que no se ha cobrado'); end if;
  update la_obra_v2.orders set order_status = 'cancelled', cancelled_at = localtimestamp where id = v_id;
  perform la_obra_v2.inv_reverse_order(v_id, u.id);
  return la_obra_v2.ok(200, 'Pedido cancelado correctamente');
end $$;

create or replace function la_obra_v2.ep_orders__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(q -> 'id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id');
  select jsonb_build_object('id', o.id, 'user_id', o.user_id, 'user_name', u.name, 'order_status', o.order_status, 'payment_status', o.payment_status,
    'delivery_status', o.delivery_status, 'total', o.total::float8, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at,
    'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at, 'items', la_obra_v2.order_items_json(o.id))
    into r from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id where o.id = v_id;
  if r is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  return la_obra_v2.ok(200, 'Pedido', jsonb_build_object('order', r));
end $$;

-- orders/checkout.php: venta completa en un paso (pedido + cobro opcional + entrega opcional)
create or replace function la_obra_v2.ep_orders__checkout(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_mode text; v_customer text; it jsonb; v_pid int; v_q int; v_lines jsonb := '{}'; k text;
        pr record; v_payment jsonb; pm record; v_deliver boolean; v_order int; v_total numeric := 0; v_sub numeric;
        v_cash numeric; v_change numeric; v_cash_j jsonb;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_mode := coalesce(la_obra_v2.jtext(b -> 'delivery_mode'), 'local');
  if (b -> 'delivery_mode') is not null and jsonb_typeof(b -> 'delivery_mode') = 'null' then v_mode := 'local'; end if;
  if v_mode not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  v_customer := la_obra_v2.jstr(b -> 'customer_name');
  if char_length(v_customer) > 80 then perform la_obra_v2.fail(422, 'Nombre del cliente demasiado largo'); end if;
  if jsonb_typeof(b -> 'items') is distinct from 'array' or jsonb_array_length(b -> 'items') = 0 then perform la_obra_v2.fail(422, 'Agrega al menos un producto'); end if;
  for it in select * from jsonb_array_elements(b -> 'items') loop
    v_pid := la_obra_v2.positive_id(it -> 'product_id');
    if not la_obra_v2.is_int(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 or la_obra_v2.num(it -> 'quantity') > 999 then
      perform la_obra_v2.fail(422, 'Cantidad inválida');
    end if;
    v_q := la_obra_v2.num(it -> 'quantity');
    v_lines := jsonb_set(v_lines, array[v_pid::text], to_jsonb(coalesce((v_lines ->> v_pid::text)::int, 0) + v_q));
  end loop;
  for k in select key from jsonb_each(v_lines) loop
    select id, name, price, status, is_available into pr from la_obra_v2.products where id = k::int;
    if pr.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
    if pr.status <> 'active' or not pr.is_available then perform la_obra_v2.fail(409, pr.name || ' no está disponible'); end if;
  end loop;
  v_payment := b -> 'payment';
  if v_payment is not null and jsonb_typeof(v_payment) <> 'null' then
    select id, name into pm from la_obra_v2.payment_methods where id = la_obra_v2.positive_id(v_payment -> 'payment_method_id') and status = 'active';
    if pm.id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado o inactivo'); end if;
  else
    v_payment := null;
  end if;
  v_deliver := la_obra_v2.not_empty(b -> 'deliver_now');

  insert into la_obra_v2.orders(user_id, order_status, payment_status, delivery_status, delivery_mode, customer_name, total)
  values (u.id, 'open', 'pending', 'pending', v_mode, nullif(v_customer, ''), 0) returning id into v_order;
  -- En el orden en que llegaron los productos
  for k, v_q in select e.key, e.value::int from jsonb_each_text(v_lines) e
                 order by (select min(n) from jsonb_array_elements(b -> 'items') with ordinality a(x, n) where la_obra_v2.jtext(x -> 'product_id')::int = e.key::int) loop
    select price into pr from la_obra_v2.products where id = k::int;
    v_sub := round(pr.price * v_q, 2);
    v_total := v_total + v_sub;
    insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal, standard_unit_cost)
    values (v_order, k::int, v_q, pr.price, v_sub, (la_obra_v2.product_cost(k::int, v_mode) ->> 'standard_cost')::numeric);
  end loop;
  v_total := round(v_total, 2);
  update la_obra_v2.orders set total = v_total, order_status = 'confirmed', confirmed_at = localtimestamp where id = v_order;
  v_change := null;
  if v_payment is not null then
    v_cash := null;
    if lower(btrim(pm.name)) = 'efectivo' then
      v_cash_j := coalesce(nullif(v_payment -> 'cash_received', 'null'::jsonb), to_jsonb(v_total));
      if not la_obra_v2.is_num(v_cash_j) or la_obra_v2.num(v_cash_j) < v_total then
        perform la_obra_v2.fail(422, 'El efectivo recibido debe cubrir el total ($' || to_char(v_total, 'FM999,999,990.00') || ')');
      end if;
      v_cash := la_obra_v2.num(v_cash_j);
      v_change := round(v_cash - v_total, 2);
    end if;
    insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount) values (v_order, pm.id, v_total, round(v_cash, 2), v_change);
    update la_obra_v2.orders set payment_status = 'paid' where id = v_order;
  end if;
  if v_deliver then
    update la_obra_v2.orders set delivery_status = 'delivered', delivered_at = localtimestamp where id = v_order;
    perform la_obra_v2.inv_consume_order(v_order, u.id);
  end if;
  return la_obra_v2.ok(201, 'Venta registrada', jsonb_build_object('order', jsonb_build_object('id', v_order, 'total', v_total::float8,
    'change_amount', v_change::float8, 'payment_status', case when v_payment is not null then 'paid' else 'pending' end,
    'delivery_status', case when v_deliver then 'delivered' else 'pending' end)));
end $$;

create or replace function la_obra_v2.ep_sales__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_ps text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'payment_status')); v_ds text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'delivery_status'));
        v_os text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'order_status')); v_pm int; v_date date;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if v_ps is not null and v_ps not in ('pending','paid') then perform la_obra_v2.fail(422, 'Filtro payment_status inválido'); end if;
  if v_ds is not null and v_ds not in ('pending','delivered') then perform la_obra_v2.fail(422, 'Filtro delivery_status inválido'); end if;
  if v_os is not null and v_os not in ('open','confirmed','cancelled') then perform la_obra_v2.fail(422, 'Filtro order_status inválido'); end if;
  if la_obra_v2.qparam(q, 'payment_method_id') is not null then
    if not la_obra_v2.int_arg(q -> 'payment_method_id') then perform la_obra_v2.fail(422, 'Filtro payment_method_id inválido'); end if;
    v_pm := la_obra_v2.num(q -> 'payment_method_id');
  end if;
  if u.role <> 'employee' and la_obra_v2.qparam(q, 'date') is not null then
    v_date := la_obra_v2.dateval(q -> 'date', 'Filtro date inválido');
  end if;
  return la_obra_v2.ok(200, 'Ventas', jsonb_build_object('scope', case when u.role = 'employee' then 'today_own' else 'all' end, 'sales', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'user_id', o.user_id, 'user_name', us.name, 'delivery_mode', o.delivery_mode,
      'customer_name', o.customer_name, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at,
      'cancelled_at', o.cancelled_at, 'total', o.total::float8, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'payment_method_id', pm.id, 'payment_method', pm.name, 'paid_at', p.paid_at,
      'items', la_obra_v2.order_items_json(o.id)) order by o.created_at desc, o.id desc), '[]')
    from la_obra_v2.orders o join la_obra_v2.users us on us.id = o.user_id
    left join la_obra_v2.payments p on p.order_id = o.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where (v_ps is null or o.payment_status = v_ps) and (v_ds is null or o.delivery_status = v_ds) and (v_os is null or o.order_status = v_os)
      and (v_pm is null or p.payment_method_id = v_pm)
      and (u.role <> 'employee' or (o.user_id = u.id and o.created_at::date = current_date))
      and (v_date is null or o.created_at::date = v_date))));
end $$;

create or replace function la_obra_v2.ep_sales__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(q -> 'id') then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id');
  select o2.*, us.name as user_name, p.id as payment_id, p.amount, p.cash_received, p.change_amount, p.paid_at, pm.id as pm_id, pm.name as pm_name
    into o from la_obra_v2.orders o2 join la_obra_v2.users us on us.id = o2.user_id
    left join la_obra_v2.payments p on p.order_id = o2.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id where o2.id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Venta o pedido no encontrado'); end if;
  if u.role = 'employee' and (o.user_id <> u.id or o.created_at::date <> current_date) then perform la_obra_v2.fail(403, 'Solo puedes consultar tus pedidos del día'); end if;
  return la_obra_v2.ok(200, 'Venta', jsonb_build_object('sale', jsonb_build_object('id', o.id, 'user', jsonb_build_object('id', o.user_id, 'name', o.user_name),
    'order_status', o.order_status, 'payment_status', o.payment_status, 'delivery_status', o.delivery_status, 'total', o.total::float8,
    'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at,
    'items', la_obra_v2.order_items_json(o.id),
    'payment', case when o.payment_id is null then null else jsonb_build_object('id', o.payment_id, 'payment_method_id', o.pm_id, 'payment_method', o.pm_name,
      'amount', o.amount::float8, 'cash_received', o.cash_received::float8, 'change_amount', o.change_amount::float8, 'paid_at', o.paid_at) end)));
end $$;

create or replace function la_obra_v2.ep_sales__payment(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_m int; o record; pm record; v_cash numeric; v_change numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'payment_method_id') then perform la_obra_v2.fail(422, 'Datos de pago inválidos'); end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_m := la_obra_v2.num(b -> 'payment_method_id');
  select id, total, order_status, payment_status into o from la_obra_v2.orders where id = v_o;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'El pedido debe estar confirmado antes de registrar el pago'); end if;
  if o.payment_status = 'paid' then perform la_obra_v2.fail(409, 'El pedido ya está pagado'); end if;
  select id, name, status into pm from la_obra_v2.payment_methods where id = v_m;
  if pm.id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
  if pm.status <> 'active' then perform la_obra_v2.fail(409, 'El método de pago está inactivo'); end if;
  if lower(btrim(pm.name)) = 'efectivo' then
    if not la_obra_v2.is_num(b -> 'cash_received') or la_obra_v2.num(b -> 'cash_received') < o.total then
      perform la_obra_v2.fail(422, 'El efectivo recibido debe ser igual o mayor al total');
    end if;
    v_cash := la_obra_v2.num(b -> 'cash_received'); v_change := v_cash - o.total;
  end if;
  insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount) values (v_o, v_m, o.total, round(v_cash, 2), round(v_change, 2));
  update la_obra_v2.orders set payment_status = 'paid' where id = v_o;
  return la_obra_v2.ok(200, 'Pago registrado correctamente', jsonb_build_object('payment', jsonb_build_object('order_id', v_o, 'payment_method', pm.name,
    'amount', o.total::float8, 'cash_received', v_cash::float8, 'change_amount', v_change::float8)));
end $$;

create or replace function la_obra_v2.ep_sales__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_long(t, true);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, payment_status into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Venta no encontrada'); end if;
  if o.order_status = 'cancelled' then perform la_obra_v2.fail(409, 'La venta ya está cancelada'); end if;
  if o.payment_status <> 'paid' then perform la_obra_v2.fail(422, 'El pedido no tiene un pago registrado'); end if;
  update la_obra_v2.orders set order_status = 'cancelled', cancelled_at = localtimestamp where id = v_id;
  perform la_obra_v2.inv_reverse_order(v_id, u.id);
  return la_obra_v2.ok(200, 'Venta cancelada correctamente');
end $$;
