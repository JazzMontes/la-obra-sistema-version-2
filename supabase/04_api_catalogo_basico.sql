-- =====================================================================
-- La Obra v2 · 04 · categories/* y payment-methods/*
-- =====================================================================
set check_function_bodies = off;

-- Borrado que respeta las relaciones (el 23000 de MySQL = 23503 en PostgreSQL)
create or replace function la_obra_v2.delete_or_conflict(p_table text, p_id int)
returns jsonb language plpgsql as $$
begin
  begin
    execute format('delete from la_obra_v2.%I where id = $1', p_table) using p_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque el registro está relacionado con otros datos. Puedes desactivarlo para conservar el historial.');
  end;
  return la_obra_v2.ok(200, 'Registro eliminado correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Categorías', jsonb_build_object('categories', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status) order by name, id), '[]') from la_obra_v2.categories)));
end $$;

create or replace function la_obra_v2.ep_categories__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if v_name = '' then perform la_obra_v2.fail(422, 'El nombre es obligatorio'); end if;
  if exists(select 1 from la_obra_v2.categories where lower(name) = lower(v_name)) then perform la_obra_v2.fail(409, 'La categoría ya existe'); end if;
  insert into la_obra_v2.categories(name, status) values (v_name, 'active') returning id into v_id;
  return la_obra_v2.ok(201, 'Categoría registrada correctamente', jsonb_build_object('category', jsonb_build_object('id', v_id, 'name', v_name, 'status', 'active')));
end $$;

create or replace function la_obra_v2.ep_categories__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_id int;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 or v_name = '' then perform la_obra_v2.fail(422, 'Id y nombre válidos son obligatorios'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  if not exists(select 1 from la_obra_v2.categories where id = v_id) then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if exists(select 1 from la_obra_v2.categories where lower(name) = lower(v_name) and id <> v_id) then perform la_obra_v2.fail(409, 'Ya existe otra categoría con ese nombre'); end if;
  update la_obra_v2.categories set name = v_name where id = v_id;
  return la_obra_v2.ok(200, 'Categoría actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__activate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select status into v_status from la_obra_v2.categories where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if v_status = 'active' then perform la_obra_v2.fail(422, 'La categoría ya está activa'); end if;
  update la_obra_v2.categories set status = 'active' where id = v_id;
  return la_obra_v2.ok(200, 'Categoría activada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__deactivate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.categories where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if v_status <> 'active' then perform la_obra_v2.fail(422, 'La categoría ya está inactiva'); end if;
  update la_obra_v2.categories set status = 'inactive' where id = v_id;
  return la_obra_v2.ok(200, 'Categoría desactivada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.categories where id = v_id) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  return la_obra_v2.delete_or_conflict('categories', v_id);
end $$;

create or replace function la_obra_v2.ep_payment_methods__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Métodos de pago', jsonb_build_object('payment_methods', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status,
             'commission_percent', coalesce(commission_percent, 0)::float8) order by name, id), '[]') from la_obra_v2.payment_methods)));
end $$;

-- Porcentaje de comisión válido (0 a 99.99, dos decimales); p_default si no viene
create or replace function la_obra_v2.commission_value(v jsonb, p_default numeric default 0)
returns numeric language plpgsql as $$
begin
  if v is null or jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then return p_default; end if;
  if not la_obra_v2.is_num(v) or la_obra_v2.num(v) < 0 or la_obra_v2.num(v) >= 100 then
    perform la_obra_v2.fail(422, 'La comisión debe ser un porcentaje entre 0 y 99.99');
  end if;
  return round(la_obra_v2.num(v), 2);
end $$;

create or replace function la_obra_v2.ep_payment_methods__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if v_name = '' then perform la_obra_v2.fail(422, 'El nombre es obligatorio'); end if;
  if exists(select 1 from la_obra_v2.payment_methods where lower(name) = lower(v_name)) then perform la_obra_v2.fail(409, 'El método de pago ya existe'); end if;
  insert into la_obra_v2.payment_methods(name, status, commission_percent)
  values (v_name, 'active', la_obra_v2.commission_value(b -> 'commission_percent', case when lower(v_name) like '%tarjeta%' then 4 else 0 end)) returning id into v_id;
  return la_obra_v2.ok(201, 'Método de pago registrado correctamente', jsonb_build_object('payment_method', jsonb_build_object('id', v_id, 'name', v_name, 'status', 'active',
    'commission_percent', (select commission_percent::float8 from la_obra_v2.payment_methods where id = v_id))));
end $$;

create or replace function la_obra_v2.ep_payment_methods__status(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text := la_obra_v2.jtext(b -> 'status');
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 or coalesce(v_status, '') not in ('active','inactive') then
    perform la_obra_v2.fail(422, 'Datos inválidos');
  end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_id) then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
  update la_obra_v2.payment_methods set status = v_status where id = v_id;
  return la_obra_v2.ok(200, 'Estado del método de pago actualizado correctamente');
end $$;

-- payment-methods/commission.php · PATCH {id, commission_percent}: comisión de la terminal (ej. 4 para tarjeta)
-- Aplica a los cobros que se registren desde ese momento; los anteriores conservan la suya.
create or replace function la_obra_v2.ep_payment_methods__commission(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_pct numeric;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_id) then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
  if not (b ? 'commission_percent') then perform la_obra_v2.fail(422, 'Indica la comisión'); end if;
  v_pct := la_obra_v2.commission_value(b -> 'commission_percent', 0);
  update la_obra_v2.payment_methods set commission_percent = v_pct where id = v_id;
  return la_obra_v2.ok(200, 'Comisión actualizada', jsonb_build_object('payment_method', (
    select jsonb_build_object('id', id, 'name', name, 'status', status, 'commission_percent', commission_percent::float8)
      from la_obra_v2.payment_methods where id = v_id)));
end $$;

create or replace function la_obra_v2.ep_payment_methods__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_id) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  return la_obra_v2.delete_or_conflict('payment_methods', v_id);
end $$;
