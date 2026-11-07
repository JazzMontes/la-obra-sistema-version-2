-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 08 · API: reportes (reports/) y pantalla de inicio (dashboard/)
-- Los reportes se calculan al momento con el historial completo;
-- no se guardan copias. El PDF se arma en la app cuando se pide.
-- =====================================================================

-- reports/daily.php — ventas cobradas por día
create or replace function la_obra_v2.ep_reports__daily(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'Los reportes están disponibles para el administrador');
  select * into r from la_obra_v2.report_range(q);
  return jsonb_build_object('success', true, 'from', r.d_from, 'to', r.d_to, 'data', coalesce((
    select jsonb_agg(jsonb_build_object('date', d, 'amount', amount, 'orders', orders) order by d)
    from (
      select pay.paid_at::date as d, sum(pay.amount) as amount, count(*) as orders
      from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id
      where o.order_status = 'confirmed' and o.payment_status = 'paid'
        and pay.paid_at >= r.d_from and pay.paid_at < r.d_to + 1
      group by pay.paid_at::date) s), '[]'::jsonb));
end $$;

-- reports/categories.php — ventas por día y categoría
create or replace function la_obra_v2.ep_reports__categories(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'Los reportes están disponibles para el administrador');
  select * into r from la_obra_v2.report_range(q);
  return jsonb_build_object('success', true, 'from', r.d_from, 'to', r.d_to, 'data', coalesce((
    select jsonb_agg(jsonb_build_object('date', d, 'category_id', cid, 'category', cname, 'amount', amount) order by d, cid)
    from (
      select pay.paid_at::date as d, c.id as cid, c.name as cname, sum(oi.subtotal) as amount
      from la_obra_v2.order_items oi
      join la_obra_v2.products p on p.id = oi.product_id
      join la_obra_v2.categories c on c.id = p.category_id
      join la_obra_v2.orders o on o.id = oi.order_id
      join la_obra_v2.payments pay on pay.order_id = o.id
      where o.order_status = 'confirmed' and o.payment_status = 'paid'
        and pay.paid_at >= r.d_from and pay.paid_at < r.d_to + 1
      group by pay.paid_at::date, c.id, c.name) s), '[]'::jsonb));
end $$;

-- reports/payment-methods.php
create or replace function la_obra_v2.ep_reports__payment_methods(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'Los reportes están disponibles para el administrador');
  select * into r from la_obra_v2.report_range(q);
  return jsonb_build_object('success', true, 'from', r.d_from, 'to', r.d_to, 'data', coalesce((
    select jsonb_agg(jsonb_build_object('method_id', mid, 'name', nm, 'amount', amount, 'orders', orders) order by amount desc, mid)
    from (
      select pm.id as mid, pm.name as nm, sum(pay.amount) as amount, count(*) as orders
      from la_obra_v2.payments pay
      join la_obra_v2.orders o on o.id = pay.order_id
      join la_obra_v2.payment_methods pm on pm.id = pay.payment_method_id
      where o.order_status = 'confirmed' and o.payment_status = 'paid'
        and pay.paid_at >= r.d_from and pay.paid_at < r.d_to + 1
      group by pm.id, pm.name) s), '[]'::jsonb));
end $$;

-- reports/products.php
create or replace function la_obra_v2.ep_reports__products(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'Los reportes están disponibles para el administrador');
  select * into r from la_obra_v2.report_range(q);
  return jsonb_build_object('success', true, 'from', r.d_from, 'to', r.d_to, 'data', coalesce((
    select jsonb_agg(jsonb_build_object('product_id', pid, 'name', nm, 'quantity', qty, 'amount', amount) order by qty desc, pid)
    from (
      select p.id as pid, p.name as nm, sum(oi.quantity) as qty, sum(oi.subtotal) as amount
      from la_obra_v2.order_items oi
      join la_obra_v2.products p on p.id = oi.product_id
      join la_obra_v2.orders o on o.id = oi.order_id
      join la_obra_v2.payments pay on pay.order_id = o.id
      where o.order_status = 'confirmed' and o.payment_status = 'paid'
        and pay.paid_at >= r.d_from and pay.paid_at < r.d_to + 1
      group by p.id, p.name) s), '[]'::jsonb));
end $$;

