set check_function_bodies = off;
-- =====================================================================
-- La Obra v2 · 02 · Núcleo
-- Equivalente a config/service_helpers.php, cost_engine.php, inventory.php y attendance.php.
--
-- Cómo responde cada "endpoint":
--   ok(código, mensaje, datos)   → termina bien: devuelve {status, body:{success:true, message, ...datos}}
--   fail(código, mensaje, datos) → lanza un error controlado; la función pública lo convierte en
--                                  {status, body:{success:false, message, ...}} y DESHACE todo lo que
--                                  se haya escrito en esa petición (igual que un rollback).
-- =====================================================================

-- ---------- Respuestas ----------
create or replace function la_obra_v2.ok(p_code int, p_message text, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('status', p_code,
    'body', jsonb_build_object('success', p_code < 400, 'message', p_message) || coalesce(p_extra, '{}'::jsonb));
$$;

create or replace function la_obra_v2.fail(p_code int, p_message text, p_extra jsonb default '{}'::jsonb)
returns void language plpgsql as $$
begin
  raise exception using errcode = 'LO001',
    message = jsonb_build_object('status', p_code,
      'body', jsonb_build_object('success', false, 'message', p_message) || coalesce(p_extra, '{}'::jsonb))::text;
end $$;

-- Igual que fail() pero devuelve cualquier tipo, para usarse dentro de expresiones
create or replace function la_obra_v2.method(p_method text, p_expected text)
returns void language plpgsql as $$
begin
  if p_method is distinct from p_expected then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
end $$;

-- ---------- Lectura de valores JSON ----------
-- Texto de un valor JSON (cadena, número o booleano); null si no viene o es null
create or replace function la_obra_v2.jtext(v jsonb)
returns text language sql immutable as $$
  select case when v is null or jsonb_typeof(v) = 'null' then null
              when jsonb_typeof(v) = 'string' then v #>> '{}'
              when jsonb_typeof(v) in ('number','boolean') then v::text
              else null end;
$$;

-- trim((string)($d['x'] ?? '')) de PHP
create or replace function la_obra_v2.jstr(v jsonb)
returns text language sql immutable as $$
  select btrim(coalesce(la_obra_v2.jtext(v), ''), E' \t\n\r\x0B');
$$;

-- ¿Es escalar? (cadena, número o booleano)
create or replace function la_obra_v2.is_scalar(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and jsonb_typeof(v) in ('string','number','boolean');
$$;

-- is_numeric() de PHP
create or replace function la_obra_v2.is_num(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and (jsonb_typeof(v) = 'number'
    or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') ~ '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$'));
$$;

create or replace function la_obra_v2.num(v jsonb)
returns numeric language sql immutable as $$
  select case when la_obra_v2.is_num(v) then btrim(la_obra_v2.jtext(v))::numeric else null end;
$$;

-- filter_var(..., FILTER_VALIDATE_INT)
create or replace function la_obra_v2.is_int(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and (
    (jsonb_typeof(v) = 'number' and (v::text)::numeric = trunc((v::text)::numeric) and v::text !~ '[.eE]')
    or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') ~ '^[+-]?\d{1,9}$'));
$$;

create or replace function la_obra_v2.body(b jsonb)
returns jsonb language plpgsql as $$
begin
  if b is null or jsonb_typeof(b) not in ('object','array') then perform la_obra_v2.fail(422, 'JSON inválido'); end if;
  return b;
end $$;

create or replace function la_obra_v2.positive_id(v jsonb, p_message text default 'ID inválido')
returns int language plpgsql as $$
begin
  if not la_obra_v2.is_int(v) or btrim(la_obra_v2.jtext(v))::int <= 0 then perform la_obra_v2.fail(422, p_message); end if;
  return btrim(la_obra_v2.jtext(v))::int;
end $$;

-- money(): monto con máximo 2 decimales; positivo (> 0) o no negativo (>= 0)
create or replace function la_obra_v2.money(v jsonb, p_positive boolean default true)
returns numeric language plpgsql as $$
declare n numeric;
begin
  if not la_obra_v2.is_scalar(v) or not la_obra_v2.is_num(v) then perform la_obra_v2.fail(422, 'Monto o costo inválido'); end if;
  n := la_obra_v2.num(v);
  if (p_positive and n <= 0) or (not p_positive and n < 0) or round(n, 2) <> n then
    perform la_obra_v2.fail(422, 'Monto o costo inválido');
  end if;
  return round(n, 2);
end $$;

create or replace function la_obra_v2.dateval(v jsonb, p_message text default 'Fecha inválida')
returns date language plpgsql as $$
declare s text := la_obra_v2.jtext(v); d date;
begin
  if v is null or jsonb_typeof(v) <> 'string' or s !~ '^\d{4}-\d{2}-\d{2}$' then perform la_obra_v2.fail(422, p_message); end if;
  begin d := s::date; exception when others then perform la_obra_v2.fail(422, p_message); end;
  if to_char(d, 'YYYY-MM-DD') <> s then perform la_obra_v2.fail(422, p_message); end if;
  return d;
end $$;

-- Valor de un parámetro de la URL (?x=...) o null si no viene / viene vacío
create or replace function la_obra_v2.qparam(q jsonb, k text)
returns jsonb language sql immutable as $$
  select case when q ? k and coalesce(la_obra_v2.jtext(q -> k), '') <> '' then q -> k else null end;
$$;

-- Validación de correo (aproximación a FILTER_VALIDATE_EMAIL)
create or replace function la_obra_v2.valid_email(e text)
returns boolean language sql immutable as $$
  select e ~ '^[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'
     and e !~ '\.\.' and e !~ '^\.' and e !~ '\.@';
$$;

-- ---------- Contraseñas (compatibles con password_hash de PHP) ----------
create or replace function la_obra_v2.hash_password(p text)
returns text language sql volatile as $$
  select extensions.crypt(p, extensions.gen_salt('bf', 10));
$$;

create or replace function la_obra_v2.check_password(p text, h text)
returns boolean language plpgsql as $$
declare hh text;
begin
  if p is null or h is null or h = '' then return false; end if;
  -- PHP genera $2y$; pgcrypto entiende $2a$ (es el mismo algoritmo)
  hh := regexp_replace(h, '^\$2[by]\$', '$2a$');
  return extensions.crypt(p, hh) = hh;
exception when others then
  return false;
end $$;

create or replace function la_obra_v2.sha256(t text)
returns text language sql immutable as $$
  select encode(extensions.digest(t, 'sha256'), 'hex');
$$;

-- ---------- Sesión ----------
-- Devuelve el usuario de la sesión: {id, role, status, name, username, email, must_change_password}
-- p_admin: exige rol administrador. p_admin_message: mensaje si no es admin.
create or replace function la_obra_v2.session_user_row(p_token text, p_admin boolean default false,
  p_admin_message text default 'Se requiere rol administrador', p_style text default 'helper')
returns la_obra_v2.users language plpgsql as $$
declare u la_obra_v2.users; exp timestamp;
begin
  if p_token is null or btrim(p_token) = '' or btrim(p_token) ~ '\s' then
    perform la_obra_v2.fail(401, 'Token de autenticación requerido');
  end if;
  select us.* into u from la_obra_v2.sessions s join la_obra_v2.users us on us.id = s.user_id
   where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  select s.expires_at into exp from la_obra_v2.sessions s where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  if u.id is null then
    perform la_obra_v2.fail(401, case when p_style = 'helper' then 'Sesión inválida o expirada' else 'Sesión inválida' end);
  end if;
  if exp <= localtimestamp then
    perform la_obra_v2.fail(401, case when p_style = 'helper' then 'Sesión inválida o expirada' else 'La sesión ha expirado' end);
  end if;
  if u.status <> 'active' or u.role is null or u.role not in ('admin','employee') then
    perform la_obra_v2.fail(403, case when p_style = 'helper' then 'Cuenta sin acceso' else 'La cuenta no tiene acceso al sistema' end);
  end if;
  if p_admin and u.role <> 'admin' then perform la_obra_v2.fail(403, p_admin_message); end if;
  return u;
end $$;

-- user() de service_helpers.php
create or replace function la_obra_v2.auth(p_token text, p_admin boolean default false)
returns la_obra_v2.users language sql as $$
  select la_obra_v2.session_user_row(p_token, p_admin);
$$;

-- Validación usada por los archivos PHP "largos" (mensajes: Sesión inválida / La sesión ha expirado / ...)
create or replace function la_obra_v2.auth_long(p_token text, p_admin boolean default false,
  p_admin_message text default 'No tienes permisos para realizar esta acción')
returns la_obra_v2.users language sql as $$
  select la_obra_v2.session_user_row(p_token, p_admin, p_admin_message, 'long');
$$;

-- ---------- Utilidades de JSON ----------
-- json_encode(...) estilo PHP para historiales
create or replace function la_obra_v2.audit_json(v jsonb)
returns text language sql immutable as $$ select v::text; $$;

-- ---------- Motor de costos (cost_engine.php) ----------
-- Costo por unidad base de un insumo según su última compra válida
create or replace function la_obra_v2.input_cost(p_input int)
returns numeric language sql stable as $$
  select pi.subtotal / pi.total_base_quantity
    from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id
   where pi.input_id = p_input and pi.total_base_quantity > 0 and pi.subtotal >= 0
   order by p.purchase_date desc, p.id desc, pi.id desc limit 1;
$$;

-- Costo de una preparación (lote y por unidad de rendimiento)
create or replace function la_obra_v2.preparation_cost(p_id int)
returns jsonb language plpgsql stable as $$
declare p la_obra_v2.preparations; r record; v_sum numeric := 0; v_missing jsonb := '[]'; v_detail jsonb := '[]'; v_unit numeric; v_n int := 0;
begin
  select * into p from la_obra_v2.preparations where id = p_id;
  if p.id is null or p.yield_quantity <= 0 then return null; end if;
  for r in select pi.*, i.name, i.unit from la_obra_v2.preparation_inputs pi join la_obra_v2.inputs i on i.id = pi.input_id
            where pi.preparation_id = p_id order by pi.id loop
    v_n := v_n + 1;
    v_unit := la_obra_v2.input_cost(r.input_id);
    if v_unit is null then v_missing := v_missing || to_jsonb(r.name); else v_sum := v_sum + v_unit * r.quantity; end if;
    v_detail := v_detail || jsonb_build_object('name', r.name, 'quantity', r.quantity, 'unit', r.unit, 'unit_cost', v_unit,
      'cost', case when v_unit is null then null else v_unit * r.quantity end, 'estimated', r.is_estimated);
  end loop;
  if v_n = 0 then return null; end if;
  return jsonb_build_object('name', p.name, 'yield_quantity', p.yield_quantity, 'yield_unit', p.yield_unit,
    'batch_cost', case when jsonb_array_length(v_missing) > 0 then null else v_sum end,
    'unit_cost', case when jsonb_array_length(v_missing) > 0 then null else v_sum / p.yield_quantity end,
    'missing', v_missing, 'ingredients', v_detail);
end $$;

-- Costo estándar de un producto para una modalidad (local / takeaway)
create or replace function la_obra_v2.product_cost(p_id int, p_mode text default 'local')
returns jsonb language plpgsql stable as $$
declare pr record; c record; v_total numeric := 0; v_missing jsonb := '[]'; v_detail jsonb := '[]'; v_cost numeric; v_prep jsonb;
        v_name text; v_n int := 0; v_complete boolean; v_profit numeric;
begin
  select id, name, price into pr from la_obra_v2.products where id = p_id;
  if pr.id is null then return null; end if;
  for c in select pc.*, i.name as input_name, i.unit as input_unit, p2.name as preparation_name
             from la_obra_v2.product_components pc
             left join la_obra_v2.inputs i on i.id = pc.input_id
             left join la_obra_v2.preparations p2 on p2.id = pc.preparation_id
            where pc.product_id = p_id and pc.delivery_mode in ('always', p_mode) order by pc.id loop
    v_n := v_n + 1;
    v_prep := null;
    if c.input_id is not null then
      v_cost := la_obra_v2.input_cost(c.input_id); v_name := c.input_name;
    else
      v_prep := la_obra_v2.preparation_cost(c.preparation_id);
      v_cost := (v_prep ->> 'unit_cost')::numeric; v_name := c.preparation_name;
    end if;
    if v_cost is null then v_missing := v_missing || to_jsonb(v_name); else v_total := v_total + c.quantity * v_cost; end if;
    v_detail := v_detail || jsonb_build_object('name', v_name, 'type', case when c.input_id is not null then 'input' else 'preparation' end,
      'quantity', c.quantity, 'unit', case when c.input_id is not null then c.input_unit else coalesce(v_prep ->> 'yield_unit', '') end,
      'unit_cost', v_cost, 'cost', case when v_cost is null then null else v_cost * c.quantity end,
      'estimated', c.is_estimated, 'delivery_mode', c.delivery_mode);
  end loop;
  v_complete := jsonb_array_length(v_missing) = 0 and v_n > 0;
  v_profit := case when v_complete then pr.price - v_total else null end;
  return jsonb_build_object('product_id', pr.id, 'name', pr.name, 'delivery_mode', p_mode, 'sale_price', pr.price,
    'standard_cost', case when v_complete then round(v_total, 4) else null end,
    'gross_profit', case when v_profit is null then null else round(v_profit, 4) end,
    'gross_margin', case when v_profit is null or pr.price = 0 then null else round(v_profit / pr.price * 100, 2) end,
    'missing_prices', v_missing, 'components', v_detail, 'complete', v_complete);
end $$;

-- ---------- Inventario (inventory.php) ----------
create or replace function la_obra_v2.inv_record(p_input int, p_type text, p_qty numeric, p_unit_cost numeric,
  p_ref_type text, p_ref_id int, p_note text, p_user int)
returns void language plpgsql as $$
begin
  if abs(coalesce(p_qty, 0)) < 0.0005 then return; end if;
  insert into la_obra_v2.inventory_movements(input_id, movement_type, quantity, unit_cost, reference_type, reference_id, note, user_id)
  values (p_input, p_type, round(p_qty, 3), case when p_unit_cost is null then null else round(p_unit_cost, 6) end, p_ref_type, p_ref_id, p_note, p_user);
end $$;

create or replace function la_obra_v2.inv_stock(p_input int)
returns numeric language sql stable as $$
  select coalesce(sum(quantity), 0) from la_obra_v2.inventory_movements where input_id = p_input;
$$;

create or replace function la_obra_v2.inv_sync_purchase(p_purchase int, p_user int)
returns void language plpgsql as $$
declare i record;
begin
  delete from la_obra_v2.inventory_movements where reference_type = 'purchase' and reference_id = p_purchase;
  for i in select input_id, subtotal, total_base_quantity from la_obra_v2.purchase_items where purchase_id = p_purchase order by id loop
    if coalesce(i.total_base_quantity, 0) <= 0 then continue; end if;
    perform la_obra_v2.inv_record(i.input_id, 'purchase', i.total_base_quantity, i.subtotal / i.total_base_quantity, 'purchase', p_purchase, null, p_user);
  end loop;
end $$;

-- Insumos por unidad de producto (receta + preparaciones), según modalidad
create or replace function la_obra_v2.inv_product_parts(p_product int, p_mode text default 'local')
returns table(input_id int, qty numeric) language sql stable as $$
  select x.input_id, sum(x.qty) from (
    select pc.input_id, pc.quantity as qty
      from la_obra_v2.product_components pc
     where pc.product_id = p_product and pc.delivery_mode in ('always', p_mode) and pc.input_id is not null
    union all
    select pi.input_id, pi.quantity / pr.yield_quantity * pc.quantity
      from la_obra_v2.product_components pc
      join la_obra_v2.preparations pr on pr.id = pc.preparation_id and pr.yield_quantity > 0
      join la_obra_v2.preparation_inputs pi on pi.preparation_id = pr.id
     where pc.product_id = p_product and pc.delivery_mode in ('always', p_mode) and pc.input_id is null
  ) x group by x.input_id;
$$;

create or replace function la_obra_v2.inv_consume_order(p_order int, p_user int)
returns void language plpgsql as $$
declare o record; r record;
begin
  select id, delivery_mode into o from la_obra_v2.orders where id = p_order;
  if o.id is null then return; end if;
  if exists(select 1 from la_obra_v2.inventory_movements where reference_type = 'order' and reference_id = p_order and movement_type = 'sale') then return; end if;
  for r in select pp.input_id, sum(pp.qty * oi.quantity) as qty
             from la_obra_v2.order_items oi
             cross join lateral la_obra_v2.inv_product_parts(oi.product_id, coalesce(nullif(o.delivery_mode, ''), 'local')) pp
            where oi.order_id = p_order group by pp.input_id order by pp.input_id loop
    perform la_obra_v2.inv_record(r.input_id, 'sale', -r.qty, la_obra_v2.input_cost(r.input_id), 'order', p_order, null, p_user);
  end loop;
end $$;

create or replace function la_obra_v2.inv_reverse_order(p_order int, p_user int)
returns void language plpgsql as $$
declare m record;
begin
  if exists(select 1 from la_obra_v2.inventory_movements where reference_type = 'order' and reference_id = p_order and movement_type = 'sale_reversal') then return; end if;
  for m in select input_id, quantity, unit_cost from la_obra_v2.inventory_movements
            where reference_type = 'order' and reference_id = p_order and movement_type = 'sale' order by id loop
    perform la_obra_v2.inv_record(m.input_id, 'sale_reversal', -m.quantity, m.unit_cost, 'order', p_order, 'Venta cancelada', p_user);
  end loop;
end $$;

-- Otras medidas de un insumo: [{id, name, unit_amount, base_amount, factor}] (factor = unidades principales por 1 de esta medida)
create or replace function la_obra_v2.input_units_json(p_input int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'unit_amount', u.unit_amount::float8,
           'base_amount', u.base_amount::float8, 'factor', (u.base_amount / u.unit_amount)::float8) order by lower(u.name), u.id), '[]'::jsonb)
    from la_obra_v2.input_units u where u.input_id = p_input;
$$;

create or replace function la_obra_v2.inv_list()
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.name, t.id), '[]'::jsonb) from (
    select s.id, s.name, s.unit, s.status, s.package_type, s.package_quantity, s.package_content_unit, s.min_stock,
           round(s.stock, 3) as stock, la_obra_v2.fmt_ts(s.last_purchase_at) as last_purchase_at,
           round(c.cost, 4) as unit_cost,
           case when c.cost is null then null else round(greatest(0, round(s.stock, 3)) * c.cost, 2) end as stock_value,
           case when round(s.stock, 3) <= 0 then 'out' when s.min_stock is not null and round(s.stock, 3) <= s.min_stock then 'low' else 'ok' end as level,
           la_obra_v2.input_units_json(s.id) as units
      from (select i.id, i.name, i.unit, i.status, i.package_type, i.package_quantity, i.package_content_unit, i.min_stock,
                   coalesce(sum(m.quantity), 0) as stock,
                   max(case when m.movement_type = 'purchase' then m.created_at end) as last_purchase_at
              from la_obra_v2.inputs i left join la_obra_v2.inventory_movements m on m.input_id = i.id
             group by i.id) s
      cross join lateral (select la_obra_v2.input_cost(s.id) as cost) c
  ) t;
$$;

-- ---------- Fechas como las daba MySQL: 'YYYY-MM-DD HH:MM:SS' ----------
create or replace function la_obra_v2.fmt_ts(t timestamp)
returns text language sql immutable as $$ select to_char(t, 'YYYY-MM-DD HH24:MI:SS'); $$;

-- Convierte un renglón a JSON con las fechas en formato MySQL (y deja números y booleanos como tales)
create or replace function la_obra_v2.js(r anyelement)
returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(k, case
      when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$'
        then to_jsonb(replace(substr(v #>> '{}', 1, 19), 'T', ' '))
      else v end), '{}'::jsonb)
  from jsonb_each(to_jsonb(r)) as e(k, v);
$$;

-- Lista de renglones (jsonb de cada uno ya con js()) en un arreglo
create or replace function la_obra_v2.fix_dates(j jsonb)
returns jsonb language sql immutable as $$
  select case jsonb_typeof(j)
    when 'object' then (select coalesce(jsonb_object_agg(k, la_obra_v2.fix_dates(v)), '{}'::jsonb) from jsonb_each(j) e(k, v))
    when 'array'  then (select coalesce(jsonb_agg(la_obra_v2.fix_dates(v) order by n), '[]'::jsonb) from jsonb_array_elements(j) with ordinality a(v, n))
    when 'string' then case when (j #>> '{}') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$'
                            then to_jsonb(replace(substr(j #>> '{}', 1, 19), 'T', ' ')) else j end
    else j end;
$$;

-- ---------- Asistencia (attendance.php) ----------
create or replace function la_obra_v2.coordinate(v jsonb, p_limit numeric, p_label text)
returns numeric language plpgsql as $$
begin
  if not la_obra_v2.is_scalar(v) or not la_obra_v2.is_num(v) or abs(la_obra_v2.num(v)) > p_limit then
    perform la_obra_v2.fail(422, p_label || ' inválida');
  end if;
  return round(la_obra_v2.num(v), 7);
end $$;

create or replace function la_obra_v2.distance_m(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(least(1, sqrt(
    sin(radians((lat2 - lat1)::float8) / 2) ^ 2
    + cos(radians(lat1::float8)) * cos(radians(lat2::float8)) * sin(radians((lng2 - lng1)::float8) / 2) ^ 2)));
$$;

create or replace function la_obra_v2.work_location_json()
returns jsonb language sql stable as $$
  select la_obra_v2.js(w) from (select id, name, latitude::float8 as latitude, longitude::float8 as longitude, radius_m, updated_at
                                   from la_obra_v2.work_location where id = 1) w;
$$;

create or replace function la_obra_v2.last_attendance_today(p_user int)
returns jsonb language sql stable as $$
  select la_obra_v2.js(a) from (select id, type, created_at from la_obra_v2.attendance
    where user_id = p_user and created_at::date = current_date order by created_at desc, id desc limit 1) a;
$$;

-- ---------- Mejoras (noviembre 2026) ----------

-- Cantidad de un ingrediente capturada en cualquiera de las medidas del insumo.
-- p_item: {quantity, unit_id?}. Si trae unit_id, "quantity" está en esa medida y se convierte
-- a la unidad principal; si no, "quantity" ya está en la unidad principal (como antes).
create or replace function la_obra_v2.item_quantity(p_input int, p_item jsonb,
  out o_qty numeric, out o_unit_id int, out o_unit_qty numeric)
language plpgsql as $$
declare v_q jsonb := coalesce(nullif(p_item -> 'unit_quantity', 'null'::jsonb), p_item -> 'quantity'); un la_obra_v2.input_units;
begin
  if not la_obra_v2.is_num(v_q) or la_obra_v2.num(v_q) <= 0 then perform la_obra_v2.fail(422, 'Indica la cantidad de cada ingrediente'); end if;
  if la_obra_v2.not_empty(p_item -> 'unit_id') then
    o_unit_id := la_obra_v2.positive_id(p_item -> 'unit_id', 'Medida inválida');
    select * into un from la_obra_v2.input_units where id = o_unit_id;
    if un.id is null or un.input_id <> p_input then perform la_obra_v2.fail(422, 'La medida elegida no corresponde al insumo'); end if;
    o_unit_qty := round(la_obra_v2.num(v_q), 3);
    o_qty := round(o_unit_qty * un.base_amount / un.unit_amount, 3);
    if o_qty <= 0 then perform la_obra_v2.fail(422, 'La cantidad es demasiado pequeña'); end if;
  else
    o_unit_id := null; o_unit_qty := null;
    o_qty := round(la_obra_v2.num(v_q), 3);
    if o_qty <= 0 then perform la_obra_v2.fail(422, 'Indica la cantidad de cada ingrediente'); end if;
  end if;
end $$;

-- Guarda las otras medidas de un insumo. p_units: [{id?, name, unit_amount, base_amount}]
-- Conserva las que siguen (por id), actualiza las recetas que las usan si cambió la equivalencia
-- y, si se quita una medida, sus ingredientes quedan con la misma cantidad en la unidad principal.
create or replace function la_obra_v2.save_input_units(p_input int, p_units jsonb)
returns void language plpgsql as $$
declare v_base text; it jsonb; v_name text; v_ua numeric; v_ba numeric; v_id int; v_keep int[] := '{}'; v_names text[] := '{}';
begin
  if p_units is null or jsonb_typeof(p_units) = 'null' then return; end if;
  if jsonb_typeof(p_units) <> 'array' then perform la_obra_v2.fail(422, 'Medidas inválidas'); end if;
  select lower(btrim(unit)) into v_base from la_obra_v2.inputs where id = p_input;
  -- Validar todo antes de escribir
  for it in select * from jsonb_array_elements(p_units) loop
    v_name := la_obra_v2.jstr(it -> 'name');
    if v_name = '' or char_length(v_name) > 30 then perform la_obra_v2.fail(422, 'Escribe el nombre de cada medida (máximo 30 letras)'); end if;
    if lower(v_name) = v_base then perform la_obra_v2.fail(422, '"' || v_name || '" ya es la unidad principal del insumo'); end if;
    if lower(v_name) = any(v_names) then perform la_obra_v2.fail(422, 'La medida "' || v_name || '" está repetida'); end if;
    v_names := v_names || lower(v_name);
    if not la_obra_v2.is_num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)) or la_obra_v2.num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)) <= 0
       or not la_obra_v2.is_num(it -> 'base_amount') or la_obra_v2.num(it -> 'base_amount') <= 0 then
      perform la_obra_v2.fail(422, 'Indica a cuánto equivale la medida "' || v_name || '"');
    end if;
    if la_obra_v2.not_empty(it -> 'id') then
      v_id := la_obra_v2.positive_id(it -> 'id', 'Medida inválida');
      if not exists(select 1 from la_obra_v2.input_units where id = v_id and input_id = p_input) then perform la_obra_v2.fail(422, 'Medida inválida'); end if;
      v_keep := v_keep || v_id;
    end if;
  end loop;
  -- Medidas quitadas: sus ingredientes conservan la cantidad (ya está en la unidad principal)
  update la_obra_v2.preparation_inputs set unit_id = null, unit_quantity = null
   where unit_id in (select id from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep)));
  update la_obra_v2.product_components set unit_id = null, unit_quantity = null
   where unit_id in (select id from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep)));
  delete from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep));
  -- Evitar choque de nombres al renombrar
  update la_obra_v2.input_units set name = '~' || id where input_id = p_input;
  for it in select * from jsonb_array_elements(p_units) loop
    v_name := la_obra_v2.jstr(it -> 'name');
    v_ua := round(la_obra_v2.num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)), 3);
    v_ba := round(la_obra_v2.num(it -> 'base_amount'), 4);
    if v_ua <= 0 or v_ba <= 0 then perform la_obra_v2.fail(422, 'Indica a cuánto equivale la medida "' || v_name || '"'); end if;
    if la_obra_v2.not_empty(it -> 'id') then
      v_id := la_obra_v2.num(it -> 'id')::int;
      update la_obra_v2.input_units set name = v_name, unit_amount = v_ua, base_amount = v_ba where id = v_id;
      -- Si cambió la equivalencia, las recetas capturadas en esta medida se recalculan
      update la_obra_v2.preparation_inputs set quantity = greatest(round(unit_quantity * v_ba / v_ua, 3), 0.001)
       where unit_id = v_id and unit_quantity is not null;
      update la_obra_v2.product_components set quantity = greatest(round(unit_quantity * v_ba / v_ua, 3), 0.001)
       where unit_id = v_id and unit_quantity is not null;
    else
      insert into la_obra_v2.input_units(input_id, name, unit_amount, base_amount) values (p_input, v_name, v_ua, v_ba);
    end if;
  end loop;
end $$;

-- Comisión que cobra la terminal por un pago (null si el método no tiene comisión)
create or replace function la_obra_v2.payment_commission(p_method int, p_amount numeric)
returns numeric language sql stable as $$
  select case when coalesce(pm.commission_percent, 0) > 0 and coalesce(p_amount, 0) > 0
              then round(p_amount * pm.commission_percent / 100, 2) end
    from la_obra_v2.payment_methods pm where pm.id = p_method;
$$;
