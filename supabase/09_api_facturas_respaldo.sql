-- =====================================================================
-- LA OBRA · SISTEMA VERSIÓN 2
-- 09 · API: factura de prueba (invoices/order.php) y respaldo (backup/, NUEVO)
-- =====================================================================

-- ---------------------------------------------------------------------
-- FACTURA DE PRUEBA CON PROFACT QA (antes invoices/cfdi.php + order.php)
-- Necesita la extensión "http" de Supabase (Database → Extensions → http).
-- Los datos del emisor/receptor de prueba están en la_obra_v2.meta
-- (clave profact_config); se pueden cambiar con un UPDATE.
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.xml_attr(v text)
returns text language sql immutable as $$
  select replace(replace(replace(replace(replace(coalesce(v, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&apos;')
$$;

create or replace function la_obra_v2.xml_node(p_name text, p_attrs jsonb, p_children text default null)
returns text language sql immutable as $$
  select '<cfdi:' || p_name
         || coalesce((select string_agg(' ' || key || '="' || la_obra_v2.xml_attr(value) || '"', '' order by o)
                      from jsonb_each_text(p_attrs) with ordinality e(key, value, o)), '')
         || case when p_children is null then '/>' else '>' || p_children || '</cfdi:' || p_name || '>' end
$$;

-- Genera el XML del CFDI 4.0 (subtotal e IVA 16% a partir del total en centavos)
create or replace function la_obra_v2.invoice_xml(p_config jsonb, p_folio text, p_cents bigint, p_payment text, p_order_id integer)
returns text language plpgsql stable as $$
declare
  v_base bigint := round(p_cents / 1.16);
  v_tax bigint := p_cents - round(p_cents / 1.16);
  v_concept numeric := round(p_cents / 116.0, 6);
  v_concept_txt text := to_char(round(p_cents / 116.0, 6), 'FM9999999990.000000');
  dec_base text := to_char(round(p_cents / 1.16) / 100.0, 'FM9999999990.00');
  dec_tax text := to_char((p_cents - round(p_cents / 1.16)) / 100.0, 'FM9999999990.00');
  dec_total text := to_char(p_cents / 100.0, 'FM9999999990.00');
  transfer_attrs text;
  concept text;
  body text;
begin
  transfer_attrs := '';
  concept := la_obra_v2.xml_node('Concepto', jsonb_build_object(
      'ClaveProdServ', '90101500', 'Cantidad', '1', 'ClaveUnidad', 'E48',
      'Descripcion', 'Consumo de alimentos - pedido ' || p_order_id,
      'ValorUnitario', v_concept_txt, 'Importe', v_concept_txt, 'ObjetoImp', '02'),
    la_obra_v2.xml_node('Impuestos', '{}'::jsonb,
      la_obra_v2.xml_node('Traslados', '{}'::jsonb,
        la_obra_v2.xml_node('Traslado', jsonb_build_object(
          'Base', v_concept_txt, 'Impuesto', '002', 'TipoFactor', 'Tasa', 'TasaOCuota', '0.160000',
          'Importe', to_char(round(v_concept * 0.16, 6), 'FM9999999990.000000'))))));
  body := la_obra_v2.xml_node('Emisor', p_config -> 'issuer')
       || la_obra_v2.xml_node('Receptor', p_config -> 'receiver')
       || la_obra_v2.xml_node('Conceptos', '{}'::jsonb, concept)
       || la_obra_v2.xml_node('Impuestos', jsonb_build_object('TotalImpuestosTrasladados', dec_tax),
            la_obra_v2.xml_node('Traslados', '{}'::jsonb,
              la_obra_v2.xml_node('Traslado', jsonb_build_object(
                'Base', dec_base, 'Impuesto', '002', 'TipoFactor', 'Tasa', 'TasaOCuota', '0.160000', 'Importe', dec_tax))));
  return '<?xml version="1.0" encoding="UTF-8"?>' || chr(10)
    || '<cfdi:Comprobante xmlns:cfdi="http://www.sat.gob.mx/cfd/4" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    || ' Version="4.0" Serie="QA" Folio="' || la_obra_v2.xml_attr(p_folio) || '"'
    || ' Fecha="' || to_char(la_obra_v2.now_mx(), 'YYYY-MM-DD"T"HH24:MI:SS') || '"'
    || ' FormaPago="' || la_obra_v2.xml_attr(p_payment) || '"'
    || ' SubTotal="' || dec_base || '" Moneda="MXN" Total="' || dec_total || '"'
    || ' TipoDeComprobante="I" Exportacion="01" MetodoPago="PUE"'
    || ' LugarExpedicion="' || la_obra_v2.xml_attr(p_config ->> 'postal_code') || '"'
    || ' xsi:schemaLocation="http://www.sat.gob.mx/cfd/4 http://www.sat.gob.mx/sitio_internet/cfd/4/cfdv40.xsd">'
    || body || '</cfdi:Comprobante>' || chr(10);
end $$;

-- Comprueba que el XML recibido tenga timbre fiscal válido y devuelve su UUID
create or replace function la_obra_v2.parse_stamped_xml(p_xml text, p_folio text)
returns text language plpgsql immutable as $$
declare
  x xml;
  ns text[] := array[array['cfdi', 'http://www.sat.gob.mx/cfd/4'], array['tfd', 'http://www.sat.gob.mx/TimbreFiscalDigital']];
  folio text;
  v_uuid text;
begin
  if p_xml is null or p_xml = '' or p_xml ilike '%<!DOCTYPE%' then return null; end if;
  begin
    x := xmlparse(document regexp_replace(replace(p_xml, chr(65279), ''), '^\s*<\?xml[^>]*\?>', ''));
  exception when others then
    return null;
  end;
  folio := (xpath('/cfdi:Comprobante/@Folio', x, ns))[1]::text;
  if folio is distinct from p_folio then return null; end if;
  v_uuid := (xpath('//tfd:TimbreFiscalDigital/@UUID', x, ns))[1]::text;
  if v_uuid ~* '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' then return v_uuid; end if;
  return null;
end $$;

-- Llama a la API de pruebas de Profact. Devuelve {status, response}
create or replace function la_obra_v2.profact_qa(p_operation text, p_token text, p_payload jsonb)
returns jsonb language plpgsql as $$
declare
  st integer;
  body text;
  parsed jsonb;
begin
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '25');
    perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT', '8');
    select r.status, r.content into st, body
    from extensions.http((
      'POST',
      'https://pruebas.timbracfdi33.mx:1444/api/v2/Timbrado/' || p_operation,
      array[extensions.http_header('Authorization', 'Bearer ' || p_token), extensions.http_header('Accept', 'application/json')],
      'application/json',
      p_payload::text)::extensions.http_request) r;
  exception
    when undefined_function or invalid_schema_name or undefined_object then
      perform la_obra_v2.fail(503, 'Activa la extensión "http" en Supabase (Database → Extensions → http) para facturar.');
    when others then
      return jsonb_build_object('status', 0, 'response', null, 'error', sqlerrm);
  end;
  begin
    parsed := body::jsonb;
  exception when others then
    parsed := null;
  end;
  return jsonb_build_object('status', st, 'response', parsed);
end $$;

-- invoices/order.php — GET consulta el CFDI de prueba, POST solicita el timbrado
create or replace function la_obra_v2.ep_invoices__order(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  actor la_obra_v2.users;
  oid integer;
  o record;
  inv la_obra_v2.order_test_invoices;
  v_name text;
  v_code text;
  v_card text;
  cfg jsonb;
  req_id text;
  v_xml text;
  call jsonb;
  resp jsonb;
  st integer;
  prev text[];
  stamped text;
  v_uuid text;
  detail text;
begin
  if upper(m) not in ('GET', 'POST') then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
  actor := la_obra_v2.auth_user(tok);
  oid := la_obra_v2.pos_id(case when upper(m) = 'GET' then q -> 'id' else b -> 'order_id' end);

  select o2.*, p.amount, pm.name as payment_name into o
  from la_obra_v2.orders o2
  left join la_obra_v2.payments p on p.order_id = o2.id
  left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
  where o2.id = oid;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;

  -- Quien no es admin solo puede acceder a sus propios pedidos del día
  if actor.role <> 'admin' and (o.user_id <> actor.id or o.created_at::date <> la_obra_v2.today_mx()) then
    perform la_obra_v2.fail(403, 'Solo puedes facturar tus pedidos del día');
  end if;

  select * into inv from la_obra_v2.order_test_invoices where order_id = oid;
  if inv.uuid is not null then
    return la_obra_v2.ok('CFDI de prueba disponible', jsonb_build_object('invoice', jsonb_build_object('uuid', inv.uuid, 'xml', inv.stamped_xml)));
  end if;
  if upper(m) = 'GET' then return la_obra_v2.ok('Sin CFDI de prueba', jsonb_build_object('invoice', null)); end if;

  if o.order_status <> 'confirmed' or o.payment_status <> 'paid' or o.total <= 0 or o.total is distinct from o.amount then
    perform la_obra_v2.fail(409, 'El pedido debe estar confirmado y pagado por completo');
  end if;

  -- Forma de pago para el SAT
  v_name := lower(btrim(coalesce(o.payment_name, '')));
  v_code := case v_name
    when 'efectivo' then '01' when 'transferencia' then '03' when 'transferencia electrónica' then '03'
    when 'tarjeta de crédito' then '04' when 'tarjeta crédito' then '04'
    when 'tarjeta de débito' then '28' when 'tarjeta débito' then '28' else null end;
  if v_code is null and position('tarjeta' in v_name) > 0 then
    v_card := b ->> 'card_type';
    if v_card = 'credit' then v_code := '04';
    elsif v_card = 'debit' then v_code := '28';
    elsif inv.order_id is null then
      perform la_obra_v2.fail(422, 'Indica si la tarjeta fue de crédito o débito para la factura', jsonb_build_object('needs_card_type', true));
    end if;
  end if;
  if inv.order_id is null and v_code is null then
    perform la_obra_v2.fail(422, 'Esta forma de pago no se puede facturar en la prueba. Usa efectivo, transferencia o tarjeta.');
  end if;

  cfg := (select value::jsonb from la_obra_v2.meta where key = 'profact_config');
  if cfg is null then perform la_obra_v2.fail(503, 'Falta la configuración de Profact (la_obra_v2.meta → profact_config)'); end if;

  -- Evita que dos solicitudes intenten timbrar el mismo pedido al mismo tiempo
  if not pg_try_advisory_xact_lock(hashtext('laobra:cfdi:qa:' || oid)) then
    perform la_obra_v2.fail(409, 'Ya hay una solicitud de timbrado para este pedido');
  end if;

  -- Guarda el XML y el ID de la solicitud para reutilizarlos si hay un reintento
  if inv.order_id is null then
    req_id := encode(extensions.gen_random_bytes(16), 'hex');
    v_xml := la_obra_v2.invoice_xml(cfg, req_id, round(o.total * 100)::bigint, v_code, oid);
    insert into la_obra_v2.order_test_invoices(order_id, request_id, request_xml) values (oid, req_id, v_xml);
    select * into inv from la_obra_v2.order_test_invoices where order_id = oid;
  end if;

  call := la_obra_v2.profact_qa('TimbraCFDI', cfg ->> 'token', jsonb_build_object(
    'XmlComprobanteBase64', replace(encode(convert_to(inv.request_xml, 'UTF8'), 'base64'), E'\n', ''),
    'IdComprobante', inv.request_id));
  if (call ->> 'status')::integer = 0 then
    -- Sin respuesta: se confirma lo guardado para reintentar con el mismo XML
    return jsonb_build_object('success', false, 'status', 502,
      'message', 'No se recibió respuesta de Profact QA. Al reintentar se usará el mismo XML.');
  end if;
  st := (call ->> 'status')::integer;
  resp := call -> 'response';

  -- Si Profact indica que ya se timbró, recupera el CFDI con su UUID
  if (resp ->> 'Codigo') = '25' then
    prev := regexp_match(coalesce(resp ->> 'Mensaje', ''), '[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}');
    if prev is not null then
      call := la_obra_v2.profact_qa('ObtieneCFDI', cfg ->> 'token', jsonb_build_object(
        'FolioFiscal', prev[1], 'RfcEmisor', cfg -> 'issuer' ->> 'Rfc'));
      st := (call ->> 'status')::integer;
      resp := call -> 'response';
    end if;
  end if;

  stamped := resp ->> 'Xml';
  if st = 200 and (resp ->> 'Codigo') = '0' and stamped is not null then
    v_uuid := la_obra_v2.parse_stamped_xml(stamped, inv.request_id);
  end if;
  if v_uuid is null then
    detail := coalesce(resp ->> 'Descripcion', resp ->> 'Mensaje', resp ->> 'message', '');
    return jsonb_build_object('success', false, 'status', 502, 'message',
      case when detail <> '' then 'Profact QA (HTTP ' || st || '): ' || left(detail, 400)
           else 'Profact QA (HTTP ' || st || ') no devolvió un XML timbrado para este pedido. Revisa el emisor y token de prueba.' end);
  end if;
  update la_obra_v2.order_test_invoices set uuid = v_uuid, stamped_xml = stamped where order_id = oid;
  return la_obra_v2.ok('CFDI de prueba timbrado', jsonb_build_object('invoice', jsonb_build_object('uuid', v_uuid, 'xml', stamped)));
end $$;

-- ---------------------------------------------------------------------
-- RESPALDO (NUEVO EN LA VERSIÓN 2)
-- backup/export: descarga TODA la información en un archivo JSON (solo admin)
-- backup/import: restaura un respaldo (borra lo actual; solo admin)
-- ---------------------------------------------------------------------
create or replace function la_obra_v2.backup_tables()
returns text[] language sql immutable as $$
  -- En orden de dependencias (padres primero)
  select array['users', 'categories', 'payment_methods', 'inputs', 'preparations', 'preparation_inputs', 'products',
               'recipes', 'product_components', 'orders', 'order_items', 'payments', 'purchases', 'purchase_items',
               'purchase_history', 'expenses', 'expense_history', 'waste_records', 'inventory_movements',
               'order_test_invoices', 'files']
$$;

-- Ajusta los contadores de id después de insertar registros con id explícito
create or replace function la_obra_v2.reset_sequences()
returns void language plpgsql as $$
declare
  t text;
  seq text;
  mx bigint;
begin
  foreach t in array la_obra_v2.backup_tables() loop
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'la_obra_v2' and table_name = t and column_name = 'id') then
      continue;
    end if;
    seq := pg_get_serial_sequence('la_obra_v2.' || t, 'id');
    if seq is null then continue; end if;
    execute format('select max(id) from la_obra_v2.%I', t) into mx;
    perform setval(seq, coalesce(mx, 1), mx is not null);
  end loop;
  seq := pg_get_serial_sequence('la_obra_v2.sessions', 'id');
  execute 'select max(id) from la_obra_v2.sessions' into mx;
  perform setval(seq, coalesce(mx, 1), mx is not null);
end $$;

create or replace function la_obra_v2.ep_backup__export(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  t text;
  rows_j jsonb;
  tables jsonb := '{}'::jsonb;
  with_files boolean := coalesce(la_obra_v2.qp(q, 'files'), '1') <> '0';
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_user(tok, true);
  foreach t in array la_obra_v2.backup_tables() loop
    if t = 'files' then
      if not with_files then continue; end if;
      select coalesce(jsonb_agg(jsonb_build_object('path', path, 'mime', mime, 'size_bytes', size_bytes, 'created_at', created_at,
                                                   'data_base64', replace(encode(data, 'base64'), E'\n', '')) order by path), '[]'::jsonb)
      into rows_j from la_obra_v2.files;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.%I), ''[]''::jsonb) from la_obra_v2.%I x',
                     case when t = 'order_test_invoices' then 'order_id' else 'id' end, t)
      into rows_j;
    end if;
    tables := tables || jsonb_build_object(t, rows_j);
  end loop;
  return la_obra_v2.ok('Respaldo generado', jsonb_build_object('backup', jsonb_build_object(
    'app', 'la-obra-sistema-version-2',
    'schema_version', (select value from la_obra_v2.meta where key = 'schema_version'),
    'exported_at', la_obra_v2.now_mx(),
    'includes_files', with_files,
    'tables', tables)));
end $$;

create or replace function la_obra_v2.ep_backup__import(m text, q jsonb, b jsonb, tok text)
returns jsonb language plpgsql as $$
declare
  bk jsonb := b -> 'backup';
  t text;
  n integer;
  total integer := 0;
  keep_files boolean;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_user(tok, true);
  if la_obra_v2.jstr(b -> 'confirm') <> 'RESTAURAR' then
    perform la_obra_v2.fail(422, 'Escribe RESTAURAR para confirmar: se reemplazará toda la información actual');
  end if;
  if jsonb_typeof(bk) is distinct from 'object' or bk ->> 'app' is distinct from 'la-obra-sistema-version-2'
     or jsonb_typeof(bk -> 'tables') is distinct from 'object' or jsonb_typeof(bk -> 'tables' -> 'users') is distinct from 'array' then
    perform la_obra_v2.fail(422, 'El archivo no es un respaldo válido de La Obra v2');
  end if;
  if not exists (select 1 from jsonb_array_elements(bk -> 'tables' -> 'users') u
                 where u ->> 'role' = 'admin' and u ->> 'status' = 'active') then
    perform la_obra_v2.fail(422, 'El respaldo no tiene ningún administrador activo; no se puede restaurar');
  end if;
  -- Si el respaldo no trae fotos, se conservan las actuales
  keep_files := not (bk -> 'tables' ? 'files');

  if keep_files then
    truncate la_obra_v2.users, la_obra_v2.sessions, la_obra_v2.categories, la_obra_v2.payment_methods, la_obra_v2.inputs,
             la_obra_v2.preparations, la_obra_v2.preparation_inputs, la_obra_v2.products, la_obra_v2.recipes,
             la_obra_v2.product_components, la_obra_v2.orders, la_obra_v2.order_items, la_obra_v2.payments,
             la_obra_v2.purchases, la_obra_v2.purchase_items, la_obra_v2.purchase_history, la_obra_v2.expenses,
             la_obra_v2.expense_history, la_obra_v2.waste_records, la_obra_v2.inventory_movements,
             la_obra_v2.order_test_invoices cascade;
  else
    truncate la_obra_v2.users, la_obra_v2.sessions, la_obra_v2.categories, la_obra_v2.payment_methods, la_obra_v2.inputs,
             la_obra_v2.preparations, la_obra_v2.preparation_inputs, la_obra_v2.products, la_obra_v2.recipes,
             la_obra_v2.product_components, la_obra_v2.orders, la_obra_v2.order_items, la_obra_v2.payments,
             la_obra_v2.purchases, la_obra_v2.purchase_items, la_obra_v2.purchase_history, la_obra_v2.expenses,
             la_obra_v2.expense_history, la_obra_v2.waste_records, la_obra_v2.inventory_movements,
             la_obra_v2.order_test_invoices, la_obra_v2.files cascade;
  end if;

  foreach t in array la_obra_v2.backup_tables() loop
    if jsonb_typeof(bk -> 'tables' -> t) is distinct from 'array' then continue; end if;
    if t = 'files' then
      insert into la_obra_v2.files(path, mime, data, size_bytes, created_at)
      select f ->> 'path', f ->> 'mime', decode(f ->> 'data_base64', 'base64'),
             coalesce((f ->> 'size_bytes')::integer, length(decode(f ->> 'data_base64', 'base64'))),
             coalesce((f ->> 'created_at')::timestamp, la_obra_v2.now_mx())
      from jsonb_array_elements(bk -> 'tables' -> 'files') f;
    else
      execute format('insert into la_obra_v2.%I select * from jsonb_populate_recordset(null::la_obra_v2.%I, $1)', t, t)
      using bk -> 'tables' -> t;
    end if;
    get diagnostics n = row_count;
    total := total + n;
  end loop;
  perform la_obra_v2.reset_sequences();
  return la_obra_v2.ok('Respaldo restaurado: ' || total || ' registros. Vuelve a iniciar sesión.',
                       jsonb_build_object('restored_rows', total));
end $$;
