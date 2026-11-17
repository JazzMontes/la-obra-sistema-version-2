-- =====================================================================
-- La Obra v2 · 03 · auth/* y users/*
-- =====================================================================
set check_function_bodies = off;

-- auth/login.php
create or replace function la_obra_v2.ep_auth__login(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_user text; v_pass text; u la_obra_v2.users; v_token text;
begin
  perform la_obra_v2.method(m, 'POST');
  v_user := la_obra_v2.jstr(b -> 'username');
  v_pass := coalesce(la_obra_v2.jtext(b -> 'password'), '');
  if v_user = '' or v_pass = '' then perform la_obra_v2.fail(422, 'Usuario y contraseña son obligatorios'); end if;
  select * into u from la_obra_v2.users where username = v_user limit 1;
  if u.id is null or not la_obra_v2.check_password(v_pass, u.password_hash) then
    perform la_obra_v2.fail(401, 'Usuario o contraseña incorrectos');
  end if;
  if u.status <> 'active' then perform la_obra_v2.fail(403, 'La cuenta no tiene acceso al sistema'); end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into la_obra_v2.sessions(user_id, token_hash, expires_at)
  values (u.id, la_obra_v2.sha256(v_token), localtimestamp + interval '8 hours');
  -- Limpieza: sesiones vencidas
  delete from la_obra_v2.sessions where expires_at < localtimestamp - interval '1 day';
  return la_obra_v2.ok(200, 'Inicio de sesión correcto', jsonb_build_object('token', v_token,
    'user', jsonb_build_object('id', u.id, 'name', u.name, 'username', u.username, 'email', u.email,
                               'role', u.role, 'must_change_password', u.must_change_password, 'avatar_path', u.avatar_path)));
end $$;

-- auth/logout.php
create or replace function la_obra_v2.ep_auth__logout(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  if t is null or btrim(t) = '' then perform la_obra_v2.fail(401, 'Token de autenticación requerido'); end if;
  select id into v_id from la_obra_v2.sessions where token_hash = la_obra_v2.sha256(btrim(t)) limit 1;
  if v_id is null then perform la_obra_v2.fail(401, 'Sesión inválida'); end if;
  delete from la_obra_v2.sessions where id = v_id;
  return la_obra_v2.ok(200, 'Sesión cerrada correctamente');
end $$;

-- auth/me.php (GET: mis datos · PUT: editar nombre, usuario y correo)
create or replace function la_obra_v2.ep_auth__me(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_name text; v_username text; v_email text;
begin
  if m not in ('GET', 'PUT') then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
  u := la_obra_v2.auth_long(t);
  if m = 'GET' then
    return la_obra_v2.ok(200, 'Sesión activa', jsonb_build_object('user', jsonb_build_object('id', u.id, 'name', u.name,
      'username', u.username, 'email', u.email, 'role', u.role, 'status', u.status, 'must_change_password', u.must_change_password,
      'avatar_path', u.avatar_path)));
  end if;
  v_name := la_obra_v2.jstr(b -> 'name');
  v_username := la_obra_v2.jstr(b -> 'username');
  v_email := la_obra_v2.jstr(b -> 'email');
  if v_name = '' or v_username = '' or v_email = '' then perform la_obra_v2.fail(422, 'Nombre, usuario y correo son obligatorios'); end if;
  if not la_obra_v2.valid_email(v_email) then perform la_obra_v2.fail(422, 'El correo electrónico no es válido'); end if;
  if exists(select 1 from la_obra_v2.users where (username = v_username or email = v_email) and id <> u.id) then
    perform la_obra_v2.fail(409, 'El nombre de usuario o correo ya está registrado');
  end if;
  update la_obra_v2.users set name = v_name, username = v_username, email = v_email, updated_at = localtimestamp where id = u.id;
  return la_obra_v2.ok(200, 'Perfil actualizado correctamente', jsonb_build_object('user', jsonb_build_object('id', u.id,
    'name', v_name, 'username', v_username, 'email', v_email, 'role', u.role, 'status', u.status, 'avatar_path', u.avatar_path)));
end $$;

-- auth/avatar.php · foto de perfil del usuario que inició sesión
--   POST {image: data URL} → la guarda (reemplaza la anterior) · DELETE → la quita
create or replace function la_obra_v2.ep_auth__avatar(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_path text;
begin
  if m not in ('POST', 'DELETE') then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
  u := la_obra_v2.auth_long(t);
  if m = 'POST' then
    v_path := la_obra_v2.save_image(la_obra_v2.body(b) -> 'image', 'avatars', 'u' || u.id);
  end if;
  update la_obra_v2.users set avatar_path = v_path, updated_at = localtimestamp where id = u.id;
  perform la_obra_v2.delete_file(u.avatar_path, 'avatars');
  return la_obra_v2.ok(200, case when m = 'POST' then 'Foto de perfil actualizada' else 'Foto de perfil eliminada' end,
    jsonb_build_object('avatar_path', v_path));
end $$;

-- auth/password.php
create or replace function la_obra_v2.ep_auth__password(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_cur text; v_new text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_long(t);
  v_cur := coalesce(la_obra_v2.jtext(b -> 'current_password'), '');
  v_new := coalesce(la_obra_v2.jtext(b -> 'new_password'), '');
  if v_cur = '' or v_new = '' then perform la_obra_v2.fail(422, 'La contraseña actual y la nueva contraseña son obligatorias'); end if;
  if octet_length(v_new) < 8 then perform la_obra_v2.fail(422, 'La nueva contraseña debe tener al menos 8 caracteres'); end if;
  if not la_obra_v2.check_password(v_cur, u.password_hash) then perform la_obra_v2.fail(401, 'La contraseña actual es incorrecta'); end if;
  update la_obra_v2.users set password_hash = la_obra_v2.hash_password(v_new), must_change_password = false, updated_at = localtimestamp where id = u.id;
  return la_obra_v2.ok(200, 'Contraseña actualizada correctamente');
end $$;

-- auth/register.php (cuenta pendiente de aprobación)
create or replace function la_obra_v2.ep_auth__register(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text; v_username text; v_email text; v_pass text;
begin
  perform la_obra_v2.method(m, 'POST');
  v_name := la_obra_v2.jstr(b -> 'name'); v_username := la_obra_v2.jstr(b -> 'username');
  v_email := la_obra_v2.jstr(b -> 'email'); v_pass := coalesce(la_obra_v2.jtext(b -> 'password'), '');
  if v_name = '' or v_username = '' or v_email = '' or v_pass = '' then perform la_obra_v2.fail(422, 'Todos los campos son obligatorios'); end if;
  if not la_obra_v2.valid_email(v_email) then perform la_obra_v2.fail(422, 'El correo electrónico no es válido'); end if;
  if octet_length(v_pass) < 8 then perform la_obra_v2.fail(422, 'La contraseña debe tener al menos 8 caracteres'); end if;
  if exists(select 1 from la_obra_v2.users where username = v_username or email = v_email) then
    perform la_obra_v2.fail(409, 'El nombre de usuario o correo ya está registrado');
  end if;
  insert into la_obra_v2.users(name, username, email, password_hash, status, role, must_change_password)
  values (v_name, v_username, v_email, la_obra_v2.hash_password(v_pass), 'pending', null, false);
  return la_obra_v2.ok(201, 'Registro realizado correctamente. Tu cuenta está pendiente de aprobación.');
end $$;

-- users/index.php
create or replace function la_obra_v2.ep_users__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_status text := la_obra_v2.jstr(q -> 'status');
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true, 'No tienes permisos para consultar usuarios');
  if v_status <> '' and v_status not in ('pending','active','rejected','inactive') then perform la_obra_v2.fail(422, 'El estado no es válido'); end if;
  return la_obra_v2.ok(200, 'Usuarios consultados', jsonb_build_object('users', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'username', username, 'email', email, 'status', status, 'role', role,
             'avatar_path', avatar_path) order by id), '[]')
      from la_obra_v2.users where v_status = '' or status = v_status)));
end $$;

-- users/show.php
create or replace function la_obra_v2.ep_users__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true, 'No tienes permisos para consultar usuarios');
  v_id := la_obra_v2.positive_id(q -> 'id', 'El id del usuario no es válido');
  select jsonb_build_object('id', id, 'name', name, 'username', username, 'email', email, 'status', status, 'role', role)
    into r from la_obra_v2.users where id = v_id;
  if r is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  return la_obra_v2.ok(200, 'Usuario', jsonb_build_object('user', r));
end $$;

-- users/create.php (admin crea cuenta con contraseña temporal)
create or replace function la_obra_v2.ep_users__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text; v_username text; v_email text; v_role text; v_tmp text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  v_name := la_obra_v2.jstr(b -> 'name'); v_username := la_obra_v2.jstr(b -> 'username');
  v_email := la_obra_v2.jstr(b -> 'email'); v_role := la_obra_v2.jstr(b -> 'role');
  if v_name = '' or v_username = '' or v_email = '' or v_role = '' then perform la_obra_v2.fail(422, 'Todos los campos son obligatorios'); end if;
  if not la_obra_v2.valid_email(v_email) then perform la_obra_v2.fail(422, 'El correo electrónico no es válido'); end if;
  if v_role not in ('admin','employee') then perform la_obra_v2.fail(422, 'El rol no es válido'); end if;
  if exists(select 1 from la_obra_v2.users where username = v_username or email = v_email) then
    perform la_obra_v2.fail(409, 'El nombre de usuario o correo ya está registrado');
  end if;
  v_tmp := encode(extensions.gen_random_bytes(5), 'hex');
  insert into la_obra_v2.users(name, username, email, password_hash, status, role, must_change_password)
  values (v_name, v_username, v_email, la_obra_v2.hash_password(v_tmp), 'active', v_role, true) returning id into v_id;
  return la_obra_v2.ok(201, 'Usuario creado correctamente', jsonb_build_object(
    'user', jsonb_build_object('id', v_id, 'name', v_name, 'username', v_username, 'email', v_email, 'role', v_role, 'status', 'active', 'must_change_password', true),
    'temporary_password', v_tmp));
end $$;

-- users/update.php?id=N (estado y/o rol; conserva al menos un admin activo)
create or replace function la_obra_v2.ep_users__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; u la_obra_v2.users; v_status text; v_role text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true, 'No tienes permisos para modificar usuarios');
  v_id := la_obra_v2.positive_id(q -> 'id', 'El id del usuario no es válido');
  select * into u from la_obra_v2.users where id = v_id;
  if u.id is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  if b is null or jsonb_typeof(b) <> 'object' then perform la_obra_v2.fail(422, 'Los datos enviados no son válidos'); end if;
  if not (b ? 'status') and not (b ? 'role') then perform la_obra_v2.fail(422, 'Debes proporcionar status, role o ambos'); end if;
  v_status := u.status; v_role := u.role;
  if b ? 'status' then
    v_status := la_obra_v2.jstr(b -> 'status');
    if v_status not in ('pending','active','rejected','inactive') then perform la_obra_v2.fail(422, 'El estado no es válido'); end if;
  end if;
  if b ? 'role' then
    v_role := la_obra_v2.jstr(b -> 'role');
    if v_role not in ('admin','employee') then perform la_obra_v2.fail(422, 'El rol no es válido'); end if;
  end if;
  if v_status = 'active' and coalesce(v_role, '') = '' then perform la_obra_v2.fail(422, 'Para activar la cuenta debes asignar un rol'); end if;
  if u.role = 'admin' and (v_role is distinct from 'admin' or v_status <> 'active') then
    if not exists(select 1 from la_obra_v2.users where role = 'admin' and status = 'active' and id <> v_id) then
      perform la_obra_v2.fail(422, 'No se puede realizar el cambio porque el sistema debe conservar al menos un administrador activo');
    end if;
  end if;
  update la_obra_v2.users set status = v_status, role = v_role, updated_at = localtimestamp where id = v_id;
  return la_obra_v2.ok(200, 'Usuario actualizado correctamente', jsonb_build_object('user', jsonb_build_object(
    'id', u.id, 'name', u.name, 'username', u.username, 'email', u.email, 'status', v_status, 'role', v_role)));
end $$;

-- users/employee-status.php
create or replace function la_obra_v2.ep_users__employee_status(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text; u la_obra_v2.users;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_status := la_obra_v2.jtext(b -> 'status');
  if (b -> 'status') is null or jsonb_typeof(b -> 'status') <> 'string' or v_status not in ('active','inactive') then
    perform la_obra_v2.fail(422, 'El estado debe ser active o inactive');
  end if;
  select * into u from la_obra_v2.users where id = v_id;
  if u.id is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  if u.role is distinct from 'employee' then perform la_obra_v2.fail(403, 'Solo se permite modificar el estado de empleados'); end if;
  if u.status not in ('pending','active','inactive') then perform la_obra_v2.fail(409, 'El estado actual de la cuenta no permite esta operación'); end if;
  if u.status = v_status then
    return la_obra_v2.ok(200, 'La cuenta ya tiene ese estado', jsonb_build_object('user', jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role, 'status', u.status)));
  end if;
  update la_obra_v2.users set status = v_status, updated_at = localtimestamp where id = v_id;
  return la_obra_v2.ok(200, 'Estado del empleado actualizado', jsonb_build_object('user', jsonb_build_object(
    'id', u.id, 'name', u.name, 'username', u.username, 'email', u.email, 'status', v_status, 'role', u.role)));
end $$;
