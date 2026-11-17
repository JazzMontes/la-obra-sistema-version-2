-- =====================================================================
-- La Obra v2 · 09b · reports/*
-- =====================================================================
set check_function_bodies = off;

-- Sesión de los reportes (sus propios mensajes en la v1)
create or replace function la_obra_v2.report_auth(p_token text)
returns void language plpgsql as $$
declare u record;
begin
  if p_token is null or btrim(p_token) = '' or btrim(p_token) ~ '\s' then perform la_obra_v2.fail(401, 'Token de autenticación requerido'); end if;
  select us.status, us.role, s.expires_at into u from la_obra_v2.sessions s join la_obra_v2.users us on us.id = s.user_id
   where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  if u.status is null or u.expires_at <= localtimestamp then perform la_obra_v2.fail(401, 'La sesión es inválida o ha expirado'); end if;
  if u.status <> 'active' or u.role is distinct from 'admin' then perform la_obra_v2.fail(403, 'Los reportes están disponibles para el administrador'); end if;
end $$;

-- Rango ?from=&to= de los reportes por fecha de pago
create or replace function la_obra_v2.report_range(q jsonb, out o_from date, out o_to date)
language plpgsql as $$
declare f text; t2 text;
begin
  f := coalesce(la_obra_v2.jtext(q -> 'from'), to_char(date_trunc('month', current_date), 'YYYY-MM-DD'));
  t2 := coalesce(la_obra_v2.jtext(q -> 'to'), to_char(current_date, 'YYYY-MM-DD'));
  if f !~ '^\d{4}-\d{2}-\d{2}$' or t2 !~ '^\d{4}-\d{2}-\d{2}$' then perform la_obra_v2.fail(422, 'Utiliza fechas válidas con formato AAAA-MM-DD'); end if;
  begin o_from := f::date; o_to := t2::date;
  exception when others then perform la_obra_v2.fail(422, 'Utiliza fechas válidas con formato AAAA-MM-DD'); end;
  if to_char(o_from, 'YYYY-MM-DD') <> f or to_char(o_to, 'YYYY-MM-DD') <> t2 then perform la_obra_v2.fail(422, 'Utiliza fechas válidas con formato AAAA-MM-DD'); end if;
  if o_from > o_to then perform la_obra_v2.fail(422, 'La fecha inicial no puede ser posterior a la final'); end if;
  if o_to - o_from > 365 then perform la_obra_v2.fail(422, 'Selecciona un rango de hasta 366 días'); end if;
end $$;

create or replace function la_obra_v2.ep_reports__daily(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('date', d, 'amount', amount::float8, 'orders', orders::float8) order by d), '[]') from (
      select pay.paid_at::date d, sum(pay.amount) amount, count(*) orders
        from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by pay.paid_at::date) s)));
end $$;

create or replace function la_obra_v2.ep_reports__payment_methods(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('method_id', id::float8, 'name', name, 'amount', amount::float8, 'orders', orders::float8,
             'commission', commission::float8) order by amount desc, id), '[]') from (
      select pm.id, pm.name, sum(pay.amount) amount, count(*) orders, coalesce(sum(pay.commission_amount), 0) commission
        from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id join la_obra_v2.payment_methods pm on pm.id = pay.payment_method_id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by pm.id, pm.name) s)));
end $$;

create or replace function la_obra_v2.ep_reports__products(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('product_id', id::float8, 'name', name, 'quantity', quantity::float8, 'amount', amount::float8) order by quantity desc, id), '[]') from (
      select p.id, p.name, sum(oi.quantity) quantity, sum(oi.subtotal) amount
        from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id join la_obra_v2.orders o on o.id = oi.order_id
        join la_obra_v2.payments pay on pay.order_id = o.id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by p.id, p.name) s)));
end $$;

create or replace function la_obra_v2.ep_reports__categories(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('date', d, 'category_id', id::float8, 'category', name, 'amount', amount::float8) order by d, id), '[]') from (
      select pay.paid_at::date d, c.id, c.name, sum(oi.subtotal) amount
        from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id join la_obra_v2.categories c on c.id = p.category_id
        join la_obra_v2.orders o on o.id = oi.order_id join la_obra_v2.payments pay on pay.order_id = o.id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by pay.paid_at::date, c.id, c.name) s)));
end $$;

-- reports/summary.php: reporte y corte de caja del periodo (por fecha del pedido)
create or replace function la_obra_v2.ep_reports__summary(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_from date; v_to date; tt record; cs record; v_purch numeric; v_exp numeric; v_waste numeric; canc record; v_sales numeric; v_cos numeric;
        v_methods jsonb; v_cash_sales numeric := 0; v_cash_purch numeric; v_fees numeric;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_from := la_obra_v2.dateval(coalesce(q -> 'from', to_jsonb(to_char(current_date, 'YYYY-MM-DD'))));
  v_to := la_obra_v2.dateval(coalesce(q -> 'to', to_jsonb(to_char(current_date, 'YYYY-MM-DD'))));
  if v_from > v_to then perform la_obra_v2.fail(422, 'La fecha inicial no puede ser mayor que la final'); end if;
  if v_to - v_from > 366 then perform la_obra_v2.fail(422, 'El periodo máximo es de un año'); end if;

  create temporary table if not exists lo_paid(id int primary key) on commit drop;
  truncate lo_paid;
  insert into lo_paid select o.id from la_obra_v2.orders o
   where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date between v_from and v_to;

  select count(*) orders, coalesce(sum(o.total), 0) sales into tt from la_obra_v2.orders o join lo_paid p on p.id = o.id;
  select coalesce(sum(oi.quantity * oi.standard_unit_cost), 0) cost, count(*) filter (where oi.standard_unit_cost is null) no_cost
    into cs from la_obra_v2.order_items oi join lo_paid p on p.id = oi.order_id;
  select coalesce(sum(total), 0) into v_purch from la_obra_v2.purchases where purchase_date between v_from and v_to;
  select coalesce(sum(amount), 0) into v_exp from la_obra_v2.expenses where status = 'active' and created_at::date between v_from and v_to;
  select coalesce(sum(estimated_total_cost), 0) into v_waste from la_obra_v2.waste_records where waste_date between v_from and v_to;
  select count(*) n, coalesce(sum(total), 0) tot into canc from la_obra_v2.orders o where o.order_status = 'cancelled' and o.created_at::date between v_from and v_to;
  v_sales := tt.sales; v_cos := cs.cost;

  select coalesce(sum(pay.commission_amount), 0) into v_fees from la_obra_v2.payments pay join lo_paid p on p.id = pay.order_id;
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'orders', orders::float8, 'amount', amount::float8, 'commission', commission::float8) order by amount desc, id), '[]') into v_methods from (
    select pm.id, pm.name, count(*) orders, sum(pay.amount) amount, coalesce(sum(pay.commission_amount), 0) commission
      from la_obra_v2.payments pay join lo_paid p on p.id = pay.order_id join la_obra_v2.payment_methods pm on pm.id = pay.payment_method_id
     group by pm.id, pm.name) s;
  select coalesce((select (x ->> 'amount')::numeric from jsonb_array_elements(v_methods) x where lower(btrim(x ->> 'name')) = 'efectivo' limit 1), 0) into v_cash_sales;
  select coalesce(sum(p.total), 0) into v_cash_purch from la_obra_v2.purchases p join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
   where lower(pm.name) = 'efectivo' and p.purchase_date between v_from and v_to;

  return la_obra_v2.ok(200, 'Reporte generado', jsonb_build_object('report', jsonb_build_object(
    'from', v_from, 'to', v_to,
    'totals', jsonb_build_object('sales', round(v_sales, 2)::float8, 'orders', tt.orders,
      'average_ticket', case when tt.orders > 0 then round(v_sales / tt.orders, 2)::float8 else 0 end,
      'cost_of_sales', round(v_cos, 2)::float8, 'gross_profit', round(v_sales - v_cos, 2)::float8,
      'gross_margin', case when v_sales > 0 then round((v_sales - v_cos) / v_sales * 100, 1)::float8 else null end,
      'lines_without_cost', cs.no_cost, 'purchases', round(v_purch, 2)::float8, 'expenses', round(v_exp, 2)::float8,
      'waste', round(v_waste, 2)::float8, 'cancelled_orders', canc.n, 'cancelled_amount', round(canc.tot, 2)::float8,
      -- Comisiones de la terminal (tarjeta): lo que se queda el banco de las ventas cobradas
      'card_fees', round(v_fees, 2)::float8, 'net_sales', round(v_sales - v_fees, 2)::float8,
      'profit_after_fees', round(v_sales - v_cos - v_fees, 2)::float8),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'orders', orders::float8, 'sales', sales::float8) order by day), '[]') from (
        select o.created_at::date as day, count(*) orders, sum(o.total) sales from la_obra_v2.orders o join lo_paid p on p.id = o.id group by o.created_at::date) s),
    'products', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'quantity', quantity::float8, 'revenue', revenue::float8, 'cost', cost::float8) order by revenue desc, id), '[]') from (
        select pr.id, pr.name, sum(oi.quantity) quantity, sum(oi.subtotal) revenue, sum(oi.quantity * coalesce(oi.standard_unit_cost, 0)) cost
          from la_obra_v2.order_items oi join lo_paid p on p.id = oi.order_id join la_obra_v2.products pr on pr.id = oi.product_id group by pr.id, pr.name) s),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'quantity', quantity::float8, 'revenue', revenue::float8) order by revenue desc, id), '[]') from (
        select c.id, c.name, sum(oi.quantity) quantity, sum(oi.subtotal) revenue
          from la_obra_v2.order_items oi join lo_paid p on p.id = oi.order_id join la_obra_v2.products pr on pr.id = oi.product_id
          join la_obra_v2.categories c on c.id = pr.category_id group by c.id, c.name) s),
    'payment_methods', v_methods,
    'cash_cut', jsonb_build_object('cash_sales', round(v_cash_sales, 2)::float8, 'cash_purchases', round(v_cash_purch, 2)::float8,
      'expenses', round(v_exp, 2)::float8, 'expected_cash', round(v_cash_sales - v_cash_purch - v_exp, 2)::float8))));
end $$;
