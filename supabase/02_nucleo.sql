-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 02 · Núcleo: funciones de apoyo que antes estaban en backend/config/
--   service_helpers.php  -> validaciones, respuestas, sesión, compras, gastos
--   cost_engine.php      -> costos estándar (insumo, preparación, producto)
--   inventory.php        -> kárdex de inventario
-- Los errores se lanzan con el código HTTP que usaba PHP (ver fail()).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Respuestas y errores
-- ---------------------------------------------------------------------

-- Equivale a out($code, $message) cuando $code >= 400.
-- Lanza un error con SQLSTATE 'PTxxx': Supabase (PostgREST) responde con ese
-- código HTTP y {"message": "..."} — la app lo muestra igual que antes.
-- Todo lo que se haya escrito en la base durante la petición se deshace.
create or replace function la_obra_v2.fail(p_code integer, p_message text, p_extra jsonb default null)
returns void language plpgsql as $$
begin
  raise exception using
    errcode = 'PT' || lpad(p_code::text, 3, '0'),
    message = p_message,
    detail  = coalesce(p_extra::text, '');
end $$;

-- Equivale a out(200, $message, $extra)
create or replace function la_obra_v2.ok(p_message text, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('success', true, 'message', p_message) || coalesce(p_extra, '{}'::jsonb)
$$;

-- Validar el método HTTP que pidió la app
create or replace function la_obra_v2.method(p_method text, p_expected text)
returns void language plpgsql as $$
begin
  if upper(coalesce(p_method, '')) <> upper(p_expected) then
    perform la_obra_v2.fail(405, 'Método no permitido');
  end if;
end $$;

-- Las fechas y horas salen como "2026-11-07 14:30:00" (igual que MySQL)
create or replace function la_obra_v2.fix_ts(j jsonb)
returns jsonb language plpgsql immutable as $$
declare t text;
begin
  case jsonb_typeof(j)
    when 'object' then
      return (select coalesce(jsonb_object_agg(k, la_obra_v2.fix_ts(v)), '{}'::jsonb) from jsonb_each(j) e(k, v));
    when 'array' then
      return (select coalesce(jsonb_agg(la_obra_v2.fix_ts(v) order by o), '[]'::jsonb)
              from jsonb_array_elements(j) with ordinality a(v, o));
    when 'string' then
      t := j #>> '{}';
      if length(t) = 19 and t ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$' then
        return to_jsonb(replace(t, 'T', ' '));
      end if;
      return j;
    else
      return j;
  end case;
end $$;

-- ---------------------------------------------------------------------
-- Lectura de valores enviados por la app (equivalentes a PHP)
-- ---------------------------------------------------------------------

-- (string) $v  — null -> '', true -> '1', false -> ''
create or replace function la_obra_v2.jstr(v jsonb)
returns text language sql immutable as $$
  select case jsonb_typeof(v)
    when 'string'  then v #>> '{}'
    when 'number'  then v #>> '{}'
    when 'boolean' then case when (v #>> '{}')::boolean then '1' else '' end
    else ''
  end
$$;

-- trim((string)$v)
create or replace function la_obra_v2.jtrim(v jsonb)
returns text language sql immutable as $$
  select btrim(la_obra_v2.jstr(v), E' \t\n\r\x0B')
$$;

-- is_numeric($v)
create or replace function la_obra_v2.is_num(v jsonb)
returns boolean language sql immutable as $$
  select case jsonb_typeof(v)
    when 'number' then true
    when 'string' then (v #>> '{}') ~ '^\s*[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\s*$'
    else false
  end
$$;

create or replace function la_obra_v2.num(v jsonb)
returns numeric language sql immutable as $$
  select case when la_obra_v2.is_num(v) then btrim(v #>> '{}')::numeric else null end
$$;

-- filter_var($v, FILTER_VALIDATE_INT) !== false
create or replace function la_obra_v2.is_int(v jsonb)
returns boolean language sql immutable as $$
  select case jsonb_typeof(v)
    when 'number' then (v #>> '{}')::numeric = trunc((v #>> '{}')::numeric) and abs((v #>> '{}')::numeric) < 2147483648
    when 'string' then (v #>> '{}') ~ '^\s*[+-]?\d{1,10}\s*$' and abs(btrim(v #>> '{}')::numeric) < 2147483648
    else false
  end
$$;

create or replace function la_obra_v2.int_of(v jsonb)
returns integer language sql immutable as $$
  select case when la_obra_v2.is_int(v) then btrim(v #>> '{}')::numeric::integer else null end
$$;

-- positiveId($v)
create or replace function la_obra_v2.pos_id(v jsonb, p_message text default 'ID inválido')
returns integer language plpgsql immutable as $$
begin
  if not la_obra_v2.is_int(v) or la_obra_v2.int_of(v) <= 0 then
    perform la_obra_v2.fail(422, p_message);
  end if;
  return la_obra_v2.int_of(v);
end $$;

-- !empty($v)
create or replace function la_obra_v2.truthy(v jsonb)
returns boolean language sql immutable as $$
  select case jsonb_typeof(v)
    when 'boolean' then (v #>> '{}')::boolean
    when 'number'  then (v #>> '{}')::numeric <> 0
    when 'string'  then (v #>> '{}') not in ('', '0')
    when 'array'   then jsonb_array_length(v) > 0
    when 'object'  then v <> '{}'::jsonb
    else false
  end
$$;

-- money($v, $positive)
create or replace function la_obra_v2.money(v jsonb, p_positive boolean default true)
returns numeric language plpgsql immutable as $$
declare n numeric;
begin
  if not la_obra_v2.is_num(v) then perform la_obra_v2.fail(422, 'Monto o costo inválido'); end if;
  n := la_obra_v2.num(v);
  if (p_positive and n <= 0) or (not p_positive and n < 0) or round(n, 2) <> n then
    perform la_obra_v2.fail(422, 'Monto o costo inválido');
  end if;
  return round(n, 2);
end $$;

-- dateval($v): 'AAAA-MM-DD' válida
create or replace function la_obra_v2.is_date(t text)
returns boolean language plpgsql immutable as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  return to_char(to_date(t, 'YYYY-MM-DD'), 'YYYY-MM-DD') = t;
exception when others then
  return false;
end $$;

create or replace function la_obra_v2.dateval(v jsonb, p_message text default 'Fecha inválida')
returns date language plpgsql immutable as $$
begin
  if jsonb_typeof(v) is distinct from 'string' or not la_obra_v2.is_date(v #>> '{}') then
    perform la_obra_v2.fail(422, p_message);
  end if;
  return (v #>> '{}')::date;
end $$;

-- Parámetro de la URL (?clave=valor). Vacío = no enviado.
create or replace function la_obra_v2.qp(q jsonb, k text)
returns text language sql immutable as $$
  select nullif(la_obra_v2.jstr(q -> k), '')
$$;

create or replace function la_obra_v2.valid_email(t text)
returns boolean language sql immutable as $$
  select t ~ '^[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'
$$;

-- ---------------------------------------------------------------------
-- Contraseñas y sesiones
-- (bcrypt con pgcrypto; acepta los hash $2y$ que generaba password_hash de PHP,
--  así las contraseñas de la versión 1 siguen funcionando después de migrar)
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.hash_password(p_plain text)
returns text language sql volatile as $$
  select extensions.crypt(p_plain, extensions.gen_salt('bf', 10))
$$;

create or replace function la_obra_v2.password_ok(p_plain text, p_hash text)
returns boolean language plpgsql stable as $$
declare h text := regexp_replace(coalesce(p_hash, ''), '^\$2[yb]\$', '$2a$');
begin
  if h = '' then return false; end if;
  return extensions.crypt(coalesce(p_plain, ''), h) = h;
exception when others then
  return false;
end $$;

create or replace function la_obra_v2.token_hash(p_token text)
returns text language sql immutable as $$
  select encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
$$;

-- user($admin): valida el token y devuelve al usuario de la sesión
create or replace function la_obra_v2.auth_user(
  p_token text,
  p_admin boolean default false,
  p_admin_message text default 'Se requiere rol administrador',
  p_require_password_changed boolean default false
) returns la_obra_v2.users language plpgsql as $$
declare
  u la_obra_v2.users;
  sid integer;
  exp timestamp;
begin
  if coalesce(btrim(p_token), '') = '' then
    perform la_obra_v2.fail(401, 'Token de autenticación requerido');
  end if;
  select s.user_id, s.expires_at into sid, exp
  from la_obra_v2.sessions s
  where s.token_hash = la_obra_v2.token_hash(p_token)
  limit 1;
  if sid is null then
    perform la_obra_v2.fail(401, 'Sesión inválida');
  end if;
  select * into u from la_obra_v2.users where id = sid;
  if u.id is null then
    perform la_obra_v2.fail(401, 'Sesión inválida');
  end if;
  if exp <= la_obra_v2.now_mx() then
    perform la_obra_v2.fail(401, 'La sesión ha expirado');
  end if;
  if u.status <> 'active' or u.role is null or u.role not in ('admin', 'employee') then
    perform la_obra_v2.fail(403, 'La cuenta no tiene acceso al sistema');
  end if;
  if p_require_password_changed and u.must_change_password then
    perform la_obra_v2.fail(403, 'Debes cambiar tu contraseña antes de continuar');
  end if;
  if p_admin and u.role <> 'admin' then
    perform la_obra_v2.fail(403, p_admin_message);
  end if;
  return u;
end $$;

-- ---------------------------------------------------------------------
-- Archivos (fotos de productos y tickets)
-- ---------------------------------------------------------------------

-- saveUploadedImage(): recibe un data URL (data:image/jpeg;base64,...)
create or replace function la_obra_v2.save_image(p_image jsonb, p_folder text, p_prefix text)
returns text language plpgsql as $$
declare
  raw text := la_obra_v2.jstr(p_image);
  m text[];
  bytes bytea;
  ext text;
  mime text;
  path text;
begin
  if raw = '' then perform la_obra_v2.fail(422, 'Selecciona una imagen'); end if;
  m := regexp_match(raw, '^data:([a-zA-Z0-9.+/-]+);base64,(.+)$');
  if m is null then perform la_obra_v2.fail(422, 'No se pudo recibir la imagen'); end if;
  begin
    bytes := decode(regexp_replace(m[2], '\s', '', 'g'), 'base64');
  exception when others then
    perform la_obra_v2.fail(422, 'No se pudo recibir la imagen');
  end;
  if length(bytes) <= 0 or length(bytes) > 3 * 1024 * 1024 then
    perform la_obra_v2.fail(413, 'La imagen debe pesar menos de 3 MB');
  end if;
  -- Validar el contenido real del archivo, no el tipo que dice el cliente
  if substring(bytes from 1 for 3) = '\xffd8ff'::bytea then
    mime := 'image/jpeg'; ext := 'jpg';
  elsif substring(bytes from 1 for 8) = '\x89504e470d0a1a0a'::bytea then
    mime := 'image/png'; ext := 'png';
  elsif substring(bytes from 1 for 4) = '\x52494646'::bytea and substring(bytes from 9 for 4) = '\x57454250'::bytea then
    mime := 'image/webp'; ext := 'webp';
  else
    perform la_obra_v2.fail(415, 'Formato no permitido. Usa JPG, PNG o WEBP');
  end if;
  path := 'uploads/' || p_folder || '/' || p_prefix || '_' || encode(extensions.gen_random_bytes(8), 'hex') || '.' || ext;
  insert into la_obra_v2.files(path, mime, data, size_bytes) values (path, mime, bytes, length(bytes));
  return path;
end $$;

-- deleteUpload(): solo borra dentro de uploads/<carpeta>/
create or replace function la_obra_v2.delete_upload(p_path text, p_folder text)
returns void language sql as $$
  delete from la_obra_v2.files
  where p_path is not null and path = p_path and path like 'uploads/' || p_folder || '/%'
$$;

-- ---------------------------------------------------------------------
-- Motor de costos (cost_engine.php)
-- Costo estándar a partir de la última compra válida de cada insumo.
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.input_cost(p_input_id integer)
returns numeric language sql stable as $$
  select pi.subtotal / pi.total_base_quantity
  from la_obra_v2.purchase_items pi
  join la_obra_v2.purchases p on p.id = pi.purchase_id
  where pi.input_id = p_input_id and pi.total_base_quantity > 0 and pi.subtotal >= 0
  order by p.purchase_date desc, p.id desc, pi.id desc
  limit 1
$$;

create or replace function la_obra_v2.preparation_cost(p_id integer)
returns jsonb language plpgsql stable as $$
declare
  p la_obra_v2.preparations;
  r record;
  unit numeric;
  total numeric := 0;
  missing jsonb := '[]'::jsonb;
  detail jsonb := '[]'::jsonb;
  n integer := 0;
begin
  select * into p from la_obra_v2.preparations where id = p_id;
  if p.id is null or p.yield_quantity <= 0 then return null; end if;
  for r in
    select pi.input_id, pi.quantity, pi.is_estimated, i.name, i.unit
    from la_obra_v2.preparation_inputs pi join la_obra_v2.inputs i on i.id = pi.input_id
    where pi.preparation_id = p_id order by pi.id
  loop
    n := n + 1;
    unit := la_obra_v2.input_cost(r.input_id);
    if unit is null then missing := missing || to_jsonb(r.name); else total := total + unit * r.quantity; end if;
    detail := detail || jsonb_build_array(jsonb_build_object(
      'name', r.name, 'quantity', r.quantity, 'unit', r.unit, 'unit_cost', unit,
      'cost', case when unit is null then null else unit * r.quantity end,
      'estimated', r.is_estimated));
  end loop;
  if n = 0 then return null; end if;
  return jsonb_build_object(
    'name', p.name,
    'yield_quantity', p.yield_quantity,
    'yield_unit', p.yield_unit,
    'batch_cost', case when jsonb_array_length(missing) > 0 then null else total end,
    'unit_cost',  case when jsonb_array_length(missing) > 0 then null else total / p.yield_quantity end,
    'missing', missing,
    'ingredients', detail);
end $$;

create or replace function la_obra_v2.product_cost(p_id integer, p_mode text default 'local')
returns jsonb language plpgsql stable as $$
declare
  p record;
  c record;
  x jsonb;
  cost numeric;
  nm text;
  unit text;
  total numeric := 0;
  missing jsonb := '[]'::jsonb;
  detail jsonb := '[]'::jsonb;
  n integer := 0;
  complete boolean;
  profit numeric;
begin
  select id, name, price into p from la_obra_v2.products where id = p_id;
  if p.id is null then return null; end if;
  for c in
    select pc.*, i.name as input_name, i.unit as input_unit, pr.name as preparation_name
    from la_obra_v2.product_components pc
    left join la_obra_v2.inputs i on i.id = pc.input_id
    left join la_obra_v2.preparations pr on pr.id = pc.preparation_id
    where pc.product_id = p_id and pc.delivery_mode in ('always', p_mode)
    order by pc.id
  loop
    n := n + 1;
    if c.input_id is not null then
      cost := la_obra_v2.input_cost(c.input_id);
      nm := c.input_name; unit := c.input_unit;
    else
      x := la_obra_v2.preparation_cost(c.preparation_id);
      cost := (x ->> 'unit_cost')::numeric;
      nm := c.preparation_name; unit := coalesce(x ->> 'yield_unit', '');
    end if;
    if cost is null then missing := missing || to_jsonb(nm); else total := total + c.quantity * cost; end if;
    detail := detail || jsonb_build_array(jsonb_build_object(
      'name', nm,
      'type', case when c.input_id is not null then 'input' else 'preparation' end,
      'quantity', c.quantity, 'unit', unit, 'unit_cost', cost,
      'cost', case when cost is null then null else cost * c.quantity end,
      'estimated', c.is_estimated, 'delivery_mode', c.delivery_mode));
  end loop;
  complete := jsonb_array_length(missing) = 0 and n > 0;
  profit := case when complete then p.price - total else null end;
  return jsonb_build_object(
    'product_id', p.id,
    'name', p.name,
    'delivery_mode', p_mode,
    'sale_price', p.price,
    'standard_cost', case when complete then round(total, 4) else null end,
    'gross_profit', case when profit is null then null else round(profit, 4) end,
    'gross_margin', case when profit is null or p.price = 0 then null else round(profit / p.price * 100, 2) end,
    'missing_prices', missing,
    'components', detail,
    'complete', complete);
end $$;

-- ---------------------------------------------------------------------
-- Inventario por movimientos (inventory.php)
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.inv_record(
  p_input_id integer, p_type text, p_qty numeric, p_unit_cost numeric,
  p_ref_type text, p_ref_id integer, p_note text, p_user_id integer
) returns void language plpgsql as $$
begin
  if abs(coalesce(p_qty, 0)) < 0.0005 then return; end if;
  insert into la_obra_v2.inventory_movements(input_id, movement_type, quantity, unit_cost, reference_type, reference_id, note, user_id)
  values (p_input_id, p_type, round(p_qty, 3), case when p_unit_cost is null then null else round(p_unit_cost, 6) end,
          p_ref_type, p_ref_id, p_note, p_user_id);
end $$;

create or replace function la_obra_v2.inv_stock(p_input_id integer)
returns numeric language sql stable as $$
  select coalesce(sum(quantity), 0) from la_obra_v2.inventory_movements where input_id = p_input_id
$$;

-- Rehacer las entradas de una compra (al crearla o editarla)
create or replace function la_obra_v2.inv_sync_purchase(p_purchase_id integer, p_user_id integer)
returns void language plpgsql as $$
declare i record;
begin
  delete from la_obra_v2.inventory_movements where reference_type = 'purchase' and reference_id = p_purchase_id;
  for i in select input_id, subtotal, total_base_quantity from la_obra_v2.purchase_items where purchase_id = p_purchase_id order by id loop
    if coalesce(i.total_base_quantity, 0) <= 0 then continue; end if;
    perform la_obra_v2.inv_record(i.input_id, 'purchase', i.total_base_quantity, i.subtotal / i.total_base_quantity,
                                  'purchase', p_purchase_id, null, p_user_id);
  end loop;
end $$;

-- Insumos que consume una preparación por cada unidad de su rendimiento
create or replace function la_obra_v2.inv_preparation_parts(p_preparation_id integer)
returns table(input_id integer, qty numeric) language sql stable as $$
  select pi.input_id, sum(pi.quantity / p.yield_quantity)
  from la_obra_v2.preparations p
  join la_obra_v2.preparation_inputs pi on pi.preparation_id = p.id
  where p.id = p_preparation_id and p.yield_quantity > 0
  group by pi.input_id
$$;

-- Insumos que consume una unidad de producto según su receta y modalidad
create or replace function la_obra_v2.inv_product_parts(p_product_id integer, p_mode text default 'local')
returns table(input_id integer, qty numeric) language sql stable as $$
  select s.input_id, sum(s.qty) from (
    select pc.input_id, pc.quantity as qty
    from la_obra_v2.product_components pc
    where pc.product_id = p_product_id and pc.delivery_mode in ('always', p_mode) and pc.input_id is not null
    union all
    select pp.input_id, pp.qty * pc.quantity
    from la_obra_v2.product_components pc
    cross join lateral la_obra_v2.inv_preparation_parts(pc.preparation_id) pp
    where pc.product_id = p_product_id and pc.delivery_mode in ('always', p_mode)
      and pc.input_id is null and pc.preparation_id is not null
  ) s group by s.input_id
$$;

-- Descontar del inventario lo que lleva un pedido (al entregarlo)
create or replace function la_obra_v2.inv_consume_order(p_order_id integer, p_user_id integer)
returns void language plpgsql as $$
declare
  o record;
  t record;
begin
  select id, delivery_mode into o from la_obra_v2.orders where id = p_order_id;
  if o.id is null then return; end if;
  -- No descontar dos veces el mismo pedido
  if exists (select 1 from la_obra_v2.inventory_movements
             where reference_type = 'order' and reference_id = p_order_id and movement_type = 'sale') then
    return;
  end if;
  for t in
    select pp.input_id, sum(pp.qty * oi.quantity) as qty
    from la_obra_v2.order_items oi
    cross join lateral la_obra_v2.inv_product_parts(oi.product_id, coalesce(nullif(o.delivery_mode, ''), 'local')) pp
    where oi.order_id = p_order_id
    group by pp.input_id
  loop
    perform la_obra_v2.inv_record(t.input_id, 'sale', -t.qty, la_obra_v2.input_cost(t.input_id), 'order', p_order_id, null, p_user_id);
  end loop;
end $$;

-- Devolver al inventario lo que se descontó de un pedido (venta cancelada)
create or replace function la_obra_v2.inv_reverse_order(p_order_id integer, p_user_id integer)
returns void language plpgsql as $$
declare m record;
begin
  if exists (select 1 from la_obra_v2.inventory_movements
             where reference_type = 'order' and reference_id = p_order_id and movement_type = 'sale_reversal') then
    return;
  end if;
  for m in select input_id, quantity, unit_cost from la_obra_v2.inventory_movements
           where reference_type = 'order' and reference_id = p_order_id and movement_type = 'sale' order by id loop
    perform la_obra_v2.inv_record(m.input_id, 'sale_reversal', -m.quantity, m.unit_cost, 'order', p_order_id, 'Venta cancelada', p_user_id);
  end loop;
end $$;

-- Listado de existencias con costo y alerta de mínimo
create or replace function la_obra_v2.inv_list()
returns jsonb language sql stable as $$
  with base as (
    select i.id, i.name, i.unit, i.status, i.package_type, i.package_quantity, i.package_content_unit, i.min_stock,
           round(coalesce(sum(m.quantity), 0), 3) as stock,
           max(case when m.movement_type = 'purchase' then m.created_at end) as last_purchase_at
    from la_obra_v2.inputs i
    left join la_obra_v2.inventory_movements m on m.input_id = i.id
    group by i.id
  ), costed as (
    select b.*, la_obra_v2.input_cost(b.id) as cost from base b
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'unit', unit, 'status', status,
      'package_type', package_type, 'package_quantity', package_quantity,
      'package_content_unit', package_content_unit, 'min_stock', min_stock,
      'stock', stock, 'last_purchase_at', last_purchase_at,
      'unit_cost', case when cost is null then null else round(cost, 4) end,
      'stock_value', case when cost is null then null else round(greatest(0, stock) * cost, 2) end,
      'level', case when stock <= 0 then 'out'
                    when min_stock is not null and stock <= min_stock then 'low'
                    else 'ok' end
    ) order by lower(name), name), '[]'::jsonb)
  from costed
$$;

-- ---------------------------------------------------------------------
-- Compras (service_helpers.php)
-- ---------------------------------------------------------------------

-- purchase($id): compra con sus renglones
create or replace function la_obra_v2.purchase_json(p_id integer, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare
  j jsonb;
begin
  if p_lock then
    perform 1 from la_obra_v2.purchases where id = p_id for update;
  end if;
  select to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name)
  into j
  from la_obra_v2.purchases p
  join la_obra_v2.users u on u.id = p.user_id
  join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
  where p.id = p_id;
  if j is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  j := j || jsonb_build_object('items', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', pi.id, 'input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit,
      'quantity', pi.quantity, 'unit_cost', pi.unit_cost, 'subtotal', pi.subtotal,
      'content_per_package', pi.content_per_package, 'content_unit', pi.content_unit,
      'total_base_quantity', pi.total_base_quantity) order by pi.id)
    from la_obra_v2.purchase_items pi join la_obra_v2.inputs i on i.id = pi.input_id
    where pi.purchase_id = p_id), '[]'::jsonb));
  return j;
end $$;

-- validItems(): devuelve {items: [...], total}
create or replace function la_obra_v2.valid_items(p_items jsonb)
returns jsonb language plpgsql as $$
declare
  it jsonb;
  inp record;
  iid integer;
  q numeric;
  content numeric;
  cost numeric;
  sub numeric;
  total numeric := 0;
  seen integer[] := '{}';
  clean jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    perform la_obra_v2.fail(422, 'Debes enviar al menos un insumo');
  end if;
  for it in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it) <> 'object' then perform la_obra_v2.fail(422, 'Insumo inválido'); end if;
    iid := la_obra_v2.pos_id(it -> 'input_id');
    if iid = any(seen) then perform la_obra_v2.fail(422, 'No repitas el mismo insumo en una compra'); end if;
    seen := seen || iid;
    select id, unit, package_quantity into inp from la_obra_v2.inputs where id = iid and status = 'active';
    if inp.id is null then perform la_obra_v2.fail(404, 'Insumo no encontrado o inactivo'); end if;
    if not la_obra_v2.is_num(it -> 'quantity') then perform la_obra_v2.fail(422, 'Cantidad inválida'); end if;
    q := la_obra_v2.num(it -> 'quantity');
    if q <= 0 or round(q, 3) <> q then perform la_obra_v2.fail(422, 'Cantidad inválida'); end if;
    -- Contenido de una presentación, en la unidad base del insumo; si no se manda, el del insumo
    if it -> 'content_per_package' is null or jsonb_typeof(it -> 'content_per_package') = 'null'
       or la_obra_v2.jstr(it -> 'content_per_package') = '' then
      content := inp.package_quantity;
    else
      if not la_obra_v2.is_num(it -> 'content_per_package') then
        perform la_obra_v2.fail(422, 'Contenido de presentación inválido');
      end if;
      content := la_obra_v2.num(it -> 'content_per_package');
    end if;
    if content <= 0 then perform la_obra_v2.fail(422, 'Contenido de presentación inválido'); end if;
    cost := la_obra_v2.money(it -> 'unit_cost', false);
    sub := round(q * cost, 2);
    total := total + sub;
    clean := clean || jsonb_build_array(jsonb_build_object(
      'input_id', iid, 'quantity', round(q, 3), 'unit_cost', cost, 'subtotal', sub,
      'content_per_package', round(content, 3), 'content_unit', inp.unit,
      'total_base_quantity', round(q * content, 3)));
  end loop;
  if total > 9999999999.99 then perform la_obra_v2.fail(422, 'Total excede el límite'); end if;
  return jsonb_build_object('items', clean, 'total', round(total, 2));
end $$;

-- validPurchase(): devuelve {purchase_date, supplier, payment_method_id, items, total}
create or replace function la_obra_v2.valid_purchase(d jsonb)
returns jsonb language plpgsql as $$
declare
  dt date;
  supplier text;
  pm integer;
  items jsonb;
begin
  dt := la_obra_v2.dateval(d -> 'purchase_date');
  if d -> 'supplier' is not null and jsonb_typeof(d -> 'supplier') <> 'null' then
    if jsonb_typeof(d -> 'supplier') <> 'string' or char_length(d ->> 'supplier') > 150 then
      perform la_obra_v2.fail(422, 'Proveedor inválido');
    end if;
    supplier := d ->> 'supplier';
  end if;
  pm := la_obra_v2.pos_id(d -> 'payment_method_id');
  if not exists (select 1 from la_obra_v2.payment_methods where id = pm and status = 'active') then
    perform la_obra_v2.fail(404, 'Método de pago inexistente o inactivo');
  end if;
  items := la_obra_v2.valid_items(d -> 'items');
  return jsonb_build_object('purchase_date', dt, 'supplier', supplier, 'payment_method_id', pm,
                            'items', items -> 'items', 'total', items -> 'total');
end $$;

create or replace function la_obra_v2.insert_items(p_purchase_id integer, p_items jsonb)
returns void language sql as $$
  insert into la_obra_v2.purchase_items(purchase_id, input_id, quantity, unit_cost, subtotal, content_per_package, content_unit, total_base_quantity)
  select p_purchase_id, (i ->> 'input_id')::integer, (i ->> 'quantity')::numeric, (i ->> 'unit_cost')::numeric,
         (i ->> 'subtotal')::numeric, (i ->> 'content_per_package')::numeric, i ->> 'content_unit',
         (i ->> 'total_base_quantity')::numeric
  from jsonb_array_elements(p_items) with ordinality e(i, o) order by o
$$;

create or replace function la_obra_v2.valid_buyer(v jsonb)
returns text language plpgsql immutable as $$
declare t text;
begin
  if v is null or jsonb_typeof(v) = 'null' then return null; end if;
  t := la_obra_v2.jtrim(v);
  if t = '' then return null; end if;
  if char_length(t) > 100 then perform la_obra_v2.fail(422, 'Nombre del comprador demasiado largo'); end if;
  return t;
end $$;

-- Recordar en el insumo la presentación con la que se compró
create or replace function la_obra_v2.remember_presentations(p_items jsonb)
returns void language plpgsql as $$
declare
  i jsonb;
  t text;
begin
  if jsonb_typeof(p_items) is distinct from 'array' then return; end if;
  for i in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(i) <> 'object' then continue; end if;
    t := la_obra_v2.jtrim(i -> 'package_type');
    if t = '' or char_length(t) > 40 or not la_obra_v2.is_int(i -> 'input_id') or la_obra_v2.int_of(i -> 'input_id') <= 0
       or not la_obra_v2.is_num(i -> 'content_per_package') or la_obra_v2.num(i -> 'content_per_package') <= 0 then
      continue;
    end if;
    update la_obra_v2.inputs
    set package_type = t, package_quantity = round(la_obra_v2.num(i -> 'content_per_package'), 3)
    where id = la_obra_v2.int_of(i -> 'input_id');
  end loop;
end $$;

-- validInput(): devuelve {name, unit, package_type, package_quantity, min_stock}
create or replace function la_obra_v2.valid_input(d jsonb)
returns jsonb language plpgsql immutable as $$
declare
  nm text := la_obra_v2.jtrim(d -> 'name');
  unit text := la_obra_v2.jtrim(d -> 'unit');
  pt text := la_obra_v2.jtrim(d -> 'package_type');
  qty jsonb := coalesce(d -> 'package_quantity', '1'::jsonb);
  mn jsonb := d -> 'min_stock';
begin
  if nm = '' or char_length(nm) > 100 then perform la_obra_v2.fail(422, 'Escribe el nombre del insumo'); end if;
  if unit = '' or char_length(unit) > 20 then perform la_obra_v2.fail(422, 'Indica la unidad de medida'); end if;
  if pt = '' then pt := unit; end if;
  if char_length(pt) > 40 then perform la_obra_v2.fail(422, 'Presentación inválida'); end if;
  if jsonb_typeof(qty) = 'null' then qty := '1'::jsonb; end if;
  if not la_obra_v2.is_num(qty) or la_obra_v2.num(qty) <= 0 or la_obra_v2.num(qty) > 999999999 then
    perform la_obra_v2.fail(422, 'Indica cuántas unidades trae cada presentación');
  end if;
  if mn is not null and jsonb_typeof(mn) = 'string' and mn #>> '{}' = '' then mn := null; end if;
  if mn is not null and jsonb_typeof(mn) = 'null' then mn := null; end if;
  if mn is not null and (not la_obra_v2.is_num(mn) or la_obra_v2.num(mn) < 0) then
    perform la_obra_v2.fail(422, 'Existencia mínima inválida');
  end if;
  return jsonb_build_object('name', nm, 'unit', unit, 'package_type', pt,
                            'package_quantity', round(la_obra_v2.num(qty), 3),
                            'min_stock', case when mn is null then null else la_obra_v2.num(mn) end);
end $$;

-- ---------------------------------------------------------------------
-- Gastos (service_helpers.php)
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.expense_json(p_id integer, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare j jsonb;
begin
  if p_lock then perform 1 from la_obra_v2.expenses where id = p_id for update; end if;
  select to_jsonb(e) || jsonb_build_object('user_name', u.name) into j
  from la_obra_v2.expenses e join la_obra_v2.users u on u.id = e.user_id where e.id = p_id;
  if j is null then perform la_obra_v2.fail(404, 'Gasto no encontrado'); end if;
  return j;
end $$;

create or replace function la_obra_v2.expense_access(e jsonb, u la_obra_v2.users)
returns void language plpgsql as $$
begin
  if u.role <> 'admin' and (e ->> 'user_id')::integer <> u.id then
    perform la_obra_v2.fail(403, 'No puedes consultar o modificar gastos de otra persona');
  end if;
end $$;

create or replace function la_obra_v2.expense_editable(e jsonb)
returns void language plpgsql as $$
begin
  if e ->> 'status' <> 'active' then perform la_obra_v2.fail(409, 'El gasto ya está cancelado'); end if;
end $$;

-- Rango de fechas de los reportes (from/to, por defecto el mes actual, máximo 366 días)
create or replace function la_obra_v2.report_range(q jsonb)
returns table(d_from date, d_to date) language plpgsql stable as $$
declare
  f text := coalesce(q ->> 'from', to_char(date_trunc('month', la_obra_v2.today_mx()), 'YYYY-MM-DD'));
  t text := coalesce(q ->> 'to', to_char(la_obra_v2.today_mx(), 'YYYY-MM-DD'));
begin
  if not la_obra_v2.is_date(f) or not la_obra_v2.is_date(t) then
    perform la_obra_v2.fail(422, 'Utiliza fechas válidas con formato AAAA-MM-DD');
  end if;
  if f::date > t::date then perform la_obra_v2.fail(422, 'La fecha inicial no puede ser posterior a la final'); end if;
  if t::date - f::date > 365 then perform la_obra_v2.fail(422, 'Selecciona un rango de hasta 366 días'); end if;
  d_from := f::date; d_to := t::date;
  return next;
end $$;
