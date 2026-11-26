-- =====================================================================
-- La Obra v2 · 19 · Compras pagadas en varias formas (ej. tarjeta + efectivo)
-- Supabase → SQL Editor → New query → pegar → Run. No borra datos y se puede volver a correr.
-- Necesita el 15 (tabla purchase_payments) y el 18 (compras con unidades).
--
--   purchases/create y purchases/update aceptan  payments: [{ payment_method_id, amount }, …]
--   La suma debe ser igual al total de la compra. Si no se manda, se paga todo con payment_method_id.
--   El método "principal" de la compra queda como el de mayor monto.
-- =====================================================================
set check_function_bodies = off;

create table if not exists la_obra_v2.purchase_payments (
  id                serial primary key,
  purchase_id       int not null references la_obra_v2.purchases(id) on delete cascade,
  payment_method_id int not null references la_obra_v2.payment_methods(id),
  amount            numeric(12,2) not null check (amount > 0)
);
create index if not exists idx_purchase_payments on la_obra_v2.purchase_payments(purchase_id);

-- Valida y limpia las formas de pago: [{payment_method_id, amount}] que sumen el total
create or replace function la_obra_v2.valid_purchase_payments(p jsonb, p_total numeric, p_default_method int)
returns jsonb language plpgsql as $$
declare x jsonb; v_m int; v_a numeric; v_sum numeric := 0; clean jsonb := '[]'; v_map jsonb := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) = 0 then
    return jsonb_build_array(jsonb_build_object('payment_method_id', p_default_method, 'amount', p_total));
  end if;
  for x in select * from jsonb_array_elements(p) loop
    v_m := la_obra_v2.positive_id(x -> 'payment_method_id', 'Elige la forma de pago');
    if not exists (select 1 from la_obra_v2.payment_methods where id = v_m and status = 'active') then
      perform la_obra_v2.fail(404, 'Forma de pago inexistente o inactiva');
    end if;
    v_a := la_obra_v2.money(coalesce(x -> 'amount', '0'::jsonb), false);
    if v_a = 0 then continue; end if;
    v_sum := v_sum + v_a;
    -- Si se repite el método, se juntan los montos
    v_map := jsonb_set(v_map, array[v_m::text], to_jsonb(coalesce((v_map ->> v_m::text)::numeric, 0) + v_a));
  end loop;
  if abs(v_sum - p_total) > 0.01 then
    perform la_obra_v2.fail(422, 'Lo pagado (' || to_char(v_sum, 'FM$999,999,990.00') || ') no coincide con el total de la compra ('
      || to_char(p_total, 'FM$999,999,990.00') || ')');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('payment_method_id', k::int, 'amount', v::numeric) order by v::numeric desc), '[]')
    into clean from jsonb_each_text(v_map) e(k, v);
  if jsonb_array_length(clean) = 0 then
    return jsonb_build_array(jsonb_build_object('payment_method_id', p_default_method, 'amount', p_total));
  end if;
  return clean;
end $$;

create or replace function la_obra_v2.save_purchase_payments(p_id int, p_pay jsonb)
returns void language plpgsql as $$
begin
  delete from la_obra_v2.purchase_payments where purchase_id = p_id;
  -- Una sola forma de pago: basta con el método de la compra (no hace falta renglón)
  if jsonb_array_length(p_pay) > 1 then
    insert into la_obra_v2.purchase_payments(purchase_id, payment_method_id, amount)
    select p_id, (x ->> 'payment_method_id')::int, (x ->> 'amount')::numeric from jsonb_array_elements(p_pay) x
     where (x ->> 'amount')::numeric > 0;
  end if;
  update la_obra_v2.purchases set payment_method_id = (p_pay -> 0 ->> 'payment_method_id')::int where id = p_id;
end $$;

create or replace function la_obra_v2.purchase_payments_json(p_id int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('payment_method_id', r.payment_method_id, 'name', pm.name, 'amount', r.amount::float8)
           order by r.amount desc), '[]')
    from la_obra_v2.purchase_pay_rows() r join la_obra_v2.payment_methods pm on pm.id = r.payment_method_id
   where r.purchase_id = p_id;
$$;

