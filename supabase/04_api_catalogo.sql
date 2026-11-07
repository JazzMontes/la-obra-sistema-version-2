-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 04 · API: categorías, métodos de pago, productos, insumos, recetas y preparaciones
-- =====================================================================

-- ---------------------------------------------------------------------
-- CATEGORÍAS
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.ep_categories__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  return jsonb_build_object('success', true, 'categories', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status) order by lower(name), name)
    from la_obra_v2.categories), '[]'::jsonb));
end $$;

create or replace function la_obra_v2.ep_categories__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  nm text := la_obra_v2.jtrim(b -> 'name');
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  if nm = '' then perform la_obra_v2.fail(422, 'El nombre es obligatorio'); end if;
  if char_length(nm) > 100 then perform la_obra_v2.fail(422, 'El nombre es demasiado largo'); end if;
  if exists (select 1 from la_obra_v2.categories where lower(name) = lower(nm)) then
    perform la_obra_v2.fail(409, 'La categoría ya existe');
  end if;
  insert into la_obra_v2.categories(name, status) values (nm, 'active') returning id into new_id;
  return la_obra_v2.ok('Categoría registrada correctamente',
    jsonb_build_object('category', jsonb_build_object('id', new_id, 'name', nm, 'status', 'active')));
end $$;

create or replace function la_obra_v2.ep_categories__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  nm text := la_obra_v2.jtrim(b -> 'name');
  cid integer;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.int_of(b -> 'id') <= 0 or nm = '' then
    perform la_obra_v2.fail(422, 'Id y nombre válidos son obligatorios');
  end if;
  cid := la_obra_v2.int_of(b -> 'id');
  if not exists (select 1 from la_obra_v2.categories where id = cid) then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if exists (select 1 from la_obra_v2.categories where lower(name) = lower(nm) and id <> cid) then
    perform la_obra_v2.fail(409, 'Ya existe otra categoría con ese nombre');
  end if;
  update la_obra_v2.categories set name = nm where id = cid;
  return la_obra_v2.ok('Categoría actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__activate(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  cid integer;
  st text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true);
  cid := la_obra_v2.pos_id(b -> 'id');
  select status into st from la_obra_v2.categories where id = cid;
  if st is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if st = 'active' then perform la_obra_v2.fail(422, 'La categoría ya está activa'); end if;
  update la_obra_v2.categories set status = 'active' where id = cid;
  return la_obra_v2.ok('Categoría activada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__deactivate(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  cid integer;
  st text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  cid := la_obra_v2.pos_id(b -> 'id', 'El id no es válido');
  select status into st from la_obra_v2.categories where id = cid;
  if st is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if st <> 'active' then perform la_obra_v2.fail(422, 'La categoría ya está inactiva'); end if;
  update la_obra_v2.categories set status = 'inactive' where id = cid;
  return la_obra_v2.ok('Categoría desactivada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__delete(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare cid integer;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  cid := la_obra_v2.pos_id(b -> 'id');
  if not exists (select 1 from la_obra_v2.categories where id = cid) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  begin
    delete from la_obra_v2.categories where id = cid;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque el registro está relacionado con otros datos. Puedes desactivarlo para conservar el historial.');
  end;
  return la_obra_v2.ok('Registro eliminado correctamente');
end $$;

-- ---------------------------------------------------------------------
-- MÉTODOS DE PAGO
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.ep_payment_methods__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  return jsonb_build_object('success', true, 'payment_methods', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status) order by lower(name), name)
    from la_obra_v2.payment_methods), '[]'::jsonb));
end $$;

create or replace function la_obra_v2.ep_payment_methods__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  nm text := la_obra_v2.jtrim(b -> 'name');
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  if nm = '' then perform la_obra_v2.fail(422, 'El nombre es obligatorio'); end if;
  if char_length(nm) > 60 then perform la_obra_v2.fail(422, 'El nombre es demasiado largo'); end if;
  if exists (select 1 from la_obra_v2.payment_methods where lower(name) = lower(nm)) then
    perform la_obra_v2.fail(409, 'El método de pago ya existe');
  end if;
  insert into la_obra_v2.payment_methods(name, status) values (nm, 'active') returning id into new_id;
  return la_obra_v2.ok('Método de pago registrado correctamente',
    jsonb_build_object('payment_method', jsonb_build_object('id', new_id, 'name', nm, 'status', 'active')));
end $$;

