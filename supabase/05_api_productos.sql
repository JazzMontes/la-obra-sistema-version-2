-- =====================================================================
-- La Obra v2 · 05 · products/* y files/*
-- Las fotos se guardan en la tabla files con la misma ruta "uploads/<carpeta>/<nombre>".
-- La app manda la foto como data URL (data:image/jpeg;base64,...) en el campo "image".
-- =====================================================================
set check_function_bodies = off;

-- Valida y guarda una imagen enviada como data URL. Devuelve la ruta relativa.
create or replace function la_obra_v2.save_image(p_data jsonb, p_folder text, p_prefix text)
returns text language plpgsql as $$
declare s text := la_obra_v2.jtext(p_data); v_bytes bytea; v_mime text; v_ext text; v_path text;
begin
  if s is null or s = '' then perform la_obra_v2.fail(422, 'Selecciona una imagen'); end if;
  s := regexp_replace(s, '^data:[^,]*,', '');
  begin
    v_bytes := decode(regexp_replace(s, '\s', '', 'g'), 'base64');
  exception when others then perform la_obra_v2.fail(422, 'No se pudo recibir la imagen');
  end;
  if octet_length(v_bytes) <= 0 then perform la_obra_v2.fail(422, 'No se pudo recibir la imagen'); end if;
  if octet_length(v_bytes) > 3 * 1024 * 1024 then perform la_obra_v2.fail(413, 'La imagen debe pesar menos de 3 MB'); end if;
  -- Tipo real por los primeros bytes (no por lo que diga el cliente)
  if substring(v_bytes from 1 for 3) = '\xffd8ff'::bytea then v_mime := 'image/jpeg'; v_ext := 'jpg';
  elsif substring(v_bytes from 1 for 8) = '\x89504e470d0a1a0a'::bytea then v_mime := 'image/png'; v_ext := 'png';
  elsif substring(v_bytes from 1 for 4) = '\x52494646'::bytea and substring(v_bytes from 9 for 4) = '\x57454250'::bytea then v_mime := 'image/webp'; v_ext := 'webp';
  else perform la_obra_v2.fail(415, 'Formato no permitido. Usa JPG, PNG o WEBP');
  end if;
  v_path := 'uploads/' || p_folder || '/' || p_prefix || '_' || encode(extensions.gen_random_bytes(8), 'hex') || '.' || v_ext;
  insert into la_obra_v2.files(path, mime, data) values (v_path, v_mime, v_bytes);
  return v_path;
end $$;

create or replace function la_obra_v2.delete_file(p_path text, p_folder text)
returns void language sql as $$
  delete from la_obra_v2.files where p_path is not null and path = p_path and path like 'uploads/' || p_folder || '/%';
$$;

-- files/image.php?path=uploads/... → { data_url }
create or replace function la_obra_v2.ep_files__image(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_path text := coalesce(la_obra_v2.jtext(q -> 'path'), ''); f la_obra_v2.files;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  if v_path !~ '^uploads/(products|tickets|avatars)/[A-Za-z0-9_.-]+$' then perform la_obra_v2.fail(422, 'Ruta de imagen inválida'); end if;
  select * into f from la_obra_v2.files where path = v_path;
  if f.path is null then perform la_obra_v2.fail(404, 'La imagen no existe en el servidor'); end if;
  return la_obra_v2.ok(200, 'Imagen', jsonb_build_object('data_url', 'data:' || f.mime || ';base64,' || replace(encode(f.data, 'base64'), E'\n', '')));
end $$;

create or replace function la_obra_v2.product_json(p_id int)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description,
    'category', jsonb_build_object('id', c.id, 'name', c.name), 'type', p.type, 'price', p.price::float8,
    'is_available', p.is_available, 'status', p.status, 'image_path', p.image_path)
  from la_obra_v2.products p join la_obra_v2.categories c on c.id = p.category_id where p.id = p_id;
$$;

create or replace function la_obra_v2.ep_products__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Productos', jsonb_build_object('products',
    (select coalesce(jsonb_agg(la_obra_v2.product_json(id) order by id), '[]') from la_obra_v2.products)));
end $$;

create or replace function la_obra_v2.ep_products__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.is_int(q -> 'id') or la_obra_v2.num(q -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id del producto no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id')::int;
  r := la_obra_v2.product_json(v_id);
  if r is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok(200, 'Producto', jsonb_build_object('product', r));
end $$;

create or replace function la_obra_v2.ep_products__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_desc text := la_obra_v2.jstr(b -> 'description');
        v_type text := la_obra_v2.jstr(b -> 'type'); v_cat int; v_price numeric; v_cs text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if v_name = '' or v_desc = '' or not la_obra_v2.is_int(b -> 'category_id') or la_obra_v2.num(b -> 'category_id') <= 0
     or v_type not in ('prepared','resale') or not la_obra_v2.is_num(b -> 'price') or la_obra_v2.num(b -> 'price') < 0 then
    perform la_obra_v2.fail(422, 'Los datos del producto no son válidos');
  end if;
  v_cat := la_obra_v2.num(b -> 'category_id')::int; v_price := la_obra_v2.num(b -> 'price');
  select status into v_cs from la_obra_v2.categories where id = v_cat;
  if v_cs is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if v_cs <> 'active' then perform la_obra_v2.fail(422, 'La categoría está inactiva'); end if;
  insert into la_obra_v2.products(name, description, category_id, type, price, is_available, status)
  values (v_name, v_desc, v_cat, v_type, round(v_price, 2), true, 'active') returning id into v_id;
  return la_obra_v2.ok(201, 'Producto registrado correctamente', jsonb_build_object('product', jsonb_build_object(
    'id', v_id, 'name', v_name, 'description', v_desc, 'category_id', v_cat, 'type', v_type, 'price', v_price::float8, 'is_available', true, 'status', 'active')));
end $$;

-- PHP: FILTER_VALIDATE_BOOLEAN con NULL_ON_FAILURE
create or replace function la_obra_v2.to_bool(v jsonb)
returns boolean language sql immutable as $$
  select case
    when v is null then null
    when jsonb_typeof(v) = 'boolean' then (v::text)::boolean
    when jsonb_typeof(v) = 'number' then case when v::text in ('1') then true when v::text in ('0') then false else null end
    when jsonb_typeof(v) = 'string' then case when lower(btrim(v #>> '{}')) in ('1','true','on','yes') then true
                                              when lower(btrim(v #>> '{}')) in ('0','false','off','no','') then false else null end
    when jsonb_typeof(v) = 'null' then false
    else null end;
$$;

create or replace function la_obra_v2.ep_products__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; p la_obra_v2.products; v text; v_cat int; v_cs text; v_bool boolean; n int := 0;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if b is null or jsonb_typeof(b) <> 'object' then b := '{}'; end if;
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select * into p from la_obra_v2.products where id = v_id;
  if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if b ? 'name' then
    v := la_obra_v2.jstr(b -> 'name'); if v = '' then perform la_obra_v2.fail(422, 'Nombre inválido'); end if;
    p.name := v; n := n + 1;
  end if;
  if b ? 'description' then
    v := la_obra_v2.jstr(b -> 'description'); if v = '' then perform la_obra_v2.fail(422, 'Descripción inválida'); end if;
    p.description := v; n := n + 1;
  end if;
  if b ? 'category_id' then
    if not la_obra_v2.is_int(b -> 'category_id') or la_obra_v2.num(b -> 'category_id') <= 0 then perform la_obra_v2.fail(422, 'Categoría inválida'); end if;
    v_cat := la_obra_v2.num(b -> 'category_id')::int;
    select status into v_cs from la_obra_v2.categories where id = v_cat;
    if v_cs is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
    if v_cs <> 'active' then perform la_obra_v2.fail(422, 'La categoría está inactiva'); end if;
    p.category_id := v_cat; n := n + 1;
  end if;
  if b ? 'type' then
    v := la_obra_v2.jstr(b -> 'type'); if v not in ('prepared','resale') then perform la_obra_v2.fail(422, 'Tipo inválido'); end if;
    p.type := v; n := n + 1;
  end if;
  if b ? 'price' then
    if not la_obra_v2.is_num(b -> 'price') or la_obra_v2.num(b -> 'price') < 0 then perform la_obra_v2.fail(422, 'Precio inválido'); end if;
    p.price := round(la_obra_v2.num(b -> 'price'), 2); n := n + 1;
  end if;
  if b ? 'is_available' then
    v_bool := la_obra_v2.to_bool(b -> 'is_available');
    if v_bool is null then perform la_obra_v2.fail(422, 'Disponibilidad inválida'); end if;
    p.is_available := v_bool; n := n + 1;
  end if;
  if n = 0 then perform la_obra_v2.fail(422, 'No se enviaron campos para actualizar'); end if;
  update la_obra_v2.products set name = p.name, description = p.description, category_id = p.category_id,
         type = p.type, price = p.price, is_available = p.is_available where id = v_id;
  return la_obra_v2.ok(200, 'Producto actualizado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__activate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.products where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_status = 'active' then perform la_obra_v2.fail(422, 'El producto ya está activo'); end if;
  update la_obra_v2.products set status = 'active', is_available = true where id = v_id;
  return la_obra_v2.ok(200, 'Producto activado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__deactivate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.products where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_status <> 'active' then perform la_obra_v2.fail(422, 'El producto ya está inactivo'); end if;
  update la_obra_v2.products set status = 'inactive', is_available = false where id = v_id;
  return la_obra_v2.ok(200, 'Producto desactivado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_img text; r jsonb;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select image_path into v_img from la_obra_v2.products where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  r := la_obra_v2.delete_or_conflict('products', v_id);
  perform la_obra_v2.delete_file(v_img, 'products');
  return r;
end $$;

create or replace function la_obra_v2.ep_products__components(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  v_id := la_obra_v2.positive_id(q -> 'product_id');
  if not exists(select 1 from la_obra_v2.products where id = v_id) then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok(200, 'Composición consultada', jsonb_build_object('components',
    (select coalesce(jsonb_agg(to_jsonb(pc) order by pc.id), '[]') from la_obra_v2.product_components pc where pc.product_id = v_id)));
end $$;

-- "!empty(x)" de PHP
create or replace function la_obra_v2.not_empty(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and jsonb_typeof(v) <> 'null' and not (
    (jsonb_typeof(v) = 'string' and (v #>> '{}') in ('', '0'))
    or (jsonb_typeof(v) = 'number' and (v::text)::numeric = 0)
    or (jsonb_typeof(v) = 'boolean' and v::text = 'false')
    or (jsonb_typeof(v) = 'array' and jsonb_array_length(v) = 0)
    or (jsonb_typeof(v) = 'object' and v = '{}'::jsonb));
$$;

create or replace function la_obra_v2.ep_products__save_components(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; it jsonb; v_in boolean; v_pr boolean; v_mode text; v_sid int; v_n bigint; v_qty numeric; v_uid int; v_uqty numeric;
begin
  perform la_obra_v2.method(m, 'PUT');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'product_id');
  if not exists(select 1 from la_obra_v2.products where id = v_id) then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if (b -> 'components') is null or jsonb_typeof(b -> 'components') not in ('array','object') then perform la_obra_v2.fail(422, 'Componentes inválidos'); end if;
  if jsonb_typeof(b -> 'components') = 'object' then b := jsonb_set(b, '{components}', (select coalesce(jsonb_agg(v), '[]') from jsonb_each(b -> 'components') e(k, v))); end if;
  for it in select * from jsonb_array_elements(b -> 'components') loop
    if jsonb_typeof(it) <> 'object' then perform la_obra_v2.fail(422, 'Componente inválido'); end if;
    v_in := la_obra_v2.not_empty(it -> 'input_id'); v_pr := la_obra_v2.not_empty(it -> 'preparation_id');
    v_mode := coalesce(la_obra_v2.jtext(it -> 'delivery_mode'), 'always');
    if v_in = v_pr or not la_obra_v2.is_num(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 or v_mode not in ('always','local','takeaway') then
      perform la_obra_v2.fail(422, 'Componente inválido');
    end if;
    v_sid := la_obra_v2.positive_id(case when v_in then it -> 'input_id' else it -> 'preparation_id' end);
    if (v_in and not exists(select 1 from la_obra_v2.inputs where id = v_sid)) or (v_pr and not exists(select 1 from la_obra_v2.preparations where id = v_sid)) then
      perform la_obra_v2.fail(422, 'Componente inexistente');
    end if;
    -- Insumo capturado en otra medida (pieza, cucharada…): se valida la medida
    if v_in then perform la_obra_v2.item_quantity(v_sid, it);
    elsif la_obra_v2.not_empty(it -> 'unit_id') then perform la_obra_v2.fail(422, 'Las preparaciones se capturan en su unidad de rendimiento');
    end if;
  end loop;
  delete from la_obra_v2.product_components where product_id = v_id;
  for it, v_n in select c, n from jsonb_array_elements(b -> 'components') with ordinality x(c, n) order by n loop
    v_in := la_obra_v2.not_empty(it -> 'input_id');
    if v_in then
      select o_qty, o_unit_id, o_unit_qty into v_qty, v_uid, v_uqty from la_obra_v2.item_quantity(la_obra_v2.num(it -> 'input_id')::int, it);
    else
      v_qty := round(la_obra_v2.num(it -> 'quantity'), 3); v_uid := null; v_uqty := null;
    end if;
    insert into la_obra_v2.product_components(product_id, input_id, preparation_id, quantity, is_estimated, delivery_mode, unit_id, unit_quantity)
    values (v_id,
            case when v_in then la_obra_v2.num(it -> 'input_id')::int end,
            case when la_obra_v2.not_empty(it -> 'preparation_id') then la_obra_v2.num(it -> 'preparation_id')::int end,
            v_qty,
            la_obra_v2.not_empty(it -> 'is_estimated'),
            coalesce(la_obra_v2.jtext(it -> 'delivery_mode'), 'always'),
            v_uid, v_uqty);
  end loop;
  return la_obra_v2.ok(200, 'Composición guardada');
end $$;

-- products/upload-image.php · campos: id, image (data URL)
create or replace function la_obra_v2.ep_products__upload_image(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text; v_path text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select image_path into v_old from la_obra_v2.products where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  v_path := la_obra_v2.save_image(b -> 'image', 'products', v_id::text);
  update la_obra_v2.products set image_path = v_path where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'products');
  return la_obra_v2.ok(200, 'Foto guardada correctamente', jsonb_build_object('image_path', v_path));
end $$;

create or replace function la_obra_v2.ep_products__delete_image(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select image_path into v_old from la_obra_v2.products where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if coalesce(v_old, '') = '' then return la_obra_v2.ok(200, 'El producto no tenía foto'); end if;
  update la_obra_v2.products set image_path = null where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'products');
  return la_obra_v2.ok(200, 'Foto eliminada correctamente');
end $$;
