-- =====================================================================
-- La Obra v2 · 12 · Editar pedidos que aún no se entregan
-- Se puede correr solo (Supabase → SQL Editor → New query → pegar → Run) sobre una base ya
-- instalada. No borra ni cambia datos existentes: agrega 2 columnas a orders, 1 tabla nueva
-- (order_edits) y actualiza/crea rutas de la API.
--
--   orders/edit.php   POST { order_id, items: [{product_id, quantity}], delivery_mode?, customer_name?,
--                            payment?: null | { payment_method_id, cash_received?, difference_received? }, reason? }
--                     · Solo pedidos confirmados y NO entregados (lo entregado ya descontó inventario).
--                     · Los productos que ya estaban conservan el precio con el que se vendieron;
--                       los nuevos entran con el precio actual.
--                     · payment = null  → el pedido queda "por cobrar" (se quita el cobro si había).
--                       payment = {...} → se cobra / se corrige el cobro con el nuevo total:
--                         mismo método → solo se cuadra la diferencia (regresar o cobrar de más;
--                         difference_received = con cuánto pagó la diferencia en efectivo);
--                         otro método o antes sin cobrar → cash_received = con cuánto pagó el total.
--                       sin payment     → se conserva el cobro y se ajusta al nuevo total.
--                     · Cada edición queda registrada (quién, cuándo, qué cambió, antes y después).
--   orders/edits.php  GET ?id=N → historial de ediciones de un pedido
--
-- También actualiza orders/active.php, sales/index.php y sales/show.php para que digan si el
-- pedido se editó (edited_at, edit_count) y traigan los datos del cobro.
-- =====================================================================
set check_function_bodies = off;

-- ---------- Tablas ----------
alter table la_obra_v2.orders add column if not exists edited_at timestamp null;
alter table la_obra_v2.orders add column if not exists edit_count int not null default 0;

create table if not exists la_obra_v2.order_edits (
  id          serial primary key,
  order_id    int not null references la_obra_v2.orders(id) on update cascade on delete cascade,
  user_id     int not null references la_obra_v2.users(id) on update cascade on delete restrict,
  edited_at   timestamp not null default localtimestamp,
  summary     text not null,
  reason      varchar(255) null,
  before_data jsonb not null,
  after_data  jsonb not null
);
alter table la_obra_v2.order_edits add column if not exists payment_adjustment jsonb null;
create index if not exists idx_order_edits_order on la_obra_v2.order_edits(order_id);
alter table la_obra_v2.order_edits enable row level security;

-- ---------- Utilidades ----------
create or replace function la_obra_v2.fmt_money(v numeric)
returns text language sql immutable as $$
  select '$' || to_char(coalesce(v, 0), 'FM999,999,990.00');
$$;

-- Foto del pedido para comparar antes / después
create or replace function la_obra_v2.order_snapshot(p_order int)
returns jsonb language sql stable as $$
  select jsonb_build_object('total', o.total::float8, 'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name,
    'payment_status', o.payment_status, 'items', la_obra_v2.order_items_json(o.id),
    'payment', (select jsonb_build_object('payment_method_id', p.payment_method_id, 'payment_method', pm.name, 'amount', p.amount::float8,
                  'cash_received', p.cash_received::float8, 'change_amount', p.change_amount::float8)
                  from la_obra_v2.payments p join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id where p.order_id = o.id))
  from la_obra_v2.orders o where o.id = p_order;
$$;