-- Cada forma de pago de cada compra (también está en el 15; se repite por si se corre solo)
create or replace function la_obra_v2.purchase_pay_rows()
returns table(purchase_id int, payment_method_id int, amount numeric, created_at timestamp, supplier text)
language sql stable as $$
  select pp.purchase_id, pp.payment_method_id, pp.amount, p.created_at, p.supplier::text
    from la_obra_v2.purchase_payments pp join la_obra_v2.purchases p on p.id = pp.purchase_id
  union all
  select p.id, p.payment_method_id, p.total, p.created_at, p.supplier::text
    from la_obra_v2.purchases p
   where not exists (select 1 from la_obra_v2.purchase_payments x where x.purchase_id = p.id);
$$;

-- ---------- purchase_json con sus formas de pago ----------
create or replace function la_obra_v2.purchase_json(p_id int, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  if p_lock then perform 1 from la_obra_v2.purchases where id = p_id for update; end if;
  select to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name,
      'payments', la_obra_v2.purchase_payments_json(p.id),
      'items', (
      select coalesce(jsonb_agg(jsonb_build_object('id', pi.id, 'input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit,
        'quantity', pi.quantity, 'unit_cost', pi.unit_cost, 'subtotal', pi.subtotal, 'content_per_package', pi.content_per_package,
        'content_unit', pi.content_unit, 'total_base_quantity', pi.total_base_quantity,
        'buy_unit', coalesce(pi.buy_unit, case when pi.content_per_package = 1 then i.unit end)) order by pi.id), '[]')
      from la_obra_v2.purchase_items pi join la_obra_v2.inputs i on i.id = pi.input_id where pi.purchase_id = p.id))
    into r from la_obra_v2.purchases p join la_obra_v2.users u on u.id = p.user_id join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
   where p.id = p_id;
  if r is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  return la_obra_v2.fix_dates(r);
end $$;

-- ---------- purchases/index: muestra "Tarjeta $300 · Efectivo $200" ----------
create or replace function la_obra_v2.ep_purchases__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_from date; v_to date;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  if la_obra_v2.qparam(q, 'date_from') is not null then v_from := la_obra_v2.dateval(q -> 'date_from'); end if;
  if la_obra_v2.qparam(q, 'date_to') is not null then v_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  return la_obra_v2.ok(200, 'Compras consultadas', jsonb_build_object('purchases', (
    select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('user_name', u.name,
             'payment_method', (select string_agg(x ->> 'name', ' + ') from jsonb_array_elements(la_obra_v2.purchase_payments_json(p.id)) x),
             'payments', la_obra_v2.purchase_payments_json(p.id)) order by p.purchase_date desc, p.id desc), '[]')
    from la_obra_v2.purchases p join la_obra_v2.users u on u.id = p.user_id
    where (v_from is null or p.purchase_date >= v_from) and (v_to is null or p.purchase_date <= v_to))));
end $$;

-- ---------- purchases/create ----------
create or replace function la_obra_v2.ep_purchases__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; vp jsonb; v_buyer text; v_id int; v_pay jsonb;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  -- Si viene "payments", el método principal sale del primero (para validar la compra)
  if jsonb_typeof(b -> 'payments') = 'array' and jsonb_array_length(b -> 'payments') > 0 and not (b ? 'payment_method_id') then
    b := b || jsonb_build_object('payment_method_id', b -> 'payments' -> 0 -> 'payment_method_id');
  end if;
  vp := la_obra_v2.valid_purchase(b);
  v_pay := la_obra_v2.valid_purchase_payments(b -> 'payments', (vp ->> 'total')::numeric, (vp ->> 'payment_method_id')::int);
  v_buyer := la_obra_v2.valid_buyer(b -> 'buyer');
  insert into la_obra_v2.purchases(purchase_date, supplier, buyer, payment_method_id, user_id, total)
  values ((vp ->> 'purchase_date')::date, vp ->> 'supplier', v_buyer, (vp ->> 'payment_method_id')::int, u.id, (vp ->> 'total')::numeric)
  returning id into v_id;
  perform la_obra_v2.insert_purchase_items(v_id, vp -> 'items');
  perform la_obra_v2.save_purchase_payments(v_id, v_pay);
  perform la_obra_v2.inv_sync_purchase(v_id, u.id);
  perform la_obra_v2.remember_presentations(b -> 'items');
  return la_obra_v2.ok(201, 'Compra registrada', jsonb_build_object('purchase', la_obra_v2.purchase_json(v_id)));