-- reports/summary.php — reporte del periodo y corte de caja
create or replace function la_obra_v2.ep_reports__summary(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  d_from date;
  d_to date;
  v_orders integer;
  v_sales numeric;
  v_cost numeric;
  v_no_cost integer;
  v_purchases numeric;
  v_expenses numeric;
  v_waste numeric;
  v_cancel_n integer;
  v_cancel_t numeric;
  v_methods jsonb;
  v_cash_sales numeric;
  v_cash_purchases numeric;
  v_ids integer[];
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  d_from := la_obra_v2.dateval(coalesce(q -> 'from', to_jsonb(to_char(la_obra_v2.today_mx(), 'YYYY-MM-DD'))));
  d_to := la_obra_v2.dateval(coalesce(q -> 'to', to_jsonb(to_char(la_obra_v2.today_mx(), 'YYYY-MM-DD'))));
  if d_from > d_to then perform la_obra_v2.fail(422, 'La fecha inicial no puede ser mayor que la final'); end if;
  if d_to - d_from > 366 then perform la_obra_v2.fail(422, 'El periodo máximo es de un año'); end if;

  -- Pedidos confirmados y cobrados, por fecha del pedido
  v_ids := array(select o.id from la_obra_v2.orders o
                 where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date between d_from and d_to);

  select count(*), coalesce(sum(o.total), 0) into v_orders, v_sales
  from la_obra_v2.orders o join unnest(v_ids) x(id) on x.id = o.id;
  select coalesce(sum(oi.quantity * oi.standard_unit_cost), 0), count(*) filter (where oi.standard_unit_cost is null)
  into v_cost, v_no_cost
  from la_obra_v2.order_items oi join unnest(v_ids) x(id) on x.id = oi.order_id;
  select coalesce(sum(total), 0) into v_purchases from la_obra_v2.purchases where purchase_date between d_from and d_to;
  select coalesce(sum(amount), 0) into v_expenses from la_obra_v2.expenses
  where status = 'active' and created_at::date between d_from and d_to;
  select coalesce(sum(estimated_total_cost), 0) into v_waste from la_obra_v2.waste_records where waste_date between d_from and d_to;
  select count(*), coalesce(sum(total), 0) into v_cancel_n, v_cancel_t from la_obra_v2.orders o
  where o.order_status = 'cancelled' and o.created_at::date between d_from and d_to;

  select coalesce(jsonb_agg(jsonb_build_object('name', nm, 'orders', orders, 'amount', amount) order by amount desc), '[]'::jsonb)
  into v_methods
  from (select pm.name as nm, count(*) as orders, sum(pay.amount) as amount
        from la_obra_v2.payments pay join unnest(v_ids) x(id) on x.id = pay.order_id
        join la_obra_v2.payment_methods pm on pm.id = pay.payment_method_id
        group by pm.id, pm.name) s;
  select coalesce(sum((x ->> 'amount')::numeric), 0) into v_cash_sales
  from jsonb_array_elements(v_methods) x where lower(btrim(x ->> 'name')) = 'efectivo';
  select coalesce(sum(p.total), 0) into v_cash_purchases
  from la_obra_v2.purchases p join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
  where lower(pm.name) = 'efectivo' and p.purchase_date between d_from and d_to;

  return la_obra_v2.ok('Reporte generado', jsonb_build_object('report', jsonb_build_object(
    'from', d_from, 'to', d_to,
    'totals', jsonb_build_object(
      'sales', round(v_sales, 2),
      'orders', v_orders,
      'average_ticket', case when v_orders > 0 then round(v_sales / v_orders, 2) else 0 end,
      'cost_of_sales', round(v_cost, 2),
      'gross_profit', round(v_sales - v_cost, 2),
      'gross_margin', case when v_sales > 0 then round((v_sales - v_cost) / v_sales * 100, 1) else null end,
      'lines_without_cost', v_no_cost,
      'purchases', round(v_purchases, 2),
      'expenses', round(v_expenses, 2),
      'waste', round(v_waste, 2),
      'cancelled_orders', v_cancel_n,
      'cancelled_amount', round(v_cancel_t, 2)),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', d, 'orders', n, 'sales', s) order by d)
      from (select o.created_at::date as d, count(*) as n, sum(o.total) as s
            from la_obra_v2.orders o join unnest(v_ids) x(id) on x.id = o.id group by o.created_at::date) t), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object('id', pid, 'name', nm, 'quantity', qty, 'revenue', rev, 'cost', cst) order by rev desc)
      from (select p.id as pid, p.name as nm, sum(oi.quantity) as qty, sum(oi.subtotal) as rev,
                   sum(oi.quantity * coalesce(oi.standard_unit_cost, 0)) as cst
            from la_obra_v2.order_items oi join unnest(v_ids) x(id) on x.id = oi.order_id
            join la_obra_v2.products p on p.id = oi.product_id group by p.id, p.name) t), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('name', nm, 'quantity', qty, 'revenue', rev) order by rev desc)
      from (select c.name as nm, sum(oi.quantity) as qty, sum(oi.subtotal) as rev
            from la_obra_v2.order_items oi join unnest(v_ids) x(id) on x.id = oi.order_id
            join la_obra_v2.products p on p.id = oi.product_id
            join la_obra_v2.categories c on c.id = p.category_id group by c.id, c.name) t), '[]'::jsonb),
    'payment_methods', v_methods,
    'cash_cut', jsonb_build_object(
      'cash_sales', round(v_cash_sales, 2),
      'cash_purchases', round(v_cash_purchases, 2),
      'expenses', round(v_expenses, 2),
      'expected_cash', round(v_cash_sales - v_cash_purchases - v_expenses, 2)))));