-- Resumen legible de lo que cambió: "Quitó 1× Hamburguesa doble · Agregó 1× Hamburguesa · Total: $100.00 → $80.00 · Se regresaron $20.00 …"
-- adj = cómo se cuadró el cobro (ver ep_orders__edit)
drop function if exists la_obra_v2.order_edit_summary(jsonb, jsonb);
create or replace function la_obra_v2.order_edit_summary(a jsonb, z jsonb, adj jsonb default null)
returns text language plpgsql immutable as $$
declare parts text[] := '{}'; r record; pz jsonb := z -> 'payment'; v_t text; v_m text;
begin
  for r in
    select coalesce(x.pid, y.pid) as pid, coalesce(y.name, x.name) as name, coalesce(x.qty, 0) as q0, coalesce(y.qty, 0) as q1, x.ord as o0, y.ord as o1,
           coalesce(x.notes, '[]'::jsonb) as n0, coalesce(y.notes, '[]'::jsonb) as n1
      from (select (e ->> 'product_id')::int as pid, e ->> 'name' as name, (e ->> 'quantity')::int as qty, n as ord, e -> 'notes' as notes
              from jsonb_array_elements(coalesce(a -> 'items', '[]')) with ordinality s(e, n)) x
      full join (select (e ->> 'product_id')::int as pid, e ->> 'name' as name, (e ->> 'quantity')::int as qty, n as ord, e -> 'notes' as notes
              from jsonb_array_elements(coalesce(z -> 'items', '[]')) with ordinality s(e, n)) y on y.pid = x.pid
     order by (x.ord is null), x.ord, y.ord
  loop
    if r.q0 = 0 and r.q1 > 0 then parts := parts || ('Agregó ' || r.q1 || '× ' || r.name);
    elsif r.q1 = 0 and r.q0 > 0 then parts := parts || ('Quitó ' || r.q0 || '× ' || r.name);
    elsif r.q0 <> r.q1 then parts := parts || (r.name || ': ' || r.q0 || ' → ' || r.q1);
    end if;
    -- Preferencias por pieza ("1 sin tomate")
    if r.q1 > 0 and r.n0 is distinct from r.n1 then
      parts := parts || ('Preferencias de ' || r.name || ': ' || coalesce(nullif(la_obra_v2.notes_text(r.n1), ''), 'ninguna'));
    end if;
  end loop;
  if (a ->> 'delivery_mode') is distinct from (z ->> 'delivery_mode') then
    parts := parts || ('Ahora ' || case when z ->> 'delivery_mode' = 'takeaway' then 'para llevar' else 'para comer aquí' end);
  end if;
  if coalesce(a ->> 'customer_name', '') is distinct from coalesce(z ->> 'customer_name', '') then
    parts := parts || ('Cliente: ' || coalesce(nullif(a ->> 'customer_name', ''), '—') || ' → ' || coalesce(nullif(z ->> 'customer_name', ''), '—'));
  end if;
  if (a ->> 'total')::numeric is distinct from (z ->> 'total')::numeric then
    parts := parts || ('Total: ' || la_obra_v2.fmt_money((a ->> 'total')::numeric) || ' → ' || la_obra_v2.fmt_money((z ->> 'total')::numeric));
  end if;

  if adj is not null then
    v_t := adj ->> 'type';
    v_m := adj ->> 'method';
    if v_t = 'refund' then
      parts := parts || ('Se regresaron ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' al cliente (' || v_m || ')');
    elsif v_t = 'charge' then
      parts := parts || ('Cobró ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' más (' || v_m || ')'
        || case when adj ? 'received' then
             case when (adj ->> 'change')::numeric > 0
                  then ': pagó con ' || la_obra_v2.fmt_money((adj ->> 'received')::numeric) || ', cambio ' || la_obra_v2.fmt_money((adj ->> 'change')::numeric)
                  else ': pago exacto' end
           else '' end);
    elsif v_t in ('new', 'method_change') then
      parts := parts || (case when v_t = 'method_change'
                                then 'Cambió el cobro de ' || (adj ->> 'method_before') || ' a ' || v_m || ': se regresaron '
                                     || la_obra_v2.fmt_money((adj ->> 'refund')::numeric) || ' (' || (adj ->> 'method_before') || ') y se cobraron '
                                     || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' (' || v_m || ')'
                                else 'Cobrado con ' || v_m || ' ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) end
        || case when adj ? 'received' then
             case when (adj ->> 'change')::numeric > 0
                  then ': pagó con ' || la_obra_v2.fmt_money((adj ->> 'received')::numeric) || ', cambio ' || la_obra_v2.fmt_money((adj ->> 'change')::numeric)
                  else ': pago exacto' end
           else '' end);
    elsif v_t = 'removed' then
      parts := parts || ('Se quitó el cobro: se regresaron ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' al cliente (' || v_m || '); queda por cobrar');
    end if;
  end if;
  if cardinality(parts) = 0 then return null; end if;
  return array_to_string(parts, ' · ');
end $$;

-- ---------- orders/edit.php ----------
create or replace function la_obra_v2.ep_orders__edit(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record; v_mode text; v_customer text; v_reason text; it jsonb; v_pid int; v_q int;
        v_lines jsonb := '{}'; k text; pr record; v_before jsonb; v_after jsonb; v_summary text; v_total numeric;
        v_pay jsonb; v_has_pay boolean; pm record; cur record; v_cash numeric; v_change numeric; v_cash_j jsonb;
        v_adj jsonb; v_diff numeric; v_received numeric; v_is_cash boolean;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'order_id', 'El id del pedido no es válido');
  select id, order_status, delivery_status, delivery_mode, customer_name into o from la_obra_v2.orders where id = v_id for update;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status = 'cancelled' then perform la_obra_v2.fail(409, 'El pedido está cancelado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'El pedido aún no está confirmado'); end if;
  if o.delivery_status = 'delivered' then perform la_obra_v2.fail(409, 'El pedido ya se entregó; ya no se puede editar'); end if;

  -- Modalidad y cliente (si no vienen, se conservan)
  v_mode := o.delivery_mode;
  if b ? 'delivery_mode' and la_obra_v2.jtext(b -> 'delivery_mode') is not null then v_mode := la_obra_v2.jtext(b -> 'delivery_mode'); end if;
  if v_mode not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  v_customer := o.customer_name;
  if b ? 'customer_name' then v_customer := nullif(la_obra_v2.jstr(b -> 'customer_name'), ''); end if;
  if char_length(coalesce(v_customer, '')) > 80 then perform la_obra_v2.fail(422, 'Nombre del cliente demasiado largo'); end if;
  v_reason := nullif(la_obra_v2.jstr(b -> 'reason'), '');
  if char_length(coalesce(v_reason, '')) > 255 then perform la_obra_v2.fail(422, 'El motivo es demasiado largo'); end if;

  -- Productos (se juntan repetidos)
  if jsonb_typeof(b -> 'items') is distinct from 'array' or jsonb_array_length(b -> 'items') = 0 then
    perform la_obra_v2.fail(422, 'El pedido debe tener al menos un producto; si ya no lo quieren, cancélalo');
  end if;
  for it in select * from jsonb_array_elements(b -> 'items') loop
    v_pid := la_obra_v2.positive_id(it -> 'product_id');
    if not la_obra_v2.is_int(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 or la_obra_v2.num(it -> 'quantity') > 999 then
      perform la_obra_v2.fail(422, 'Cantidad inválida');
    end if;
    v_q := la_obra_v2.num(it -> 'quantity');
    v_lines := jsonb_set(v_lines, array[v_pid::text], to_jsonb(coalesce((v_lines ->> v_pid::text)::int, 0) + v_q));
  end loop;
  -- Solo se exige que esté disponible lo que se agrega; lo que ya estaba se respeta
  for k in select key from jsonb_each(v_lines) loop
    if not exists(select 1 from la_obra_v2.order_items where order_id = v_id and product_id = k::int) then
      select id, name, price, status, is_available into pr from la_obra_v2.products where id = k::int;
      if pr.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
      if pr.status <> 'active' or not pr.is_available then perform la_obra_v2.fail(409, pr.name || ' no está disponible'); end if;
    end if;
  end loop;

  v_before := la_obra_v2.order_snapshot(v_id);

  -- Quitar, cambiar cantidad y agregar
  delete from la_obra_v2.order_items where order_id = v_id and not (v_lines ? product_id::text);
  for k, v_q in select e.key, e.value::int from jsonb_each_text(v_lines) e loop
    if exists(select 1 from la_obra_v2.order_items where order_id = v_id and product_id = k::int) then
      update la_obra_v2.order_items set quantity = v_q, subtotal = round(unit_price * v_q, 2)
       where order_id = v_id and product_id = k::int and quantity <> v_q;
    else
      select price into pr from la_obra_v2.products where id = k::int;
      insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal, standard_unit_cost)
      values (v_id, k::int, v_q, pr.price, round(pr.price * v_q, 2), (la_obra_v2.product_cost(k::int, v_mode) ->> 'standard_cost')::numeric);
    end if;
  end loop;
  -- Si cambió la modalidad, el costo estándar de cada línea se vuelve a calcular (empaques para llevar, etc.)
  if v_mode is distinct from o.delivery_mode then
    update la_obra_v2.order_items oi set standard_unit_cost = (la_obra_v2.product_cost(oi.product_id, v_mode) ->> 'standard_cost')::numeric
     where oi.order_id = v_id;
  end if;
  -- Preferencias por pieza: se cambian solo si vienen; si no, se conservan (recortadas a la nueva cantidad)
  perform la_obra_v2.order_apply_notes(v_id, b -> 'items');
  select round(coalesce(sum(subtotal), 0), 2) into v_total from la_obra_v2.order_items where order_id = v_id;
  update la_obra_v2.orders set total = v_total, delivery_mode = v_mode, customer_name = v_customer where id = v_id;

  -- Cobro. Se cuadra contra lo que ya se había cobrado:
  --   · mismo método y el total bajó  → se regresa la diferencia al cliente
  --   · mismo método y el total subió → se cobra la diferencia (en efectivo: con cuánto pagó y su cambio)
  --   · otro método                   → se regresa el cobro anterior y se cobra el nuevo total completo
  --   · antes por cobrar              → se cobra el total completo
  --   · payment = null                → se quita el cobro y se regresa lo cobrado
  -- En payments siempre queda amount = nuevo total y, en efectivo, cash_received − change_amount = amount.
  v_has_pay := b ? 'payment';
  v_pay := b -> 'payment';
  select p.id, p.payment_method_id, p.amount, p.cash_received, p.change_amount, pm2.name into cur
    from la_obra_v2.payments p join la_obra_v2.payment_methods pm2 on pm2.id = p.payment_method_id where p.order_id = v_id;
  if v_has_pay and (v_pay is null or jsonb_typeof(v_pay) = 'null') then
    if cur.id is not null then
      v_adj := jsonb_build_object('type', 'removed', 'amount', cur.amount, 'method', cur.name);
      delete from la_obra_v2.payments where order_id = v_id;
    end if;
    update la_obra_v2.orders set payment_status = 'pending' where id = v_id;
  elsif v_has_pay or cur.id is not null then
    if v_has_pay then
      if jsonb_typeof(v_pay) <> 'object' then perform la_obra_v2.fail(422, 'Datos de pago inválidos'); end if;
      select id, name, status into pm from la_obra_v2.payment_methods where id = la_obra_v2.positive_id(v_pay -> 'payment_method_id', 'Elige el método de pago');
      if pm.id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
      -- Un método que ya se desactivó solo se acepta si es el que ya tenía el cobro
      if pm.status <> 'active' and pm.id is distinct from cur.payment_method_id then perform la_obra_v2.fail(409, 'El método de pago está inactivo'); end if;
    else
      v_pay := '{}'::jsonb;
      select id, name, status into pm from la_obra_v2.payment_methods where id = cur.payment_method_id;
    end if;
    v_is_cash := lower(btrim(pm.name)) = 'efectivo';
    v_cash := null; v_change := null;

    if cur.id is not null and pm.id = cur.payment_method_id then
      -- Mismo método: solo se cuadra la diferencia
      v_diff := v_total - cur.amount;
      if v_diff > 0 then
        v_adj := jsonb_build_object('type', 'charge', 'amount', v_diff, 'method', pm.name);
        if v_is_cash then
          v_cash_j := coalesce(nullif(v_pay -> 'difference_received', 'null'::jsonb), to_jsonb(v_diff));
          if not la_obra_v2.is_num(v_cash_j) or la_obra_v2.num(v_cash_j) < v_diff then
            perform la_obra_v2.fail(422, 'Con lo que pagó no alcanza la diferencia (' || la_obra_v2.fmt_money(v_diff) || ')');
          end if;
          v_received := round(la_obra_v2.num(v_cash_j), 2);
          v_change := round(v_received - v_diff, 2);
          v_cash := v_total + v_change;
          v_adj := v_adj || jsonb_build_object('received', v_received, 'change', v_change);
        end if;
      elsif v_diff < 0 then
        v_adj := jsonb_build_object('type', 'refund', 'amount', -v_diff, 'method', pm.name);
        if v_is_cash then v_cash := v_total; v_change := 0; end if;
      else
        v_cash := cur.cash_received; v_change := cur.change_amount;
      end if;
    else
      -- Cobro nuevo (o con otro método): el nuevo total completo
      v_adj := jsonb_build_object('type', case when cur.id is null then 'new' else 'method_change' end, 'amount', v_total, 'method', pm.name);
      if cur.id is not null then v_adj := v_adj || jsonb_build_object('method_before', cur.name, 'refund', cur.amount); end if;
      if v_is_cash then
        v_cash_j := coalesce(nullif(v_pay -> 'cash_received', 'null'::jsonb), to_jsonb(v_total));
        if not la_obra_v2.is_num(v_cash_j) or la_obra_v2.num(v_cash_j) < v_total then
          perform la_obra_v2.fail(422, 'El efectivo recibido debe cubrir el nuevo total (' || la_obra_v2.fmt_money(v_total) || ')');
        end if;
        v_cash := round(la_obra_v2.num(v_cash_j), 2);
        v_change := round(v_cash - v_total, 2);
        v_adj := v_adj || jsonb_build_object('received', v_cash, 'change', v_change);
      end if;
    end if;

    if cur.id is not null then
      update la_obra_v2.payments set payment_method_id = pm.id, amount = v_total, cash_received = v_cash, change_amount = v_change,
             commission_amount = la_obra_v2.payment_commission(pm.id, v_total)
       where id = cur.id;
    else
      insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount, commission_amount)
      values (v_id, pm.id, v_total, v_cash, v_change, la_obra_v2.payment_commission(pm.id, v_total));
    end if;
    update la_obra_v2.orders set payment_status = 'paid' where id = v_id;
  end if;

  v_after := la_obra_v2.order_snapshot(v_id);
  v_summary := la_obra_v2.order_edit_summary(v_before, v_after, v_adj);
  if v_summary is null then perform la_obra_v2.fail(422, 'No hiciste ningún cambio'); end if;

  insert into la_obra_v2.order_edits(order_id, user_id, summary, reason, before_data, after_data, payment_adjustment)
  values (v_id, u.id, v_summary, v_reason, v_before, v_after, v_adj);
  update la_obra_v2.orders set edited_at = localtimestamp, edit_count = edit_count + 1 where id = v_id;

  return la_obra_v2.ok(200, 'Pedido actualizado', jsonb_build_object(
    'order', jsonb_build_object('id', v_id, 'total', v_total::float8, 'payment_status', v_after ->> 'payment_status',
      'change_amount', v_change::float8),
    'edit', jsonb_build_object('summary', v_summary, 'payment_adjustment', v_adj)));
end $$;

-- ---------- orders/edits.php ----------
create or replace function la_obra_v2.order_edits_json(p_order int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'edited_at', e.edited_at, 'user_name', us.name, 'summary', e.summary,
    'reason', e.reason, 'total_before', (e.before_data ->> 'total')::float8, 'total_after', (e.after_data ->> 'total')::float8,
    'payment_adjustment', e.payment_adjustment)
    order by e.edited_at desc, e.id desc), '[]'::jsonb)
  from la_obra_v2.order_edits e join la_obra_v2.users us on us.id = e.user_id where e.order_id = p_order;
