-- =====================================================================
-- La Obra v2 · 10 · Función pública y permisos
-- La app SOLO puede llamar a public.la_obra_v2_api(...). Cada ruta de la v1
-- ("products/index.php") se ejecuta con la función la_obra_v2.ep_products__index.
-- =====================================================================
set check_function_bodies = off;

-- health.php (no requiere sesión)
create or replace function la_obra_v2.ep_health(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  return la_obra_v2.ok(200, 'API disponible', jsonb_build_object(
    'server_time', to_char(now() at time zone 'America/Mexico_City', 'YYYY-MM-DD"T"HH24:MI:SS') || '-06:00',
    'database_ok', true, 'missing', '[]'::jsonb, 'run_migrations', '[]'::jsonb, 'backend', 'supabase'));
end $$;

create or replace function public.la_obra_v2_api(
  path   text,
  method text  default 'GET',
  query  jsonb default '{}'::jsonb,
  body   jsonb default null,
  token  text  default null
) returns jsonb
language plpgsql
security definer
set search_path = la_obra_v2, public, extensions
set timezone = 'America/Mexico_City'
as $$
declare
  p  text := lower(regexp_replace(btrim(coalesce(path, '')), '^/+', ''));
  fn text;
  r  jsonb;
  st text; msg text;
begin
  p := regexp_replace(p, '\?.*$', '');
  if p = 'health.php' or p = 'health' then
    fn := 'ep_health';
  elsif p ~ '^[a-z][a-z-]*/[a-z][a-z-]*(\.php)?$' then
    fn := 'ep_' || replace(replace(regexp_replace(p, '\.php$', ''), '-', '_'), '/', '__');
  else
    return jsonb_build_object('status', 404, 'body', jsonb_build_object('success', false, 'message', 'Ruta no encontrada: ' || coalesce(path, '')));
  end if;

  if not exists (select 1 from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
                  where n.nspname = 'la_obra_v2' and pr.proname = fn) then
    return jsonb_build_object('status', 404, 'body', jsonb_build_object('success', false, 'message', 'Ruta no encontrada: ' || p));
  end if;

  -- Planes y créditos (13_planes_y_creditos.sql): si el negocio no tiene vigente la función
  -- a la que pertenece esta ruta, se responde 402 sin ejecutarla.
  perform set_config('la_obra_v2.in_api', 'on', true);
  if to_regproc('la_obra_v2.billing_gate') is not null then
    execute 'select la_obra_v2.billing_gate($1, $2)' into r using p, token;
    if r is not null then return r; end if;
  end if;

  begin
    execute format('select la_obra_v2.%I($1, $2, $3, $4)', fn)
      into r using upper(coalesce(method, 'GET')), coalesce(query, '{}'::jsonb), body, token;
    return la_obra_v2.fix_dates(r);
  exception
    when sqlstate 'LO001' then
      return la_obra_v2.fix_dates(sqlerrm::jsonb);
    when others then
      get stacked diagnostics st = returned_sqlstate, msg = message_text;
      raise log 'la_obra_v2_api % %: % %', method, p, st, msg;
      return jsonb_build_object('status', 500, 'body', jsonb_build_object('success', false,
        'message', 'No se pudo completar la operación', 'detail', st || ': ' || left(msg, 300)));
  end;
end $$;

-- Crear el primer administrador desde el SQL Editor de Supabase
create or replace function la_obra_v2.crear_admin_inicial(p_name text, p_username text, p_email text, p_password text)
returns text language plpgsql as $$
begin
  if length(coalesce(p_password, '')) < 8 then raise exception 'La contraseña debe tener al menos 8 caracteres'; end if;
  insert into la_obra_v2.users(name, username, email, password_hash, status, role, must_change_password)
  values (p_name, p_username, p_email, la_obra_v2.hash_password(p_password), 'active', 'admin', false)
  on conflict (username) do update set password_hash = excluded.password_hash, status = 'active', role = 'admin', name = excluded.name, email = excluded.email;
  return 'Administrador listo: ' || p_username;
end $$;

-- ---------- Permisos ----------
-- Nadie (ni anon ni authenticated) puede usar el esquema privado directamente.
revoke all on schema la_obra_v2 from public;
revoke all on all tables in schema la_obra_v2 from public;
revoke all on all functions in schema la_obra_v2 from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all tables in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all functions in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all sequences in schema la_obra_v2 from anon, authenticated';
    execute 'alter default privileges in schema la_obra_v2 revoke all on tables from anon, authenticated';
    execute 'alter default privileges in schema la_obra_v2 revoke all on functions from anon, authenticated';
  end if;
end $$;

-- Solo la función pública se puede llamar con la clave pública
revoke all on function public.la_obra_v2_api(text, text, jsonb, jsonb, text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function public.la_obra_v2_api(text, text, jsonb, jsonb, text) to anon, authenticated';
  end if;
end $$;

-- Supabase limita a 3 s cada consulta de la clave pública; los respaldos con fotos tardan más
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'alter role anon set statement_timeout = ''60s''';
  end if;
end $$;

-- Que la API de Supabase vea la función nueva y el nuevo límite sin esperar
notify pgrst, 'reload schema';
notify pgrst, 'reload config';