end $$;

-- ---------- purchases/update ----------
create or replace function la_obra_v2.ep_purchases__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_old jsonb; merged jsonb; vp jsonb; v_buyer text; v_new jsonb; v_pay jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  if not (b ?| array['purchase_date','supplier','buyer','payment_method_id','items','payments']) then perform la_obra_v2.fail(422, 'No hay cambios para actualizar'); end if;
  v_old := la_obra_v2.purchase_json(v_id, true);
  if jsonb_typeof(b -> 'payments') = 'array' and jsonb_array_length(b -> 'payments') > 0 and not (b ? 'payment_method_id') then
    b := b || jsonb_build_object('payment_method_id', b -> 'payments' -> 0 -> 'payment_method_id');
  end if;
  merged := jsonb_build_object(
    'purchase_date', coalesce(nullif(b -> 'purchase_date', 'null'::jsonb), v_old -> 'purchase_date'),
    'supplier', case when b ? 'supplier' then b -> 'supplier' else v_old -> 'supplier' end,
    'payment_method_id', coalesce(nullif(b -> 'payment_method_id', 'null'::jsonb), v_old -> 'payment_method_id'),
    'items', coalesce(nullif(b -> 'items', 'null'::jsonb), (select coalesce(jsonb_agg(jsonb_build_object('input_id', i -> 'input_id', 'quantity', i -> 'quantity',
              'unit_cost', i -> 'unit_cost', 'content_per_package', i -> 'content_per_package', 'buy_unit', i -> 'buy_unit') order by n), '[]')
              from jsonb_array_elements(v_old -> 'items') with ordinality x(i, n))));
  vp := la_obra_v2.valid_purchase(merged);
  -- Formas de pago: las nuevas; si no vienen y el total no cambió, se conservan; si cambió, todo al método principal
  v_pay := case
    when b ? 'payments' then la_obra_v2.valid_purchase_payments(b -> 'payments', (vp ->> 'total')::numeric, (vp ->> 'payment_method_id')::int)
    when abs((v_old ->> 'total')::numeric - (vp ->> 'total')::numeric) < 0.005 and not (b ? 'payment_method_id')
      then (select coalesce(jsonb_agg(jsonb_build_object('payment_method_id', x -> 'payment_method_id', 'amount', x -> 'amount')), '[]') from jsonb_array_elements(v_old -> 'payments') x)
    else jsonb_build_array(jsonb_build_object('payment_method_id', (vp ->> 'payment_method_id')::int, 'amount', (vp ->> 'total')::numeric)) end;
  v_buyer := case when b ? 'buyer' then la_obra_v2.valid_buyer(b -> 'buyer') else v_old ->> 'buyer' end;
  update la_obra_v2.purchases set purchase_date = (vp ->> 'purchase_date')::date, supplier = vp ->> 'supplier', buyer = v_buyer,
         payment_method_id = (vp ->> 'payment_method_id')::int, total = (vp ->> 'total')::numeric, updated_at = localtimestamp where id = v_id;
  delete from la_obra_v2.purchase_items where purchase_id = v_id;
  perform la_obra_v2.insert_purchase_items(v_id, vp -> 'items');
  perform la_obra_v2.save_purchase_payments(v_id, v_pay);
  perform la_obra_v2.inv_sync_purchase(v_id, u.id);
  if b ? 'items' then perform la_obra_v2.remember_presentations(b -> 'items'); end if;
  v_new := la_obra_v2.purchase_json(v_id);
  insert into la_obra_v2.purchase_history(purchase_id, changed_by, previous_data, new_data, change_reason)
  values (v_id, u.id, v_old::text, v_new::text, case when b ? 'change_reason' and jsonb_typeof(b -> 'change_reason') <> 'null' then la_obra_v2.jstr(b -> 'change_reason') end);
  return la_obra_v2.ok(200, 'Compra actualizada', jsonb_build_object('purchase', v_new));
end $$;

-- ---------- Permisos ----------
revoke all on all tables in schema la_obra_v2 from public;
revoke all on all functions in schema la_obra_v2 from public;
revoke all on all sequences in schema la_obra_v2 from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all tables in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all functions in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all sequences in schema la_obra_v2 from anon, authenticated';
  end if;
end $$;
notify pgrst, 'reload schema';
select 'Compras con pago dividido listas' as resultado;
