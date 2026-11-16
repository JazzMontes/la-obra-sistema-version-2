-- =====================================================================
-- La Obra v2 · 09d · Respaldo y restauración (backup/export, backup/import)
-- El plan gratuito de Supabase no da respaldos descargables: el administrador
-- descarga un JSON con todo desde la pantalla "Servidor" y lo puede restaurar.
-- =====================================================================
set check_function_bodies = off;

-- Tablas en orden de dependencias (para insertar; se borran al revés)
create or replace function la_obra_v2.backup_tables()
returns text[] language sql immutable as $$
  select array['users','sessions','categories','payment_methods','inputs','products','preparations','preparation_inputs',
               'recipes','product_components','orders','order_items','payments','purchases','purchase_items','purchase_history',
               'expenses','expense_history','waste_records','inventory_movements','order_test_invoices','work_location','attendance'];
$$;

create or replace function la_obra_v2.ep_backup__export(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare tb text; v_rows jsonb; v_tables jsonb := '{}'; v_files jsonb := '[]';
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  foreach tb in array la_obra_v2.backup_tables() loop
    if tb = 'sessions' then continue; end if;  -- las sesiones no se respaldan
    execute format('select coalesce(jsonb_agg(to_jsonb(x) order by %s), ''[]'') from la_obra_v2.%I x',
                   case when tb = 'order_test_invoices' then 'x.order_id' else 'x.id' end, tb) into v_rows;
    v_tables := v_tables || jsonb_build_object(tb, v_rows);
  end loop;
  if coalesce(la_obra_v2.jtext(q -> 'files'), '1') not in ('0', 'false', '') then
    select coalesce(jsonb_agg(jsonb_build_object('path', path, 'mime', mime, 'data', replace(encode(data, 'base64'), E'\n', ''), 'created_at', created_at) order by path), '[]')
      into v_files from la_obra_v2.files;
  end if;
  return la_obra_v2.ok(200, 'Respaldo generado', jsonb_build_object('backup', jsonb_build_object(
    'format', 'la-obra-v2-backup', 'version', 1, 'created_at', la_obra_v2.fmt_ts(localtimestamp),
    'tables', v_tables, 'files', v_files, 'includes_files', jsonb_array_length(v_files) > 0)));
end $$;

create or replace function la_obra_v2.ep_backup__import(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; bk jsonb; tb text; v_n int; v_total int := 0; seq text; v_admins int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  bk := la_obra_v2.body(b) -> 'backup';
  if bk is null or bk ->> 'format' is distinct from 'la-obra-v2-backup' or jsonb_typeof(bk -> 'tables') <> 'object' then
    perform la_obra_v2.fail(422, 'El archivo no es un respaldo de La Obra v2');
  end if;
  select count(*) into v_admins from jsonb_array_elements(coalesce(bk #> '{tables,users}', '[]')) x where x ->> 'role' = 'admin' and x ->> 'status' = 'active';
  if v_admins = 0 then perform la_obra_v2.fail(422, 'El respaldo no tiene ningún administrador activo; no se restauró para que no pierdas el acceso'); end if;

  execute 'truncate ' || (select string_agg(format('la_obra_v2.%I', x), ', ') from unnest(la_obra_v2.backup_tables()) x) || ' restart identity cascade';
  foreach tb in array la_obra_v2.backup_tables() loop
    if tb = 'sessions' or jsonb_typeof(bk -> 'tables' -> tb) is distinct from 'array' then continue; end if;
    execute format('insert into la_obra_v2.%I select * from jsonb_populate_recordset(null::la_obra_v2.%I, $1)', tb, tb) using bk -> 'tables' -> tb;
    get diagnostics v_n = row_count;
    v_total := v_total + v_n;
    seq := case when exists(select 1 from information_schema.columns where table_schema = 'la_obra_v2' and table_name = tb and column_name = 'id')
                then pg_get_serial_sequence(format('la_obra_v2.%I', tb), 'id') end;
    if seq is not null then
      execute format('select setval(%L, greatest(coalesce((select max(id) from la_obra_v2.%I), 0), 1), (select count(*) > 0 from la_obra_v2.%I))', seq, tb, tb);
    end if;
  end loop;
  if jsonb_typeof(bk -> 'files') = 'array' and jsonb_array_length(bk -> 'files') > 0 then
    delete from la_obra_v2.files;
    insert into la_obra_v2.files(path, mime, data, created_at)
    select f ->> 'path', f ->> 'mime', decode(f ->> 'data', 'base64'), coalesce((f ->> 'created_at')::timestamp, localtimestamp)
      from jsonb_array_elements(bk -> 'files') f;
  end if;
  return la_obra_v2.ok(200, 'Respaldo restaurado: ' || v_total || ' registros. Vuelve a iniciar sesión.');
end $$;
