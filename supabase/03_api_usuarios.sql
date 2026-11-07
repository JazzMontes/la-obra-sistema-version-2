-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 03 · API: estado, autenticación y usuarios
-- Cada función equivale a un archivo PHP del backend anterior:
--   ep_<carpeta>__<archivo>  (los guiones pasan a guion bajo)
--   ej. auth/login.php -> la_obra_v2.ep_auth__login
-- Parámetros: m = método HTTP, q = parámetros de la URL, b = cuerpo JSON, tok = token de sesión
-- =====================================================================

-- health.php — no requiere sesión
create or replace function la_obra_v2.ep_health(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  return jsonb_build_object(
    'success', true,
    'message', 'API disponible',
    'server_time', to_char(la_obra_v2.now_mx(), 'YYYY-MM-DD"T"HH24:MI:SS')
                   || to_char((now() at time zone 'America/Mexico_City') - (now() at time zone 'UTC'), 'HH24:MI'),
    'database_ok', true,
    'missing', '[]'::jsonb,
    'run_migrations', '[]'::jsonb,
    'backend', 'supabase',
    'schema_version', (select value from la_obra_v2.meta where key = 'schema_version'));
end $$;

-- auth/login.php
create or replace function la_obra_v2.ep_auth__login(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  uname text := la_obra_v2.jtrim(b -> 'username');
  pass text := la_obra_v2.jstr(b -> 'password');
  u la_obra_v2.users;
  token text;
begin
  perform la_obra_v2.method(m, 'POST');
  if uname = '' or pass = '' then perform la_obra_v2.fail(422, 'Usuario y contraseña son obligatorios'); end if;
  select * into u from la_obra_v2.users where lower(username) = lower(uname) limit 1;
  if u.id is null or not la_obra_v2.password_ok(pass, u.password_hash) then
    perform la_obra_v2.fail(401, 'Usuario o contraseña incorrectos');
  end if;
  if u.status <> 'active' then perform la_obra_v2.fail(403, 'La cuenta no tiene acceso al sistema'); end if;

  -- Limpiar sesiones vencidas para no acumular registros
  delete from la_obra_v2.sessions where expires_at < la_obra_v2.now_mx() - interval '1 day';

  -- Token aleatorio; en la base solo se guarda su hash. La sesión dura 8 horas.
  token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into la_obra_v2.sessions(user_id, token_hash, expires_at)
  values (u.id, la_obra_v2.token_hash(token), la_obra_v2.now_mx() + interval '8 hours');

  return jsonb_build_object(
    'success', true,
    'message', 'Inicio de sesión correcto',
    'token', token,
    'user', jsonb_build_object('id', u.id, 'name', u.name, 'username', u.username, 'email', u.email,
                               'role', u.role, 'must_change_password', u.must_change_password));
end $$;

-- auth/logout.php
create or replace function la_obra_v2.ep_auth__logout(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare sid integer;
begin
  perform la_obra_v2.method(m, 'POST');
  if coalesce(btrim(tok), '') = '' then perform la_obra_v2.fail(401, 'Token de autenticación requerido'); end if;
  select id into sid from la_obra_v2.sessions where token_hash = la_obra_v2.token_hash(tok) limit 1;
  if sid is null then perform la_obra_v2.fail(401, 'Sesión inválida'); end if;
  delete from la_obra_v2.sessions where id = sid;
  return la_obra_v2.ok('Sesión cerrada correctamente');
end $$;

-- auth/me.php (GET consulta, PUT modifica el propio perfil)
create or replace function la_obra_v2.ep_auth__me(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  nm text; un text; em text;
begin
  if upper(m) not in ('GET', 'PUT') then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
  u := la_obra_v2.auth_user(tok);
  if upper(m) = 'GET' then
    return jsonb_build_object('success', true, 'user', jsonb_build_object(
      'id', u.id, 'name', u.name, 'username', u.username, 'email', u.email,
      'role', u.role, 'status', u.status, 'must_change_password', u.must_change_password));
  end if;
  nm := la_obra_v2.jtrim(b -> 'name');
  un := la_obra_v2.jtrim(b -> 'username');
  em := la_obra_v2.jtrim(b -> 'email');
  if nm = '' or un = '' or em = '' then perform la_obra_v2.fail(422, 'Nombre, usuario y correo son obligatorios'); end if;
  if not la_obra_v2.valid_email(em) then perform la_obra_v2.fail(422, 'El correo electrónico no es válido'); end if;
  if char_length(nm) > 100 or char_length(un) > 50 or char_length(em) > 150 then
    perform la_obra_v2.fail(422, 'Algún dato es demasiado largo');
  end if;
  if exists (select 1 from la_obra_v2.users where (lower(username) = lower(un) or lower(email) = lower(em)) and id <> u.id) then
    perform la_obra_v2.fail(409, 'El nombre de usuario o correo ya está registrado');
  end if;
  update la_obra_v2.users set name = nm, username = un, email = em where id = u.id;
  return la_obra_v2.ok('Perfil actualizado correctamente', jsonb_build_object('user', jsonb_build_object(
    'id', u.id, 'name', nm, 'username', un, 'email', em, 'role', u.role, 'status', u.status)));
end $$;

-- auth/password.php
create or replace function la_obra_v2.ep_auth__password(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  u la_obra_v2.users;
  cur text := la_obra_v2.jstr(b -> 'current_password');
  nw text := la_obra_v2.jstr(b -> 'new_password');
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_user(tok);
  if cur = '' or nw = '' then
    perform la_obra_v2.fail(422, 'La contraseña actual y la nueva contraseña son obligatorias');
  end if;
  if octet_length(nw) < 8 then perform la_obra_v2.fail(422, 'La nueva contraseña debe tener al menos 8 caracteres'); end if;
  if not la_obra_v2.password_ok(cur, u.password_hash) then
    perform la_obra_v2.fail(401, 'La contraseña actual es incorrecta');
  end if;
  update la_obra_v2.users set password_hash = la_obra_v2.hash_password(nw), must_change_password = false where id = u.id;
  return la_obra_v2.ok('Contraseña actualizada correctamente');
end $$;

-- auth/register.php — no requiere sesión; la cuenta queda pendiente de aprobación
create or replace function la_obra_v2.ep_auth__register(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  nm text := la_obra_v2.jtrim(b -> 'name');
  un text := la_obra_v2.jtrim(b -> 'username');
  em text := la_obra_v2.jtrim(b -> 'email');
  pw text := la_obra_v2.jstr(b -> 'password');
begin
  perform la_obra_v2.method(m, 'POST');
  if nm = '' or un = '' or em = '' or pw = '' then perform la_obra_v2.fail(422, 'Todos los campos son obligatorios'); end if;
  if not la_obra_v2.valid_email(em) then perform la_obra_v2.fail(422, 'El correo electrónico no es válido'); end if;
  if octet_length(pw) < 8 then perform la_obra_v2.fail(422, 'La contraseña debe tener al menos 8 caracteres'); end if;
  if char_length(nm) > 100 or char_length(un) > 50 or char_length(em) > 150 then
    perform la_obra_v2.fail(422, 'Algún dato es demasiado largo');
  end if;
  if exists (select 1 from la_obra_v2.users where lower(username) = lower(un) or lower(email) = lower(em)) then
    perform la_obra_v2.fail(409, 'El nombre de usuario o correo ya está registrado');
  end if;
  insert into la_obra_v2.users(name, username, email, password_hash, status, role, must_change_password)
  values (nm, un, em, la_obra_v2.hash_password(pw), 'pending', null, false);
  return la_obra_v2.ok('Registro realizado correctamente. Tu cuenta está pendiente de aprobación.');
end $$;

-- users/index.php
create or replace function la_obra_v2.ep_users__index(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare st text := btrim(coalesce(la_obra_v2.qp(q, 'status'), ''));
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para consultar usuarios');
  if st <> '' and st not in ('pending', 'active', 'rejected', 'inactive') then
    perform la_obra_v2.fail(422, 'El estado no es válido');
  end if;
  return jsonb_build_object('success', true, 'users', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'username', username, 'email', email,
                                        'status', status, 'role', role) order by id)
    from la_obra_v2.users where st = '' or status = st), '[]'::jsonb));
end $$;

-- users/show.php
create or replace function la_obra_v2.ep_users__show(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  uid integer;
  j jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para consultar usuarios');
  uid := la_obra_v2.pos_id(q -> 'id', 'El id del usuario no es válido');
  select jsonb_build_object('id', id, 'name', name, 'username', username, 'email', email, 'status', status, 'role', role)
  into j from la_obra_v2.users where id = uid;
  if j is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  return jsonb_build_object('success', true, 'user', j);
end $$;

-- users/create.php — el administrador crea la cuenta con una contraseña temporal
create or replace function la_obra_v2.ep_users__create(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  nm text := la_obra_v2.jtrim(b -> 'name');
  un text := la_obra_v2.jtrim(b -> 'username');
  em text := la_obra_v2.jtrim(b -> 'email');
  rl text := la_obra_v2.jtrim(b -> 'role');
  temp text;
  new_id integer;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para realizar esta acción');
  if nm = '' or un = '' or em = '' or rl = '' then perform la_obra_v2.fail(422, 'Todos los campos son obligatorios'); end if;
  if not la_obra_v2.valid_email(em) then perform la_obra_v2.fail(422, 'El correo electrónico no es válido'); end if;
  if rl not in ('admin', 'employee') then perform la_obra_v2.fail(422, 'El rol no es válido'); end if;
  if char_length(nm) > 100 or char_length(un) > 50 or char_length(em) > 150 then
    perform la_obra_v2.fail(422, 'Algún dato es demasiado largo');
  end if;
  if exists (select 1 from la_obra_v2.users where lower(username) = lower(un) or lower(email) = lower(em)) then
    perform la_obra_v2.fail(409, 'El nombre de usuario o correo ya está registrado');
  end if;
  temp := encode(extensions.gen_random_bytes(5), 'hex');
  insert into la_obra_v2.users(name, username, email, password_hash, status, role, must_change_password)
  values (nm, un, em, la_obra_v2.hash_password(temp), 'active', rl, true)
  returning id into new_id;
  return la_obra_v2.ok('Usuario creado correctamente', jsonb_build_object(
    'user', jsonb_build_object('id', new_id, 'name', nm, 'username', un, 'email', em, 'role', rl,
                               'status', 'active', 'must_change_password', true),
    'temporary_password', temp));
end $$;

-- users/update.php?id=N — estado y/o rol
create or replace function la_obra_v2.ep_users__update(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  uid integer;
  u la_obra_v2.users;
  new_status text;
  new_role text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true, 'No tienes permisos para modificar usuarios');
  uid := la_obra_v2.pos_id(coalesce(q -> 'id', b -> 'id'), 'El id del usuario no es válido');
  select * into u from la_obra_v2.users where id = uid;
  if u.id is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  if jsonb_typeof(b) <> 'object' then perform la_obra_v2.fail(422, 'Los datos enviados no son válidos'); end if;
  if not (b ? 'status') and not (b ? 'role') then
    perform la_obra_v2.fail(422, 'Debes proporcionar status, role o ambos');
  end if;
  new_status := u.status;
  if b ? 'status' then
    new_status := la_obra_v2.jtrim(b -> 'status');
    if new_status not in ('pending', 'active', 'rejected', 'inactive') then
      perform la_obra_v2.fail(422, 'El estado no es válido');
    end if;
  end if;
  new_role := u.role;
  if b ? 'role' then
    new_role := la_obra_v2.jtrim(b -> 'role');
    if new_role not in ('admin', 'employee') then perform la_obra_v2.fail(422, 'El rol no es válido'); end if;
  end if;
  -- Una cuenta activa debe tener un rol
  if new_status = 'active' and coalesce(new_role, '') = '' then
    perform la_obra_v2.fail(422, 'Para activar la cuenta debes asignar un rol');
  end if;
  -- Proteger al último administrador activo
  if u.role = 'admin' and (new_role is distinct from 'admin' or new_status <> 'active') then
    if not exists (select 1 from la_obra_v2.users where role = 'admin' and status = 'active' and id <> uid) then
      perform la_obra_v2.fail(422, 'No se puede realizar el cambio porque el sistema debe conservar al menos un administrador activo');
    end if;
  end if;
  update la_obra_v2.users set status = new_status, role = new_role where id = uid;
  -- Al desactivar o rechazar, se cierran sus sesiones abiertas
  if new_status <> 'active' then delete from la_obra_v2.sessions where user_id = uid; end if;
  return la_obra_v2.ok('Usuario actualizado correctamente', jsonb_build_object('user', jsonb_build_object(
    'id', u.id, 'name', u.name, 'username', u.username, 'email', u.email, 'status', new_status, 'role', new_role)));
end $$;

-- users/employee-status.php
create or replace function la_obra_v2.ep_users__employee_status(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  uid integer;
  st text := la_obra_v2.jstr(b -> 'status');
  t la_obra_v2.users;
  n integer;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_user(tok, true);
  uid := la_obra_v2.pos_id(b -> 'id');
  if jsonb_typeof(b -> 'status') is distinct from 'string' or st not in ('active', 'inactive') then
    perform la_obra_v2.fail(422, 'El estado debe ser active o inactive');
  end if;
  select * into t from la_obra_v2.users where id = uid;
  if t.id is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  if t.role is distinct from 'employee' then perform la_obra_v2.fail(403, 'Solo se permite modificar el estado de empleados'); end if;
  if t.status not in ('pending', 'active', 'inactive') then
    perform la_obra_v2.fail(409, 'El estado actual de la cuenta no permite esta operación');
  end if;
  if t.status = st then
    return la_obra_v2.ok('La cuenta ya tiene ese estado', jsonb_build_object('user',
      jsonb_build_object('id', t.id, 'name', t.name, 'role', t.role, 'status', t.status)));
  end if;
  update la_obra_v2.users set status = st where id = uid and role = 'employee' and status in ('pending', 'active', 'inactive');
  get diagnostics n = row_count;
  if n = 0 then perform la_obra_v2.fail(409, 'La cuenta cambió de estado; vuelve a consultar'); end if;
  if st <> 'active' then delete from la_obra_v2.sessions where user_id = uid; end if;
  return la_obra_v2.ok('Estado del empleado actualizado', jsonb_build_object('user', (
    select jsonb_build_object('id', id, 'name', name, 'username', username, 'email', email, 'status', status, 'role', role)
    from la_obra_v2.users where id = uid)));
end $$;