create or replace function la_obra_v2.ep_payment_methods__status(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  st text := la_obra_v2.jstr(b -> 'status');
  pid integer;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.int_of(b -> 'id') <= 0 or st not in ('active', 'inactive') then
    perform la_obra_v2.fail(422, 'Datos inválidos');
  end if;
  pid := la_obra_v2.int_of(b -> 'id');
  if not exists (select 1 from la_obra_v2.payment_methods where id = pid) then
    perform la_obra_v2.fail(404, 'Método de pago no encontrado');
  end if;
  update la_obra_v2.payment_methods set status = st where id = pid;
  return la_obra_v2.ok('Estado del método de pago actualizado correctamente');
end $$;

create or replace function la_obra_v2.ep_payment_methods__delete(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare pid integer;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  if not exists (select 1 from la_obra_v2.payment_methods where id = pid) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  begin
    delete from la_obra_v2.payment_methods where id = pid;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque el registro está relacionado con otros datos. Puedes desactivarlo para conservar el historial.');
  end;
  return la_obra_v2.ok('Registro eliminado correctamente');
end $$;

-- ---------------------------------------------------------------------
-- PRODUCTOS
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.product_json(p_id integer)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description,
    'category', jsonb_build_object('id', c.id, 'name', c.name),
    'type', p.type, 'price', p.price, 'is_available', p.is_available, 'status', p.status, 'image_path', p.image_path)
  from la_obra_v2.products p join la_obra_v2.categories c on c.id = p.category_id
  where p.id = p_id
$$;

create or replace function la_obra_v2.ep_products__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  return jsonb_build_object('success', true, 'products', coalesce((
    select jsonb_agg(la_obra_v2.product_json(id) order by id) from la_obra_v2.products), '[]'::jsonb));
end $$;

create or replace function la_obra_v2.ep_products__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  j jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  pid := la_obra_v2.pos_id(q -> 'id', 'El id del producto no es válido');
  j := la_obra_v2.product_json(pid);
  if j is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return jsonb_build_object('success', true, 'product', j);
end $$;

create or replace function la_obra_v2.ep_products__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  nm text := la_obra_v2.jtrim(b -> 'name');
  ds text := la_obra_v2.jtrim(b -> 'description');
  tp text := la_obra_v2.jtrim(b -> 'type');
  cid integer;
  price numeric;
  cst text;
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  if nm = '' or ds = '' or not la_obra_v2.is_int(b -> 'category_id') or la_obra_v2.int_of(b -> 'category_id') <= 0
     or tp not in ('prepared', 'resale') or not la_obra_v2.is_num(b -> 'price') or la_obra_v2.num(b -> 'price') < 0 then
    perform la_obra_v2.fail(422, 'Los datos del producto no son válidos');
  end if;
  if char_length(nm) > 100 or char_length(ds) > 255 then perform la_obra_v2.fail(422, 'Nombre o descripción demasiado largos'); end if;
  cid := la_obra_v2.int_of(b -> 'category_id');
  price := round(la_obra_v2.num(b -> 'price'), 2);
  select status into cst from la_obra_v2.categories where id = cid;
  if cst is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if cst <> 'active' then perform la_obra_v2.fail(422, 'La categoría está inactiva'); end if;
  insert into la_obra_v2.products(name, description, category_id, type, price, is_available, status)
  values (nm, ds, cid, tp, price, true, 'active') returning id into new_id;
  return la_obra_v2.ok('Producto registrado correctamente', jsonb_build_object('product', jsonb_build_object(
    'id', new_id, 'name', nm, 'description', ds, 'category_id', cid, 'type', tp, 'price', price,
    'is_available', true, 'status', 'active')));
end $$;

-- FILTER_VALIDATE_BOOLEAN con FILTER_NULL_ON_FAILURE
create or replace function la_obra_v2.bool_of(v jsonb)
returns boolean language sql immutable as $$
  select case jsonb_typeof(v)
    when 'boolean' then (v #>> '{}')::boolean
    when 'number' then case (v #>> '{}') when '1' then true when '0' then false else null end
    when 'string' then case lower(btrim(v #>> '{}'))
      when '1' then true when 'true' then true when 'on' then true when 'yes' then true
      when '0' then false when 'false' then false when 'off' then false when 'no' then false when '' then false
      else null end
    else null
  end
$$;

create or replace function la_obra_v2.ep_products__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  p la_obra_v2.products;
  v text;
  cid integer;
  cst text;
  av boolean;
  changed boolean := false;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  if jsonb_typeof(b) <> 'object' then perform la_obra_v2.fail(422, 'Datos inválidos'); end if;
  pid := la_obra_v2.pos_id(b -> 'id', 'El id no es válido');
  select * into p from la_obra_v2.products where id = pid;
  if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if b ? 'name' then
    v := la_obra_v2.jtrim(b -> 'name');
    if v = '' or char_length(v) > 100 then perform la_obra_v2.fail(422, 'Nombre inválido'); end if;
    p.name := v; changed := true;
  end if;
  if b ? 'description' then
    v := la_obra_v2.jtrim(b -> 'description');
    if v = '' or char_length(v) > 255 then perform la_obra_v2.fail(422, 'Descripción inválida'); end if;
    p.description := v; changed := true;
  end if;
  if b ? 'category_id' then
    if not la_obra_v2.is_int(b -> 'category_id') or la_obra_v2.int_of(b -> 'category_id') <= 0 then
      perform la_obra_v2.fail(422, 'Categoría inválida');
    end if;
    cid := la_obra_v2.int_of(b -> 'category_id');
    select status into cst from la_obra_v2.categories where id = cid;
    if cst is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
    if cst <> 'active' then perform la_obra_v2.fail(422, 'La categoría está inactiva'); end if;
    p.category_id := cid; changed := true;
  end if;
  if b ? 'type' then
    v := la_obra_v2.jtrim(b -> 'type');
    if v not in ('prepared', 'resale') then perform la_obra_v2.fail(422, 'Tipo inválido'); end if;
    p.type := v; changed := true;
  end if;
  if b ? 'price' then
    if not la_obra_v2.is_num(b -> 'price') or la_obra_v2.num(b -> 'price') < 0 then perform la_obra_v2.fail(422, 'Precio inválido'); end if;
    p.price := round(la_obra_v2.num(b -> 'price'), 2); changed := true;
  end if;
  if b ? 'is_available' then
    av := la_obra_v2.bool_of(b -> 'is_available');
    if av is null then perform la_obra_v2.fail(422, 'Disponibilidad inválida'); end if;
    p.is_available := av; changed := true;
  end if;
  if not changed then perform la_obra_v2.fail(422, 'No se enviaron campos para actualizar'); end if;
  update la_obra_v2.products
  set name = p.name, description = p.description, category_id = p.category_id, type = p.type,
      price = p.price, is_available = p.is_available
  where id = pid;
  return la_obra_v2.ok('Producto actualizado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__activate(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  st text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  pid := la_obra_v2.pos_id(b -> 'id', 'El id no es válido');
  select status into st from la_obra_v2.products where id = pid;
  if st is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if st = 'active' then perform la_obra_v2.fail(422, 'El producto ya está activo'); end if;
  update la_obra_v2.products set status = 'active', is_available = true where id = pid;
  return la_obra_v2.ok('Producto activado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__deactivate(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  st text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  pid := la_obra_v2.pos_id(b -> 'id', 'El id no es válido');
  select status into st from la_obra_v2.products where id = pid;
  if st is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if st <> 'active' then perform la_obra_v2.fail(422, 'El producto ya está inactivo'); end if;
  update la_obra_v2.products set status = 'inactive', is_available = false where id = pid;
  return la_obra_v2.ok('Producto desactivado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__delete(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  img text;
  found_id integer;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  select id, image_path into found_id, img from la_obra_v2.products where id = pid;
  if found_id is null then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  begin
    delete from la_obra_v2.products where id = pid;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque el registro está relacionado con otros datos. Puedes desactivarlo para conservar el historial.');
  end;
  perform la_obra_v2.delete_upload(img, 'products');
  return la_obra_v2.ok('Registro eliminado correctamente');
end $$;

-- products/upload-image.php — antes multipart; ahora {id, image: "data:image/jpeg;base64,..."}
create or replace function la_obra_v2.ep_products__upload_image(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  old text;
  found_id integer;
  path text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  select id, image_path into found_id, old from la_obra_v2.products where id = pid;
  if found_id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  path := la_obra_v2.save_image(b -> 'image', 'products', pid::text);
  update la_obra_v2.products set image_path = path where id = pid;
  -- Borrar la foto anterior para no acumular archivos
  perform la_obra_v2.delete_upload(old, 'products');
  return la_obra_v2.ok('Foto guardada correctamente', jsonb_build_object('image_path', path));
end $$;

create or replace function la_obra_v2.ep_products__delete_image(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  old text;
  found_id integer;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  select id, image_path into found_id, old from la_obra_v2.products where id = pid;
  if found_id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if coalesce(old, '') = '' then return la_obra_v2.ok('El producto no tenía foto'); end if;
  update la_obra_v2.products set image_path = null where id = pid;
  perform la_obra_v2.delete_upload(old, 'products');
  return la_obra_v2.ok('Foto eliminada correctamente');
end $$;

-- products/components.php — composición estándar del producto
create or replace function la_obra_v2.ep_products__components(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare pid integer;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  pid := la_obra_v2.pos_id(q -> 'product_id');
  if not exists (select 1 from la_obra_v2.products where id = pid) then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok('Composición consultada', jsonb_build_object('components', coalesce((
    select jsonb_agg(to_jsonb(pc) order by pc.id) from la_obra_v2.product_components pc where pc.product_id = pid), '[]'::jsonb)));
end $$;

-- products/save-components.php — sustituye la composición del producto
create or replace function la_obra_v2.ep_products__save_components(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  items jsonb := b -> 'components';
  i jsonb;
  has_input boolean;
  has_prep boolean;
  sid integer;
begin
  perform la_obra_v2.method(m, 'PUT');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'product_id');
  if not exists (select 1 from la_obra_v2.products where id = pid) then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if jsonb_typeof(items) is distinct from 'array' then perform la_obra_v2.fail(422, 'Componentes inválidos'); end if;
  for i in select value from jsonb_array_elements(items) loop
    has_input := la_obra_v2.truthy(i -> 'input_id');
    has_prep := la_obra_v2.truthy(i -> 'preparation_id');
    if has_input = has_prep or not la_obra_v2.is_num(i -> 'quantity') or la_obra_v2.num(i -> 'quantity') <= 0
       or coalesce(i ->> 'delivery_mode', 'always') not in ('always', 'local', 'takeaway') then
      perform la_obra_v2.fail(422, 'Componente inválido');
    end if;
    if has_input then
      sid := la_obra_v2.pos_id(i -> 'input_id');
      if not exists (select 1 from la_obra_v2.inputs where id = sid) then perform la_obra_v2.fail(422, 'Componente inexistente'); end if;
    else
      sid := la_obra_v2.pos_id(i -> 'preparation_id');
      if not exists (select 1 from la_obra_v2.preparations where id = sid) then perform la_obra_v2.fail(422, 'Componente inexistente'); end if;
    end if;
  end loop;
  delete from la_obra_v2.product_components where product_id = pid;
  insert into la_obra_v2.product_components(product_id, input_id, preparation_id, quantity, is_estimated, delivery_mode)
  select pid,
         case when la_obra_v2.truthy(c -> 'input_id') then la_obra_v2.int_of(c -> 'input_id') end,
         case when la_obra_v2.truthy(c -> 'preparation_id') then la_obra_v2.int_of(c -> 'preparation_id') end,
         round(la_obra_v2.num(c -> 'quantity'), 3),
         la_obra_v2.truthy(c -> 'is_estimated'),
         coalesce(c ->> 'delivery_mode', 'always')
  from jsonb_array_elements(items) with ordinality e(c, o) order by o;
  return la_obra_v2.ok('Composición guardada');
end $$;

-- ---------------------------------------------------------------------
-- INSUMOS
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.ep_inputs__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  return jsonb_build_object('success', true, 'inputs', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'unit', unit, 'status', status,
      'package_type', package_type, 'package_quantity', package_quantity,
      'package_content_unit', package_content_unit, 'min_stock', min_stock) order by lower(name), name)
    from la_obra_v2.inputs), '[]'::jsonb));
end $$;

create or replace function la_obra_v2.ep_inputs__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  iid integer;
  j jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  iid := la_obra_v2.pos_id(q -> 'id', 'El id no es válido');
  select jsonb_build_object('id', id, 'name', name, 'unit', unit, 'status', status, 'package_type', package_type,
                            'package_quantity', package_quantity, 'package_content_unit', package_content_unit)
  into j from la_obra_v2.inputs where id = iid;
  if j is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return jsonb_build_object('success', true, 'input', j);
end $$;

create or replace function la_obra_v2.ep_inputs__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  v jsonb;
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true);
  v := la_obra_v2.valid_input(b);
  if exists (select 1 from la_obra_v2.inputs where lower(name) = lower(v ->> 'name')) then
    perform la_obra_v2.fail(409, 'Ya existe un insumo con ese nombre');
  end if;
  insert into la_obra_v2.inputs(name, unit, package_type, package_quantity, package_content_unit, min_stock, status)
  values (v ->> 'name', v ->> 'unit', v ->> 'package_type', (v ->> 'package_quantity')::numeric, v ->> 'unit',
          (v ->> 'min_stock')::numeric, 'active')
  returning id into new_id;
  return la_obra_v2.ok('Insumo registrado correctamente', jsonb_build_object('input', jsonb_build_object(
    'id', new_id, 'name', v -> 'name', 'unit', v -> 'unit', 'package_type', v -> 'package_type',
    'package_quantity', v -> 'package_quantity', 'min_stock', v -> 'min_stock', 'status', 'active')));
end $$;

create or replace function la_obra_v2.ep_inputs__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  iid integer;
  old la_obra_v2.inputs;
  merged jsonb;
  v jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true);
  iid := la_obra_v2.pos_id(b -> 'id');
  select * into old from la_obra_v2.inputs where id = iid;
  if old.id is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  merged := jsonb_build_object(
    'name', coalesce(nullif(b -> 'name', 'null'::jsonb), to_jsonb(old.name)),
    'unit', coalesce(nullif(b -> 'unit', 'null'::jsonb), to_jsonb(old.unit)),
    'package_type', coalesce(nullif(b -> 'package_type', 'null'::jsonb), to_jsonb(old.package_type)),
    'package_quantity', coalesce(nullif(b -> 'package_quantity', 'null'::jsonb), to_jsonb(old.package_quantity)),
    'min_stock', case when b ? 'min_stock' then b -> 'min_stock' else to_jsonb(old.min_stock) end);
  v := la_obra_v2.valid_input(merged);
  if exists (select 1 from la_obra_v2.inputs where lower(name) = lower(v ->> 'name') and id <> iid) then
    perform la_obra_v2.fail(409, 'Ya existe un insumo con ese nombre');
  end if;
  update la_obra_v2.inputs
  set name = v ->> 'name', unit = v ->> 'unit', package_type = v ->> 'package_type',
      package_quantity = (v ->> 'package_quantity')::numeric, package_content_unit = v ->> 'unit',
      min_stock = (v ->> 'min_stock')::numeric
  where id = iid;
  return la_obra_v2.ok('Insumo actualizado correctamente');
end $$;

create or replace function la_obra_v2.ep_inputs__activate(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare iid integer;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true);
  iid := la_obra_v2.pos_id(b -> 'id');
  if not exists (select 1 from la_obra_v2.inputs where id = iid) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  update la_obra_v2.inputs set status = 'active' where id = iid;
  return la_obra_v2.ok('Insumo activado correctamente');
end $$;

create or replace function la_obra_v2.ep_inputs__deactivate(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  iid integer;
  st text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  iid := la_obra_v2.pos_id(b -> 'id', 'El id no es válido');
  select status into st from la_obra_v2.inputs where id = iid;
  if st is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  if st <> 'active' then perform la_obra_v2.fail(422, 'El insumo ya está inactivo'); end if;
  update la_obra_v2.inputs set status = 'inactive' where id = iid;
  return la_obra_v2.ok('Insumo desactivado correctamente');
end $$;

create or replace function la_obra_v2.ep_inputs__delete(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare iid integer;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  iid := la_obra_v2.pos_id(b -> 'id');
  if not exists (select 1 from la_obra_v2.inputs where id = iid) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  if exists (select 1 from la_obra_v2.inventory_movements where input_id = iid)
     or exists (select 1 from la_obra_v2.purchase_items where input_id = iid)
     or exists (select 1 from la_obra_v2.product_components where input_id = iid)
     or exists (select 1 from la_obra_v2.preparation_inputs where input_id = iid) then
    perform la_obra_v2.fail(409, 'Este insumo ya tiene compras, recetas o movimientos de inventario. Desactívalo para conservar el historial.');
  end if;
  begin
    delete from la_obra_v2.inputs where id = iid;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque el registro está relacionado con otros datos. Puedes desactivarlo para conservar el historial.');
  end;
  return la_obra_v2.ok('Registro eliminado correctamente');
end $$;

-- inputs/dependencies.php — relaciones de un registro antes de eliminarlo
create or replace function la_obra_v2.ep_inputs__dependencies(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  tp text := coalesce(la_obra_v2.qp(q, 'type'), 'input');
  rid integer;
  rel jsonb := '[]'::jsonb;
  ok boolean;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  rid := la_obra_v2.pos_id(q -> 'id');
  if tp not in ('input','product','preparation','waste','recipe','component','preparation_input','purchase_item','order_item') then
    perform la_obra_v2.fail(422, 'Tipo de registro inválido');
  end if;
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)',
    case tp when 'input' then 'inputs' when 'product' then 'products' when 'preparation' then 'preparations'
            when 'waste' then 'waste_records' when 'recipe' then 'recipes' when 'component' then 'product_components'
            when 'preparation_input' then 'preparation_inputs' when 'purchase_item' then 'purchase_items'
            else 'order_items' end) into ok using rid;
  if not ok then perform la_obra_v2.fail(404, 'El registro ya no existe'); end if;

  if tp = 'input' then
    select coalesce(jsonb_agg(x order by o), '[]'::jsonb) into rel from (
      select 1 as o, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Producto que utiliza el insumo','deletable',true) x
        from la_obra_v2.recipes r join la_obra_v2.products p on p.id = r.product_id where r.input_id = rid
      union all
      select 2, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Componente de producto','deletable',true)
        from la_obra_v2.product_components pc join la_obra_v2.products p on p.id = pc.product_id where pc.input_id = rid
      union all
      select 3, jsonb_build_object('type','preparation','id',pr.id,'label',pr.name,'detail','Preparación que utiliza el insumo','deletable',true)
        from la_obra_v2.preparation_inputs pi join la_obra_v2.preparations pr on pr.id = pi.preparation_id where pi.input_id = rid
      union all
      select 4, jsonb_build_object('type','waste','id',w.id,'label','Merma del ' || w.waste_date,'detail','Registro de merma','deletable',true)
        from la_obra_v2.waste_records w where w.input_id = rid
      union all
      select 5, jsonb_build_object('type','purchase_item','id',pi.id,'label','Compra del ' || p.purchase_date,'detail','Movimiento histórico de compra','deletable',false)
        from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id where pi.input_id = rid
    ) s;
  elsif tp = 'product' then
    select coalesce(jsonb_agg(x order by o), '[]'::jsonb) into rel from (
      select 1 as o, jsonb_build_object('type','recipe','id',id,'label','Ingrediente de receta #' || id,'detail','Relación con insumo','deletable',true) x
        from la_obra_v2.recipes where product_id = rid
      union all
      select 2, jsonb_build_object('type','component','id',id,'label','Componente #' || id,'detail','Composición del producto','deletable',true)
        from la_obra_v2.product_components where product_id = rid
      union all
      select 3, jsonb_build_object('type','waste','id',id,'label','Merma del ' || waste_date,'detail','Registro de merma','deletable',true)
        from la_obra_v2.waste_records where product_id = rid
      union all
      select 4, jsonb_build_object('type','order_item','id',oi.id,'label','Venta #' || o.id,'detail','Historial de venta protegido','deletable',false)
        from la_obra_v2.order_items oi join la_obra_v2.orders o on o.id = oi.order_id where oi.product_id = rid
    ) s;
  elsif tp = 'preparation' then
    select coalesce(jsonb_agg(x order by o), '[]'::jsonb) into rel from (
      select 1 as o, jsonb_build_object('type','preparation_input','id',id,'label','Ingrediente de preparación #' || id,'detail','Componente de preparación','deletable',true) x
        from la_obra_v2.preparation_inputs where preparation_id = rid
      union all
      select 2, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Producto que utiliza la preparación','deletable',true)
        from la_obra_v2.product_components pc join la_obra_v2.products p on p.id = pc.product_id where pc.preparation_id = rid
      union all
      select 3, jsonb_build_object('type','waste','id',id,'label','Merma del ' || waste_date,'detail','Registro de merma','deletable',true)
        from la_obra_v2.waste_records where preparation_id = rid
    ) s;
  end if;

  -- Evita mostrar el mismo producto varias veces (se queda el último, como en PHP)
  select coalesce(jsonb_agg(x order by first_pos), '[]'::jsonb) into rel from (
    select distinct on (x ->> 'type', x ->> 'id') x, min(pos) over (partition by x ->> 'type', x ->> 'id') as first_pos
    from jsonb_array_elements(rel) with ordinality e(x, pos)
    order by x ->> 'type', x ->> 'id', pos desc
  ) u;

  return la_obra_v2.ok('Relaciones consultadas', jsonb_build_object('type', tp, 'id', rid, 'relations', rel));
end $$;

-- inputs/delete-related.php — elimina solo el registro confirmado
create or replace function la_obra_v2.ep_inputs__delete_related(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  tp text := la_obra_v2.jstr(b -> 'type');
  rid integer;
  tbl text;
  ok boolean;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  rid := la_obra_v2.pos_id(b -> 'id');
  tbl := case tp when 'input' then 'inputs' when 'product' then 'products' when 'preparation' then 'preparations'
                 when 'waste' then 'waste_records' when 'recipe' then 'recipes' when 'component' then 'product_components'
                 when 'preparation_input' then 'preparation_inputs' else null end;
  if tbl is null then perform la_obra_v2.fail(422, 'Tipo de registro no permitido'); end if;
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)', tbl) into ok using rid;
  if not ok then perform la_obra_v2.fail(404, 'El registro ya no existe'); end if;
  begin
    execute format('delete from la_obra_v2.%I where id = $1', tbl) using rid;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'Este registro todavía tiene relaciones. Revisa la lista y elimínalas individualmente.');
  end;
  return la_obra_v2.ok('Registro eliminado correctamente', jsonb_build_object('type', tp, 'id', rid));
end $$;

-- ---------------------------------------------------------------------
-- RECETAS (versión anterior; las pantallas actuales usan product_components)
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.recipe_check(b jsonb, p_must_exist boolean)
returns integer language plpgsql as $$
declare
  pid integer;
  tp text;
  it jsonb;
  st text;
begin
  if not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.int_of(b -> 'product_id') <= 0
     or jsonb_typeof(b -> 'inputs') is distinct from 'array' or jsonb_array_length(b -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Producto e insumos válidos son obligatorios');
  end if;
  pid := la_obra_v2.int_of(b -> 'product_id');
  select type into tp from la_obra_v2.products where id = pid;
  if tp is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if tp <> 'prepared' then perform la_obra_v2.fail(422, 'Solo los productos preparados pueden tener receta'); end if;
  if p_must_exist and not exists (select 1 from la_obra_v2.recipes where product_id = pid) then
    perform la_obra_v2.fail(404, 'Receta no encontrada');
  end if;
  if not p_must_exist and exists (select 1 from la_obra_v2.recipes where product_id = pid) then
    perform la_obra_v2.fail(409, 'El producto ya tiene una receta registrada');
  end if;
  for it in select value from jsonb_array_elements(b -> 'inputs') loop
    if not la_obra_v2.is_int(it -> 'input_id') or la_obra_v2.int_of(it -> 'input_id') <= 0
       or not la_obra_v2.is_num(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 then
      perform la_obra_v2.fail(422, 'Datos de insumo inválidos');
    end if;
    select status into st from la_obra_v2.inputs where id = la_obra_v2.int_of(it -> 'input_id');
    if st is null then perform la_obra_v2.fail(404, 'Insumo no encontrado: ' || la_obra_v2.int_of(it -> 'input_id')); end if;
    if st <> 'active' then perform la_obra_v2.fail(422, 'El insumo ' || la_obra_v2.int_of(it -> 'input_id') || ' está inactivo'); end if;
  end loop;
  return pid;
end $$;

create or replace function la_obra_v2.ep_recipes__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare pid integer;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  pid := la_obra_v2.recipe_check(b, false);
  begin
    insert into la_obra_v2.recipes(product_id, input_id, quantity)
    select pid, la_obra_v2.int_of(it -> 'input_id'), round(la_obra_v2.num(it -> 'quantity'), 3)
    from jsonb_array_elements(b -> 'inputs') it;
  exception when unique_violation then
    perform la_obra_v2.fail(422, 'No repitas el mismo insumo en la receta');
  end;
  return la_obra_v2.ok('Receta registrada correctamente');
end $$;

create or replace function la_obra_v2.ep_recipes__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare pid integer;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  pid := la_obra_v2.recipe_check(b, true);
  delete from la_obra_v2.recipes where product_id = pid;
  begin
    insert into la_obra_v2.recipes(product_id, input_id, quantity)
    select pid, la_obra_v2.int_of(it -> 'input_id'), round(la_obra_v2.num(it -> 'quantity'), 3)
    from jsonb_array_elements(b -> 'inputs') it;
  exception when unique_violation then
    perform la_obra_v2.fail(422, 'No repitas el mismo insumo en la receta');
  end;
  return la_obra_v2.ok('Receta actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_recipes__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  pid integer;
  p record;
  rows_j jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  pid := la_obra_v2.pos_id(q -> 'product_id', 'El id del producto no es válido');
  select id, name, type into p from la_obra_v2.products where id = pid;
  if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if p.type <> 'prepared' then perform la_obra_v2.fail(422, 'El producto no es de tipo prepared'); end if;
  select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'quantity', r.quantity, 'unit', i.unit) order by i.name)
  into rows_j from la_obra_v2.recipes r join la_obra_v2.inputs i on i.id = r.input_id where r.product_id = pid;
  if rows_j is null then perform la_obra_v2.fail(404, 'El producto no tiene receta registrada'); end if;
  return jsonb_build_object('success', true, 'recipe', jsonb_build_object(
    'product', jsonb_build_object('id', p.id, 'name', p.name), 'inputs', rows_j));
end $$;

-- ---------------------------------------------------------------------
-- PREPARACIONES (subrecetas)
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.ep_preparations__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok);
  return la_obra_v2.ok('Preparaciones consultadas', jsonb_build_object('preparations', coalesce((
    select jsonb_agg(
      to_jsonb(p) || jsonb_build_object(
        'inputs', coalesce((
          select jsonb_agg(jsonb_build_object('input_id', pi.input_id, 'quantity', pi.quantity,
                   'is_estimated', pi.is_estimated, 'name', i.name, 'unit', i.unit) order by i.name)
          from la_obra_v2.preparation_inputs pi join la_obra_v2.inputs i on i.id = pi.input_id
          where pi.preparation_id = p.id), '[]'::jsonb),
        'batch_cost', c -> 'batch_cost',
        'unit_cost', c -> 'unit_cost',
        'missing_prices', coalesce(c -> 'missing', '[]'::jsonb))
      order by p.name)
    from la_obra_v2.preparations p
    cross join lateral (select la_obra_v2.preparation_cost(p.id) as c) cc
  ), '[]'::jsonb)));
end $$;

create or replace function la_obra_v2.preparation_validate(b jsonb)
returns void language plpgsql as $$
declare
  nm text := la_obra_v2.jtrim(b -> 'name');
  ds text := la_obra_v2.jtrim(b -> 'description');
  it jsonb;
  iid integer;
  seen integer[] := '{}';
begin
  if nm = '' or char_length(nm) > 120 or char_length(ds) > 255 or not la_obra_v2.is_num(b -> 'yield_quantity')
     or la_obra_v2.num(b -> 'yield_quantity') <= 0 or coalesce(b ->> 'yield_unit', '') not in ('portion','piece','g','ml')
     or jsonb_typeof(b -> 'inputs') is distinct from 'array' or jsonb_array_length(b -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Nombre, rendimiento e ingredientes válidos son obligatorios');
  end if;
  for it in select value from jsonb_array_elements(b -> 'inputs') loop
    iid := la_obra_v2.pos_id(it -> 'input_id');
    if iid = any(seen) or not la_obra_v2.is_num(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 then
      perform la_obra_v2.fail(422, 'Insumos duplicados o cantidades inválidas');
    end if;
    seen := seen || iid;
    if not exists (select 1 from la_obra_v2.inputs where id = iid and status = 'active') then
      perform la_obra_v2.fail(422, 'Insumo inexistente o inactivo');
    end if;
  end loop;
end $$;

create or replace function la_obra_v2.preparation_save_inputs(p_id integer, b jsonb)
returns void language sql as $$
  insert into la_obra_v2.preparation_inputs(preparation_id, input_id, quantity, is_estimated)
  select p_id, la_obra_v2.int_of(it -> 'input_id'), round(la_obra_v2.num(it -> 'quantity'), 3), la_obra_v2.truthy(it -> 'is_estimated')
  from jsonb_array_elements(b -> 'inputs') with ordinality e(it, o) order by o
$$;

create or replace function la_obra_v2.ep_preparations__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true);
  perform la_obra_v2.preparation_validate(b);
  insert into la_obra_v2.preparations(name, description, yield_quantity, yield_unit, yield_estimated)
  values (la_obra_v2.jtrim(b -> 'name'), la_obra_v2.jtrim(b -> 'description'), round(la_obra_v2.num(b -> 'yield_quantity'), 3),
          b ->> 'yield_unit', la_obra_v2.truthy(b -> 'yield_estimated'))
  returning id into new_id;
  perform la_obra_v2.preparation_save_inputs(new_id, b);
  return la_obra_v2.ok('Preparación guardada', jsonb_build_object('id', new_id));
end $$;

create or replace function la_obra_v2.ep_preparations__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare pid integer;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  perform la_obra_v2.preparation_validate(b);
  if not exists (select 1 from la_obra_v2.preparations where id = pid) then perform la_obra_v2.fail(404, 'Preparación no encontrada'); end if;
  update la_obra_v2.preparations
  set name = la_obra_v2.jtrim(b -> 'name'), description = la_obra_v2.jtrim(b -> 'description'),
      yield_quantity = round(la_obra_v2.num(b -> 'yield_quantity'), 3), yield_unit = b ->> 'yield_unit',
      yield_estimated = la_obra_v2.truthy(b -> 'yield_estimated'), updated_at = la_obra_v2.now_mx()
  where id = pid;
  delete from la_obra_v2.preparation_inputs where preparation_id = pid;
  perform la_obra_v2.preparation_save_inputs(pid, b);
  return la_obra_v2.ok('Preparación guardada', jsonb_build_object('id', pid));
end $$;

create or replace function la_obra_v2.ep_preparations__delete(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare pid integer;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_user(tok, true);
  pid := la_obra_v2.pos_id(b -> 'id');
  perform 1 from la_obra_v2.preparations where id = pid for update;
  if not found then perform la_obra_v2.fail(404, 'La preparación no existe o ya fue eliminada'); end if;
  -- No borrar preparaciones utilizadas por productos: conservar integridad de costos
  if exists (select 1 from la_obra_v2.product_components where preparation_id = pid) then
    perform la_obra_v2.fail(409, 'No se puede eliminar: esta preparación está utilizada en un producto. Retírala de la composición del producto antes de eliminarla.');
  end if;
  begin
    delete from la_obra_v2.preparation_inputs where preparation_id = pid;
    delete from la_obra_v2.preparations where id = pid;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque la preparación está relacionada con otros registros o con el historial.');
  end;
  return la_obra_v2.ok('Preparación eliminada correctamente', jsonb_build_object('id', pid));
end $$;
