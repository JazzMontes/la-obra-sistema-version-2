-- =====================================================================
-- La Obra v2 · 09c · waste/*, invoices/order, attendance/*
-- =====================================================================
set check_function_bodies = off;

-- Sesión de los servicios de mermas (sus propios mensajes en la v1)
create or replace function la_obra_v2.waste_auth(p_token text, p_admin boolean default false)
returns la_obra_v2.users language plpgsql as $$
declare u la_obra_v2.users; v_exp timestamp;
begin
  if p_token is null or btrim(p_token) = '' or btrim(p_token) ~ '\s' then perform la_obra_v2.fail(401, 'Token de autenticación requerido'); end if;
  select us.* into u from la_obra_v2.sessions s join la_obra_v2.users us on us.id = s.user_id where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  select s.expires_at into v_exp from la_obra_v2.sessions s where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  if u.id is null then perform la_obra_v2.fail(401, 'Sesión inválida'); end if;
  if v_exp <= localtimestamp then perform la_obra_v2.fail(401, 'La sesión ha expirado'); end if;
  if u.status <> 'active' then perform la_obra_v2.fail(403, 'La cuenta no tiene acceso al sistema'); end if;
  if u.role is null or u.role not in ('admin','employee') then perform la_obra_v2.fail(403, 'No tienes acceso a este servicio'); end if;
  if u.must_change_password then perform la_obra_v2.fail(403, 'Debes cambiar tu contraseña antes de continuar'); end if;
  if p_admin and u.role <> 'admin' then perform la_obra_v2.fail(403, 'Solo el administrador puede consultar esta información'); end if;
  return u;
end $$;

create or replace function la_obra_v2.waste_date(q jsonb, k text)
returns date language plpgsql as $$
declare s text := la_obra_v2.jtext(q -> k); d date;
begin
  if (q -> k) is null or jsonb_typeof(q -> k) <> 'string' or s !~ '^\d{4}-\d{2}-\d{2}$' then perform la_obra_v2.fail(422, k || ': fecha inválida'); end if;
  begin d := s::date; exception when others then perform la_obra_v2.fail(422, k || ': fecha inválida'); end;
  return d;
end $$;

create or replace function la_obra_v2.waste_select(p_where text, p_args anyarray)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  execute 'select coalesce(jsonb_agg(to_jsonb(w) || jsonb_build_object(''affected_name'', coalesce(i.name, p.name, pr.name),
      ''affected_unit'', case when w.affected_type = ''input'' then i.unit end, ''user_name'', u.name) order by w.waste_date desc, w.id desc), ''[]'')
    from la_obra_v2.waste_records w
    left join la_obra_v2.inputs i on i.id = w.input_id
    left join la_obra_v2.products p on p.id = w.product_id
    left join la_obra_v2.preparations pr on pr.id = w.preparation_id
    join la_obra_v2.users u on u.id = w.user_id where ' || p_where into r using p_args;
  return r;
end $$;

-- Insumos de una preparación por unidad de rendimiento
create or replace function la_obra_v2.inv_preparation_parts(p_prep int)
returns table(input_id int, qty numeric) language sql stable as $$
  select pi.input_id, sum(pi.quantity / pr.yield_quantity)
    from la_obra_v2.preparations pr join la_obra_v2.preparation_inputs pi on pi.preparation_id = pr.id
   where pr.id = p_prep and pr.yield_quantity > 0 group by pi.input_id;
$$;

create or replace function la_obra_v2.ep_waste__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_type text; v_id int; v_found boolean; v_q numeric; v_approx boolean; v_date date; v_reason text; v_class text;
        v_unit numeric; v_total numeric; v_wid int; r record;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_type := la_obra_v2.jtext(b -> 'affected_type');
  if (b -> 'affected_type') is null or jsonb_typeof(b -> 'affected_type') <> 'string' or v_type not in ('input','product','preparation') then
    perform la_obra_v2.fail(422, 'Tipo de elemento inválido');
  end if;
  v_id := la_obra_v2.positive_id(b -> 'affected_id');
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)', case v_type when 'input' then 'inputs' when 'product' then 'products' else 'preparations' end)
    into v_found using v_id;
  if not v_found then perform la_obra_v2.fail(404, 'Elemento afectado no encontrado'); end if;
  if not la_obra_v2.is_scalar(b -> 'quantity') or not la_obra_v2.is_num(b -> 'quantity') or la_obra_v2.num(b -> 'quantity') <= 0 or la_obra_v2.num(b -> 'quantity') > 999999999 then
    perform la_obra_v2.fail(422, 'Cantidad inválida');
  end if;
  v_q := round(la_obra_v2.num(b -> 'quantity'), 3);
  v_approx := la_obra_v2.not_empty(b -> 'is_approximate');
  v_date := la_obra_v2.dateval(coalesce(nullif(b -> 'waste_date', 'null'::jsonb), to_jsonb(to_char(current_date, 'YYYY-MM-DD'))));
  if v_date > current_date then perform la_obra_v2.fail(422, 'La fecha no puede ser futura'); end if;
  v_reason := la_obra_v2.jstr(b -> 'reason'); v_class := la_obra_v2.jstr(b -> 'classification');
  if v_reason = '' or char_length(v_reason) > 500 then perform la_obra_v2.fail(422, 'Escribe el motivo (máximo 500 caracteres)'); end if;
  if v_class = '' or char_length(v_class) > 100 then perform la_obra_v2.fail(422, 'Elige una clasificación'); end if;
  if v_type = 'input' then v_unit := la_obra_v2.input_cost(v_id);
  elsif v_type = 'preparation' then v_unit := (la_obra_v2.preparation_cost(v_id) ->> 'unit_cost')::numeric;
  else v_unit := (la_obra_v2.product_cost(v_id, 'local') ->> 'standard_cost')::numeric;
  end if;
  v_total := case when v_unit is null then null else round(v_unit * v_q, 2) end;
  insert into la_obra_v2.waste_records(affected_type, input_id, product_id, preparation_id, quantity, is_approximate, waste_date, reason, classification,
    estimated_unit_cost, estimated_total_cost, cost_status, user_id)
  values (v_type, case when v_type = 'input' then v_id end, case when v_type = 'product' then v_id end, case when v_type = 'preparation' then v_id end,
    v_q, v_approx, v_date, v_reason, v_class, round(v_unit, 4), v_total, case when v_unit is null then 'unavailable' else 'calculated' end, u.id)
  returning id into v_wid;
  for r in
    select v_id as input_id, 1.0::numeric as qty where v_type = 'input'
    union all select * from la_obra_v2.inv_preparation_parts(v_id) where v_type = 'preparation'
    union all select * from la_obra_v2.inv_product_parts(v_id, 'local') where v_type = 'product'
  loop
    perform la_obra_v2.inv_record(r.input_id, 'waste', -r.qty * v_q, la_obra_v2.input_cost(r.input_id), 'waste', v_wid, v_class, u.id);
  end loop;
  return la_obra_v2.ok(201, 'Merma registrada y descontada del inventario', jsonb_build_object('waste', jsonb_build_object('id', v_wid, 'estimated_total_cost', v_total::float8)));
end $$;

create or replace function la_obra_v2.ep_waste__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_from date; v_to date; v_type text; v_class text;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.waste_auth(t);
  if la_obra_v2.qparam(q, 'date_from') is not null then v_from := la_obra_v2.waste_date(q, 'date_from'); end if;
  if la_obra_v2.qparam(q, 'date_to') is not null then v_to := la_obra_v2.waste_date(q, 'date_to'); end if;
  if v_from is not null and v_to is not null and v_from > v_to then perform la_obra_v2.fail(422, 'Rango de fechas inválido'); end if;
  v_type := la_obra_v2.jtext(la_obra_v2.qparam(q, 'affected_type'));
  if v_type is not null and v_type not in ('input','product','preparation') then perform la_obra_v2.fail(422, 'Tipo inválido'); end if;
  v_class := la_obra_v2.jtext(la_obra_v2.qparam(q, 'classification'));
  if v_class is not null and char_length(v_class) > 100 then perform la_obra_v2.fail(422, 'Clasificación inválida'); end if;
  return la_obra_v2.ok(200, 'Mermas consultadas', jsonb_build_object('scope', case when u.role = 'admin' then 'all' else 'today_own' end,
    'waste_records', la_obra_v2.waste_select(
      '($1[1] is null or w.waste_date >= $1[1]::date) and ($1[2] is null or w.waste_date <= $1[2]::date)
       and ($1[3] is null or w.affected_type = $1[3]) and ($1[4] is null or w.classification = $1[4])
       and ($1[5] is null or (w.user_id = $1[5]::int and w.waste_date = current_date))',
      array[v_from::text, v_to::text, v_type, v_class, case when u.role = 'employee' then u.id::text end])));
end $$;

create or replace function la_obra_v2.ep_waste__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.waste_auth(t);
  if coalesce(la_obra_v2.jtext(q -> 'id'), '') !~ '^[1-9][0-9]{0,8}$' then perform la_obra_v2.fail(422, 'Identificador inválido'); end if;
  v_id := la_obra_v2.jtext(q -> 'id')::int;
  r := la_obra_v2.waste_select('w.id = $1[1]::int', array[v_id::text]) -> 0;
  if r is null then perform la_obra_v2.fail(404, 'Merma no encontrada'); end if;
  if u.role = 'employee' and ((r ->> 'user_id')::int <> u.id or r ->> 'waste_date' <> to_char(current_date, 'YYYY-MM-DD')) then
    perform la_obra_v2.fail(403, 'No tienes acceso a este registro');
  end if;
  return la_obra_v2.ok(200, 'Detalle consultado', jsonb_build_object('waste', r));
end $$;

create or replace function la_obra_v2.waste_totals(p_from date, p_to date)
returns jsonb language sql stable as $$
  select jsonb_build_object('records', count(*),
    'estimated_loss', coalesce(sum(case when cost_status = 'calculated' then estimated_total_cost else 0 end), 0),
    'without_cost', sum(case when cost_status = 'unavailable' then 1 else 0 end))
  from la_obra_v2.waste_records where waste_date between p_from and p_to;
$$;

create or replace function la_obra_v2.ep_waste__indicators(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_from date; v_to date; w jsonb; v_sales numeric; v_purch numeric; v_loss numeric;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.waste_auth(t, true);
  v_from := la_obra_v2.waste_date(q, 'date_from'); v_to := la_obra_v2.waste_date(q, 'date_to');
  if v_from > v_to then perform la_obra_v2.fail(422, 'El inicio no puede superar el final'); end if;
  w := la_obra_v2.waste_totals(v_from, v_to);
  select coalesce(sum(o.total), 0) into v_sales from la_obra_v2.orders o where o.order_status = 'confirmed' and o.payment_status = 'paid'
     and exists(select 1 from la_obra_v2.payments pay where pay.order_id = o.id and pay.paid_at >= v_from and pay.paid_at < v_to + 1);
  select coalesce(sum(total), 0) into v_purch from la_obra_v2.purchases where purchase_date between v_from and v_to;
  v_loss := (w ->> 'estimated_loss')::numeric;
  return la_obra_v2.ok(200, 'Indicadores consultados', jsonb_build_object('waste', w, 'sales_total', v_sales::float8, 'purchases_total', v_purch::float8,
    'loss_as_percent_of_sales', case when v_sales > 0 then round(v_loss / v_sales * 100, 2)::float8 end,
    'loss_as_percent_of_purchases', case when v_purch > 0 then round(v_loss / v_purch * 100, 2)::float8 end,
    'cost_basis', 'purchases_total es gasto en compras del periodo, no costo de ventas ni consumo real',
    'note', 'Los porcentajes se basan en pérdidas con costo calculable; los demás registros se cuentan por separado'));
end $$;

create or replace function la_obra_v2.ep_waste__compare(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare a1 date; a2 date; b1 date; b2 date; p1 jsonb; p2 jsonb; v_diff numeric;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.waste_auth(t, true);
  a1 := la_obra_v2.waste_date(q, 'period1_start'); a2 := la_obra_v2.waste_date(q, 'period1_end');
  b1 := la_obra_v2.waste_date(q, 'period2_start'); b2 := la_obra_v2.waste_date(q, 'period2_end');
  if a1 > a2 or b1 > b2 then perform la_obra_v2.fail(422, 'El inicio no puede superar el final'); end if;
  p1 := la_obra_v2.waste_totals(a1, a2); p2 := la_obra_v2.waste_totals(b1, b2);
  v_diff := round((p2 ->> 'estimated_loss')::numeric - (p1 ->> 'estimated_loss')::numeric, 2);
  return la_obra_v2.ok(200, 'Comparación consultada', jsonb_build_object('period1', p1, 'period2', p2, 'difference', v_diff::float8,
    'percentage_change', case when (p1 ->> 'estimated_loss')::numeric > 0 then round(v_diff / (p1 ->> 'estimated_loss')::numeric * 100, 2)::float8 end,
    'note', 'Los valores económicos excluyen pérdidas sin costo estimable'));
end $$;

create or replace function la_obra_v2.ep_waste__ranking(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_from date; v_to date; v_type text;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.waste_auth(t, true);
  v_from := la_obra_v2.waste_date(q, 'date_from'); v_to := la_obra_v2.waste_date(q, 'date_to');
  if v_from > v_to then perform la_obra_v2.fail(422, 'El inicio no puede superar el final'); end if;
  v_type := la_obra_v2.jtext(la_obra_v2.qparam(q, 'affected_type'));
  if v_type is not null and v_type not in ('input','product','preparation') then perform la_obra_v2.fail(422, 'Tipo inválido'); end if;
  return la_obra_v2.ok(200, 'Ranking consultado', jsonb_build_object('ranking', (
    select coalesce(jsonb_agg(to_jsonb(s) order by s.estimated_loss desc, s.records desc), '[]') from (
      select w.affected_type, w.input_id, w.product_id, w.preparation_id, coalesce(i.name, p.name, pr.name) as affected_name,
             case when w.affected_type = 'input' then i.unit end as affected_unit, count(*) as records, sum(w.quantity) as total_quantity,
             coalesce(sum(case when w.cost_status = 'calculated' then w.estimated_total_cost else 0 end), 0) as estimated_loss,
             sum(case when w.cost_status = 'unavailable' then 1 else 0 end) as without_cost
        from la_obra_v2.waste_records w
        left join la_obra_v2.inputs i on i.id = w.input_id left join la_obra_v2.products p on p.id = w.product_id
        left join la_obra_v2.preparations pr on pr.id = w.preparation_id
       where w.waste_date between v_from and v_to and (v_type is null or w.affected_type = v_type)
       group by w.affected_type, w.input_id, w.product_id, w.preparation_id, i.name, p.name, pr.name, i.unit) s),
    'note', 'Las cantidades solo se suman dentro de un mismo elemento; los costos no disponibles se reportan por separado'));
end $$;

-- ---------- Factura de prueba (CFDI 4.0 con Profact QA) ----------
-- Necesita la extensión "http" de Supabase (Database → Extensions → http).
create or replace function la_obra_v2.invoice_config()
returns jsonb language sql immutable as $$
  select jsonb_build_object('token', 'mvpNUXmQfK8=', 'postal_code', '32690',
    'issuer', jsonb_build_object('Rfc', 'IIA040805DZ4', 'Nombre', 'INDISTRIA ILUMINADORA DE ALMACENES', 'RegimenFiscal', '626'),
    'receiver', jsonb_build_object('Rfc', 'EKU9003173C9', 'Nombre', 'ESCUELA KEMPER URGATE', 'DomicilioFiscalReceptor', '42501',
      'RegimenFiscalReceptor', '603', 'UsoCFDI', 'G03'));
$$;

create or replace function la_obra_v2.xml_attr(v text)
returns text language sql immutable as $$
  select replace(replace(replace(replace(replace(coalesce(v, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&apos;');
$$;

create or replace function la_obra_v2.invoice_xml(p_folio text, p_cents bigint, p_payment text, p_order int)
returns text language plpgsql stable as $$
declare c jsonb := la_obra_v2.invoice_config(); v_base bigint := round(p_cents / 1.16); v_tax bigint; v_cb numeric := round(p_cents / 116.0, 6);
        v_ca text; d text; i jsonb; r jsonb;
begin
  v_tax := p_cents - v_base;
  v_ca := to_char(v_cb, 'FM999999990.000000');
  i := c -> 'issuer'; r := c -> 'receiver';
  return '<?xml version="1.0" encoding="UTF-8"?>' || chr(10) ||
    '<cfdi:Comprobante xmlns:cfdi="http://www.sat.gob.mx/cfd/4" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    || ' Version="4.0" Serie="QA" Folio="' || p_folio || '" Fecha="' || to_char(now() at time zone 'America/Mexico_City', 'YYYY-MM-DD"T"HH24:MI:SS')
    || '" FormaPago="' || p_payment || '" SubTotal="' || to_char(v_base / 100.0, 'FM999999990.00') || '" Moneda="MXN" Total="' || to_char(p_cents / 100.0, 'FM999999990.00')
    || '" TipoDeComprobante="I" Exportacion="01" MetodoPago="PUE" LugarExpedicion="' || (c ->> 'postal_code')
    || '" xsi:schemaLocation="http://www.sat.gob.mx/cfd/4 http://www.sat.gob.mx/sitio_internet/cfd/4/cfdv40.xsd">'
    || '<cfdi:Emisor Rfc="' || (i ->> 'Rfc') || '" Nombre="' || la_obra_v2.xml_attr(i ->> 'Nombre') || '" RegimenFiscal="' || (i ->> 'RegimenFiscal') || '"/>'
    || '<cfdi:Receptor Rfc="' || (r ->> 'Rfc') || '" Nombre="' || la_obra_v2.xml_attr(r ->> 'Nombre') || '" DomicilioFiscalReceptor="' || (r ->> 'DomicilioFiscalReceptor')
    || '" RegimenFiscalReceptor="' || (r ->> 'RegimenFiscalReceptor') || '" UsoCFDI="' || (r ->> 'UsoCFDI') || '"/>'
    || '<cfdi:Conceptos><cfdi:Concepto ClaveProdServ="90101500" Cantidad="1" ClaveUnidad="E48" Descripcion="Consumo de alimentos - pedido ' || p_order
    || '" ValorUnitario="' || v_ca || '" Importe="' || v_ca || '" ObjetoImp="02"><cfdi:Impuestos><cfdi:Traslados><cfdi:Traslado Base="' || v_ca
    || '" Impuesto="002" TipoFactor="Tasa" TasaOCuota="0.160000" Importe="' || to_char(round(v_cb * 0.16, 6), 'FM999999990.000000')
    || '"/></cfdi:Traslados></cfdi:Impuestos></cfdi:Concepto></cfdi:Conceptos>'
    || '<cfdi:Impuestos TotalImpuestosTrasladados="' || to_char(v_tax / 100.0, 'FM999999990.00') || '"><cfdi:Traslados><cfdi:Traslado Base="'
    || to_char(v_base / 100.0, 'FM999999990.00') || '" Impuesto="002" TipoFactor="Tasa" TasaOCuota="0.160000" Importe="' || to_char(v_tax / 100.0, 'FM999999990.00')
    || '"/></cfdi:Traslados></cfdi:Impuestos></cfdi:Comprobante>' || chr(10);
end $$;

create or replace function la_obra_v2.profact(p_op text, p_payload jsonb, out o_status int, out o_body jsonb)
language plpgsql as $$
declare r record;
begin
  if not exists(select 1 from pg_extension where extname = 'http') then
    perform la_obra_v2.fail(503, 'Activa la extensión "http" en Supabase (Database → Extensions → http) para timbrar la factura de prueba');
  end if;
  begin
    execute 'select (h).status, (h).content from (select extensions.http((''POST'', $1,
        array[extensions.http_header(''Accept'', ''application/json''), extensions.http_header(''Authorization'', ''Bearer '' || $2)],
        ''application/json'', $3)::extensions.http_request) h) x'
      into r using 'https://pruebas.timbracfdi33.mx:1444/api/v2/Timbrado/' || p_op, la_obra_v2.invoice_config() ->> 'token', p_payload::text;
  exception when others then
    perform la_obra_v2.fail(502, 'No se recibió respuesta de Profact QA. Al reintentar se usará el mismo XML.');
  end;
  o_status := r.status;
  begin o_body := r.content::jsonb; exception when others then o_body := null; end;
end $$;

create or replace function la_obra_v2.parse_stamped_xml(p_xml text, p_folio text)
returns text language plpgsql as $$
declare x xml; v_uuid text;
begin
  if p_xml is null or p_xml = '' or position('<!DOCTYPE' in upper(p_xml)) > 0 then return null; end if;
  begin x := xmlparse(document p_xml); exception when others then return null; end;
  if (xpath('/c:Comprobante/@Folio', x, array[array['c','http://www.sat.gob.mx/cfd/4']]))[1]::text is distinct from p_folio then return null; end if;
  v_uuid := (xpath('//t:TimbreFiscalDigital/@UUID', x, array[array['t','http://www.sat.gob.mx/TimbreFiscalDigital']]))[1]::text;
  return case when v_uuid ~* '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' then v_uuid end;
end $$;

-- invoices/order.php · GET ?id= (consultar) · POST {order_id, card_type?} (timbrar)
create or replace function la_obra_v2.ep_invoices__order(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record; inv la_obra_v2.order_test_invoices; v_name text; v_code text; v_card text; v_req text; v_xml text;
        v_st int; v_resp jsonb; v_prev text; v_stamped text; v_uuid text; v_detail text;
begin
  if m not in ('GET','POST') then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
  u := la_obra_v2.auth(t);
  v_id := la_obra_v2.positive_id(case when m = 'GET' then q -> 'id' else la_obra_v2.body(b) -> 'order_id' end);
  select o2.*, p.amount, pm.name as payment_name into o from la_obra_v2.orders o2
    left join la_obra_v2.payments p on p.order_id = o2.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id where o2.id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if u.role <> 'admin' and (o.user_id <> u.id or o.created_at::date <> current_date) then perform la_obra_v2.fail(403, 'Solo puedes facturar tus pedidos del día'); end if;
  select * into inv from la_obra_v2.order_test_invoices where order_id = v_id;
  if inv.uuid is not null and inv.uuid <> '' then
    return la_obra_v2.ok(200, 'CFDI de prueba disponible', jsonb_build_object('invoice', jsonb_build_object('uuid', inv.uuid, 'xml', inv.stamped_xml)));
  end if;
  if m = 'GET' then return la_obra_v2.ok(200, 'Sin CFDI de prueba', jsonb_build_object('invoice', null)); end if;
  if o.order_status <> 'confirmed' or o.payment_status <> 'paid' or o.total <= 0 or o.total is distinct from o.amount then
    perform la_obra_v2.fail(409, 'El pedido debe estar confirmado y pagado por completo');
  end if;
  v_name := lower(btrim(coalesce(o.payment_name, '')));
  v_code := case v_name when 'efectivo' then '01' when 'transferencia' then '03' when 'transferencia electrónica' then '03'
    when 'tarjeta de crédito' then '04' when 'tarjeta crédito' then '04' when 'tarjeta de débito' then '28' when 'tarjeta débito' then '28' end;
  if v_code is null and position('tarjeta' in v_name) > 0 then
    v_card := la_obra_v2.jtext(b -> 'card_type');
    if v_card = 'credit' then v_code := '04'; elsif v_card = 'debit' then v_code := '28';
    elsif inv.order_id is null then perform la_obra_v2.fail(422, 'Indica si la tarjeta fue de crédito o débito para la factura', jsonb_build_object('needs_card_type', true));
    end if;
  end if;
  if inv.order_id is null and v_code is null then perform la_obra_v2.fail(422, 'Esta forma de pago no se puede facturar en la prueba. Usa efectivo, transferencia o tarjeta.'); end if;
  if not pg_try_advisory_xact_lock(hashtext('laobra:cfdi:qa:' || v_id)) then perform la_obra_v2.fail(409, 'Ya hay una solicitud de timbrado para este pedido'); end if;
  if inv.order_id is null then
    v_req := encode(extensions.gen_random_bytes(16), 'hex');
    v_xml := la_obra_v2.invoice_xml(v_req, round(o.total * 100)::bigint, v_code, v_id);
    insert into la_obra_v2.order_test_invoices(order_id, request_id, request_xml) values (v_id, v_req, v_xml);
  else
    v_req := inv.request_id; v_xml := inv.request_xml;
  end if;
  select * into v_st, v_resp from la_obra_v2.profact('TimbraCFDI', jsonb_build_object('XmlComprobanteBase64', replace(encode(convert_to(v_xml, 'UTF8'), 'base64'), E'\n', ''), 'IdComprobante', v_req));
  if (v_resp ->> 'Codigo') = '25' then
    v_prev := substring(coalesce(v_resp ->> 'Mensaje', '') from '[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}');
    if v_prev is not null then
      select * into v_st, v_resp from la_obra_v2.profact('ObtieneCFDI', jsonb_build_object('FolioFiscal', v_prev, 'RfcEmisor', la_obra_v2.invoice_config() #>> '{issuer,Rfc}'));
    end if;
  end if;
  v_stamped := case when jsonb_typeof(v_resp -> 'Xml') = 'string' then v_resp ->> 'Xml' end;
  v_uuid := case when v_st = 200 and (v_resp ->> 'Codigo') = '0' and v_stamped is not null then la_obra_v2.parse_stamped_xml(v_stamped, v_req) end;
  if v_uuid is null then
    v_detail := coalesce(v_resp ->> 'Descripcion', v_resp ->> 'Mensaje', v_resp ->> 'message', '');
    -- Se conserva la solicitud para reintentar con el mismo XML
    if v_detail <> '' then
      return la_obra_v2.ok(502, 'Profact QA (HTTP ' || coalesce(v_st::text, '?') || '): ' || left(v_detail, 400));
    end if;
    return la_obra_v2.ok(502, 'Profact QA (HTTP ' || coalesce(v_st::text, '?') || ') no devolvió un XML timbrado para este pedido. Revisa el emisor y token de prueba.');
  end if;
  update la_obra_v2.order_test_invoices set uuid = v_uuid, stamped_xml = v_stamped where order_id = v_id;
  return la_obra_v2.ok(201, 'CFDI de prueba timbrado', jsonb_build_object('invoice', jsonb_build_object('uuid', v_uuid, 'xml', v_stamped)));
end $$;

-- ---------- Asistencia con geolocalización ----------
create or replace function la_obra_v2.ep_attendance__location(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_name text; v_lat numeric; v_lng numeric; v_radius jsonb;
begin
  if m = 'GET' then
    perform la_obra_v2.auth(t);
    return la_obra_v2.ok(200, 'Ubicación del negocio', jsonb_build_object('location', la_obra_v2.work_location_json()));
  end if;
  if m <> 'PUT' then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_name := btrim(coalesce(la_obra_v2.jtext(b -> 'name'), 'La Obra'));
  if v_name = '' or char_length(v_name) > 100 then perform la_obra_v2.fail(422, 'Nombre del lugar inválido'); end if;
  v_lat := la_obra_v2.coordinate(b -> 'latitude', 90, 'Latitud');
  v_lng := la_obra_v2.coordinate(b -> 'longitude', 180, 'Longitud');
  v_radius := coalesce(nullif(b -> 'radius_m', 'null'::jsonb), '100'::jsonb);
  if not la_obra_v2.is_num(v_radius) or trunc(la_obra_v2.num(v_radius)) < 20 or trunc(la_obra_v2.num(v_radius)) > 2000 then
    perform la_obra_v2.fail(422, 'El radio debe estar entre 20 y 2000 metros');
  end if;
  insert into la_obra_v2.work_location(id, name, latitude, longitude, radius_m, updated_by, updated_at)
  values (1, v_name, v_lat, v_lng, trunc(la_obra_v2.num(v_radius))::int, u.id, localtimestamp)
  on conflict (id) do update set name = excluded.name, latitude = excluded.latitude, longitude = excluded.longitude,
    radius_m = excluded.radius_m, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  return la_obra_v2.ok(200, 'Ubicación del negocio guardada', jsonb_build_object('location', la_obra_v2.work_location_json()));
end $$;

create or replace function la_obra_v2.ep_attendance__check(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_type text; v_lat numeric; v_lng numeric; v_acc numeric; v_note text; loc jsonb; v_dist double precision; v_last jsonb; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_type := la_obra_v2.jtext(b -> 'type');
  if coalesce(v_type, '') not in ('in','out') then perform la_obra_v2.fail(422, 'Indica si es entrada o salida'); end if;
  v_lat := la_obra_v2.coordinate(b -> 'latitude', 90, 'Latitud');
  v_lng := la_obra_v2.coordinate(b -> 'longitude', 180, 'Longitud');
  if not la_obra_v2.is_num(b -> 'accuracy') or la_obra_v2.num(b -> 'accuracy') < 0 or la_obra_v2.num(b -> 'accuracy') > 100000 then perform la_obra_v2.fail(422, 'Precisión inválida'); end if;
  v_acc := round(la_obra_v2.num(b -> 'accuracy'), 1);
  v_note := la_obra_v2.jstr(b -> 'note');
  if char_length(v_note) > 255 then perform la_obra_v2.fail(422, 'La nota es demasiado larga'); end if;
  if v_acc > 150 then
    perform la_obra_v2.fail(422, 'La ubicación es poco precisa (±' || round(v_acc) || ' m). Sal a un lugar abierto o activa el GPS de alta precisión e intenta de nuevo.');
  end if;
  loc := la_obra_v2.work_location_json();
  if loc is null then perform la_obra_v2.fail(409, 'El administrador aún no ha configurado la ubicación del negocio'); end if;
  v_dist := la_obra_v2.distance_m(v_lat, v_lng, (loc ->> 'latitude')::numeric, (loc ->> 'longitude')::numeric);
  if v_dist > (loc ->> 'radius_m')::int then
    perform la_obra_v2.fail(403, 'Estás a ' || round(v_dist::numeric) || ' m de ' || (loc ->> 'name') || '. Para registrar debes estar a menos de ' || (loc ->> 'radius_m') || ' m.',
      jsonb_build_object('distance_m', round(v_dist::numeric, 1), 'radius_m', (loc ->> 'radius_m')::int));
  end if;
  v_last := la_obra_v2.last_attendance_today(u.id);
  if v_type = 'in' and v_last ->> 'type' = 'in' then perform la_obra_v2.fail(409, 'Ya registraste tu entrada. Lo siguiente es registrar tu salida.'); end if;
  if v_type = 'out' and (v_last is null or v_last ->> 'type' = 'out') then perform la_obra_v2.fail(409, 'Primero registra tu entrada de hoy.'); end if;
  insert into la_obra_v2.attendance(user_id, type, latitude, longitude, accuracy_m, distance_m, note)
  values (u.id, v_type, v_lat, v_lng, v_acc, round(v_dist::numeric, 1), nullif(v_note, '')) returning id into v_id;
  return la_obra_v2.ok(201, case when v_type = 'in' then 'Entrada registrada' else 'Salida registrada' end, jsonb_build_object('record',
    (select to_jsonb(a) || jsonb_build_object('user_name', us.name) from la_obra_v2.attendance a join la_obra_v2.users us on us.id = a.user_id where a.id = v_id)));
end $$;

create or replace function la_obra_v2.ep_attendance__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_uid int; v_from date; v_to date;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  if u.role = 'admin' then
    if la_obra_v2.qparam(q, 'user_id') is not null then v_uid := la_obra_v2.positive_id(q -> 'user_id'); end if;
    if la_obra_v2.qparam(q, 'date_from') is not null then v_from := la_obra_v2.dateval(q -> 'date_from'); end if;
    if la_obra_v2.qparam(q, 'date_to') is not null then v_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  end if;
  return la_obra_v2.ok(200, 'Asistencia consultada', jsonb_build_object(
    'scope', case when u.role = 'admin' then 'all' else 'own_week' end,
    'records', (select coalesce(jsonb_agg(x order by rn), '[]') from (
        select jsonb_build_object('id', a.id, 'user_id', a.user_id, 'user_name', us.name, 'type', a.type, 'latitude', a.latitude, 'longitude', a.longitude,
          'accuracy_m', a.accuracy_m, 'distance_m', a.distance_m, 'note', a.note, 'created_at', a.created_at) x,
          row_number() over (order by a.created_at desc, a.id desc) rn
        from la_obra_v2.attendance a join la_obra_v2.users us on us.id = a.user_id
        where (u.role = 'admin' or (a.user_id = u.id and a.created_at::date >= current_date - 6))
          and (v_uid is null or a.user_id = v_uid) and (v_from is null or a.created_at::date >= v_from) and (v_to is null or a.created_at::date <= v_to)
        order by a.created_at desc, a.id desc limit 500) s),
    'last_today', la_obra_v2.last_attendance_today(u.id),
    'location', la_obra_v2.work_location_json()));
end $$;