$$;

create or replace function la_obra_v2.ep_orders__edits(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(q -> 'id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id');
  select id, user_id, created_at, delivery_status, order_status into o from la_obra_v2.orders where id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  -- El empleado ve lo mismo que en el historial (sus pedidos del día) y los pedidos en curso
  if u.role = 'employee' and not (o.order_status = 'confirmed' and o.delivery_status = 'pending')
     and (o.user_id <> u.id or o.created_at::date <> current_date) then
    perform la_obra_v2.fail(403, 'Solo puedes consultar tus pedidos del día');
  end if;
  return la_obra_v2.ok(200, 'Ediciones del pedido', jsonb_build_object('edits', la_obra_v2.order_edits_json(v_id)));
end $$;

-- ---------- Rutas existentes con datos de edición y cobro ----------
create or replace function la_obra_v2.ep_orders__active(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Pedidos en curso', jsonb_build_object('orders', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'total', o.total::float8, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name, 'created_at', o.created_at,
      'confirmed_at', o.confirmed_at, 'user_name', u.name, 'edited_at', o.edited_at, 'edit_count', o.edit_count,
      'payment_method_id', p.payment_method_id, 'payment_method', pm.name, 'cash_received', p.cash_received::float8,
      'change_amount', p.change_amount::float8, 'items', la_obra_v2.order_items_json(o.id)) order by o.created_at, o.id), '[]')
    from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id
    left join la_obra_v2.payments p on p.order_id = o.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where o.order_status = 'confirmed' and (o.payment_status = 'pending' or o.delivery_status = 'pending'))));
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
      'commission_amount', p.commission_amount::float8, 'cash_received', p.cash_received::float8, 'change_amount', p.change_amount::float8,
      'edited_at', o.edited_at, 'edit_count', o.edit_count,
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
  select o2.*, us.name as user_name, p.id as payment_id, p.amount, p.cash_received, p.change_amount, p.paid_at, p.commission_amount, pm.id as pm_id, pm.name as pm_name
    into o from la_obra_v2.orders o2 join la_obra_v2.users us on us.id = o2.user_id
    left join la_obra_v2.payments p on p.order_id = o2.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id where o2.id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Venta o pedido no encontrado'); end if;
  if u.role = 'employee' and (o.user_id <> u.id or o.created_at::date <> current_date) then perform la_obra_v2.fail(403, 'Solo puedes consultar tus pedidos del día'); end if;
  return la_obra_v2.ok(200, 'Venta', jsonb_build_object('sale', jsonb_build_object('id', o.id, 'user', jsonb_build_object('id', o.user_id, 'name', o.user_name),
    'order_status', o.order_status, 'payment_status', o.payment_status, 'delivery_status', o.delivery_status, 'total', o.total::float8,
    'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at,
    'edited_at', o.edited_at, 'edit_count', o.edit_count, 'edits', la_obra_v2.order_edits_json(o.id),
    'items', la_obra_v2.order_items_json(o.id),
    'payment', case when o.payment_id is null then null else jsonb_build_object('id', o.payment_id, 'payment_method_id', o.pm_id, 'payment_method', o.pm_name,
      'amount', o.amount::float8, 'cash_received', o.cash_received::float8, 'change_amount', o.change_amount::float8, 'paid_at', o.paid_at,
      'commission_amount', o.commission_amount::float8) end)));
end $$;

-- Que la API de Supabase vea los cambios sin esperar
notify pgrst, 'reload schema';