end $$;

-- dashboard/summary.php — inicio: ventas del día, pendientes y alertas de inventario
create or replace function la_obra_v2.ep_dashboard__summary(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  is_admin boolean;
  v_today date := la_obra_v2.today_mx();
  v_month date := date_trunc('month', la_obra_v2.today_mx())::date;
  t record;
  v_yesterday numeric;
  v_pending record;
  v_stock jsonb;
  data jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_user(tok);
  is_admin := u.role = 'admin';

  select count(*) as orders, coalesce(sum(o.total), 0) as sales,
         coalesce(sum((select sum(oi.quantity * coalesce(oi.standard_unit_cost, 0)) from la_obra_v2.order_items oi where oi.order_id = o.id)), 0) as cost
  into t
  from la_obra_v2.orders o
  where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date = v_today
    and (is_admin or o.user_id = u.id);
  select coalesce(sum(o.total), 0) into v_yesterday from la_obra_v2.orders o
  where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date = v_today - 1
    and (is_admin or o.user_id = u.id);
  select count(*) filter (where payment_status = 'pending') as to_charge,
         count(*) filter (where delivery_status = 'pending') as to_deliver
  into v_pending
  from la_obra_v2.orders where order_status = 'confirmed' and (payment_status = 'pending' or delivery_status = 'pending');

  select coalesce(jsonb_agg(x order by x ->> 'level', x ->> 'name'), '[]'::jsonb) into v_stock
  from jsonb_array_elements(la_obra_v2.inv_list()) x
  where x ->> 'status' = 'active' and x ->> 'level' <> 'ok';

  data := jsonb_build_object(
    'today', jsonb_build_object(
      'sales', round(t.sales, 2),
      'orders', t.orders,
      'average_ticket', case when t.orders > 0 then round(t.sales / t.orders, 2) else 0 end,
      'yesterday_sales', round(v_yesterday, 2)),
    'pending', jsonb_build_object('to_charge', v_pending.to_charge, 'to_deliver', v_pending.to_deliver),
    'top_products', coalesce((
      select jsonb_agg(jsonb_build_object('name', nm, 'quantity', qty, 'revenue', rev) order by qty desc, nm)
      from (select p.name as nm, sum(oi.quantity) as qty, sum(oi.subtotal) as rev
            from la_obra_v2.order_items oi
            join la_obra_v2.orders o on o.id = oi.order_id
            join la_obra_v2.products p on p.id = oi.product_id
            where o.order_status = 'confirmed' and o.created_at::date = v_today and (is_admin or o.user_id = u.id)
            group by p.id, p.name order by qty desc limit 5) s), '[]'::jsonb),
    'stock_alerts', coalesce((
      select jsonb_agg(jsonb_build_object('id', x -> 'id', 'name', x -> 'name', 'stock', x -> 'stock', 'unit', x -> 'unit',
                                          'min_stock', x -> 'min_stock', 'level', x -> 'level') order by o)
      from jsonb_array_elements(v_stock) with ordinality e(x, o) where o <= 6), '[]'::jsonb),
    'stock_alerts_total', jsonb_array_length(v_stock));

  if is_admin then
    data := jsonb_set(data, '{today,gross_profit}', to_jsonb(round(t.sales - t.cost, 2)));
    data := data || jsonb_build_object('month', jsonb_build_object(
      'purchases', (select coalesce(sum(total), 0) from la_obra_v2.purchases where purchase_date >= v_month),
      'expenses', (select coalesce(sum(amount), 0) from la_obra_v2.expenses where status = 'active' and created_at::date >= v_month),
      'sales', (select coalesce(sum(total), 0) from la_obra_v2.orders
                where order_status = 'confirmed' and payment_status = 'paid' and created_at::date >= v_month)));
  end if;
  return la_obra_v2.ok('Resumen consultado', jsonb_build_object('summary', data));
end $$;
