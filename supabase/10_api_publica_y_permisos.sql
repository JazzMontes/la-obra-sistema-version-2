-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 10 · Puerta de entrada pública, permisos y datos iniciales
--
-- La app (web en GitHub Pages y APK) llama SIEMPRE a una sola función:
--   POST https://<proyecto>.supabase.co/rest/v1/rpc/la_obra_v2_api
--   { "p_path": "products/index.php", "p_method": "GET",
--     "p_query": {...}, "p_body": {...}, "p_token": "<token de sesión>" }
-- y esta función ejecuta el "endpoint" equivalente al archivo PHP.
-- Las tablas NO son accesibles directamente desde internet.
-- =====================================================================

create or replace function public.la_obra_v2_api(
  p_path   text,
  p_method text  default 'GET',
  p_query  jsonb default '{}'::jsonb,
  p_body   jsonb default '{}'::jsonb,
  p_token  text  default null
) returns jsonb
language plpgsql
security definer
set search_path = la_obra_v2, extensions, public, pg_temp
as $$
declare
  v_path text := lower(btrim(coalesce(p_path, '')));
  fn text;
  r jsonb;
begin
  v_path := split_part(regexp_replace(v_path, '^/+', ''), '?', 1);
  if v_path !~ '^[a-z0-9_-]+(/[a-z0-9_-]+)?(\.php)?$' then
    perform la_obra_v2.fail(404, 'Ruta no encontrada: ' || coalesce(p_path, ''));
  end if;
  v_path := regexp_replace(v_path, '\.php$', '');
  fn := 'ep_' || replace(replace(v_path, '/', '__'), '-', '_');
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'la_obra_v2' and p.proname = fn) then
    perform la_obra_v2.fail(404, 'Ruta no encontrada: ' || p_path);
  end if;
  execute format('select la_obra_v2.%I($1, $2, $3, $4)', fn)
    into r
    using upper(coalesce(p_method, 'GET')),
          case when jsonb_typeof(p_query) = 'object' then p_query else '{}'::jsonb end,
          case when p_body is null or jsonb_typeof(p_body) = 'null' then '{}'::jsonb else p_body end,
          p_token;
  return la_obra_v2.fix_ts(r);
end $$;

comment on function public.la_obra_v2_api(text, text, jsonb, jsonb, text) is
  'La Obra v2: única entrada de la app. Equivale a la carpeta backend/ de PHP.';

-- Crear el primer administrador (solo funciona si todavía no hay ninguno)
create or replace function la_obra_v2.crear_admin_inicial(p_name text, p_username text, p_email text, p_password text)
returns text language plpgsql as $$
begin
  if exists (select 1 from la_obra_v2.users where role = 'admin' and status = 'active') then
    return 'Ya existe un administrador activo; no se creó otro.';
  end if;
  if octet_length(coalesce(p_password, '')) < 8 then
    return 'La contraseña debe tener al menos 8 caracteres.';
  end if;
  insert into la_obra_v2.users(name, username, email, password_hash, status, role, must_change_password)
  values (btrim(p_name), btrim(p_username), btrim(p_email), la_obra_v2.hash_password(p_password), 'active', 'admin', false);
  return 'Administrador creado: ' || btrim(p_username);
end $$;

-- ---------------------------------------------------------------------
-- PERMISOS: nada del esquema la_obra_v2 es visible desde la API;
-- solo se puede ejecutar public.la_obra_v2_api.
-- ---------------------------------------------------------------------
revoke all on schema la_obra_v2 from public;
revoke all on all tables    in schema la_obra_v2 from public;
revoke all on all sequences in schema la_obra_v2 from public;
revoke all on all functions in schema la_obra_v2 from public;
alter default privileges in schema la_obra_v2 revoke all on tables from public;
alter default privileges in schema la_obra_v2 revoke all on functions from public;

do $$
declare
  t record;
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on schema la_obra_v2 from %I', r);
      execute format('revoke all on all tables in schema la_obra_v2 from %I', r);
      execute format('revoke all on all sequences in schema la_obra_v2 from %I', r);
      execute format('revoke all on all functions in schema la_obra_v2 from %I', r);
    end if;
  end loop;
  -- Seguridad a nivel de fila activada y sin políticas: nadie entra directo a las tablas
  for t in select tablename from pg_tables where schemaname = 'la_obra_v2' loop
    execute format('alter table la_obra_v2.%I enable row level security', t.tablename);
  end loop;
end $$;

revoke all on function public.la_obra_v2_api(text, text, jsonb, jsonb, text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.la_obra_v2_api(text, text, jsonb, jsonb, text) to anon;
    -- Las peticiones de la app llegan como "anon"; Supabase les da 3 s por defecto.
    -- Los reportes y la factura de prueba pueden tardar más.
    alter role anon set statement_timeout = '20s';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.la_obra_v2_api(text, text, jsonb, jsonb, text) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.la_obra_v2_api(text, text, jsonb, jsonb, text) to service_role;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- DATOS INICIALES
-- ---------------------------------------------------------------------
insert into la_obra_v2.payment_methods(name, status)
select v.name, 'active' from (values ('Efectivo'), ('Transferencia'), ('Tarjeta')) v(name)
where not exists (select 1 from la_obra_v2.payment_methods pm where lower(pm.name) = lower(v.name));

-- Configuración de prueba de Profact (la misma de invoices/config.php)
insert into la_obra_v2.meta(key, value) values ('profact_config', jsonb_build_object(
  'token', 'mvpNUXmQfK8=',
  'postal_code', '32690',
  'issuer', jsonb_build_object('Rfc', 'IIA040805DZ4', 'Nombre', 'INDISTRIA ILUMINADORA DE ALMACENES', 'RegimenFiscal', '626'),
  'receiver', jsonb_build_object('Rfc', 'EKU9003173C9', 'Nombre', 'ESCUELA KEMPER URGATE', 'DomicilioFiscalReceptor', '42501',
                                 'RegimenFiscalReceptor', '603', 'UsoCFDI', 'G03'))::text)
on conflict (key) do nothing;

-- Avisar a la API de Supabase que hay una función nueva
notify pgrst, 'reload schema';
notify pgrst, 'reload config';
