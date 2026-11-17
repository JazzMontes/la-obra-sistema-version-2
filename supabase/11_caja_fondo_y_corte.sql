-- =====================================================================
-- La Obra v2 · 11 · Caja: fondo inicial y corte de caja
-- Se puede correr solo (Supabase → SQL Editor → New query → pegar → Run) sobre una base ya
-- instalada. No borra ni cambia datos: solo crea 3 tablas nuevas y 2 rutas de la API.
--
--   cash/opening.php  GET ?date=AAAA-MM-DD   → fondo del día (o null)
--                     POST { amount, date? } → registra / corrige el fondo del día
--   cash/cut.php      GET ?date=AAAA-MM-DD   → corte calculado del día (toda la caja)
--                     POST { counted_cash, notes?, date? } → guarda el corte
--
-- Efectivo esperado = fondo + ventas cobradas en efectivo − gastos y salidas del día.
-- Las compras pagadas en efectivo NO entran al corte.
-- Las ventas cuentan el día en que se cobraron (paid_at), que es cuando entra el dinero.
-- El empleado solo consulta y registra el día de hoy; el administrador, cualquier día.
-- =====================================================================
set check_function_bodies = off;

-- ---------- Tablas ----------
create table if not exists la_obra_v2.cash_openings (
  id            serial primary key,
  business_date date not null unique,
  amount        numeric(12,2) not null check (amount >= 0),
  user_id       int not null references la_obra_v2.users(id),
  created_at    timestamp not null default localtimestamp,
  updated_by    int null references la_obra_v2.users(id),
  updated_at    timestamp null
);

create table if not exists la_obra_v2.cash_opening_history (
  id          serial primary key,
  opening_id  int not null references la_obra_v2.cash_openings(id),
  old_amount  numeric(12,2) not null,
  new_amount  numeric(12,2) not null,
  changed_by  int not null references la_obra_v2.users(id),
  changed_at  timestamp not null default localtimestamp
);

create table if not exists la_obra_v2.cash_cuts (
  id             serial primary key,
  business_date  date not null,
  user_id        int not null references la_obra_v2.users(id),
  fund           numeric(12,2) not null,
  total_sales    numeric(12,2) not null,
  cash_sales     numeric(12,2) not null,
  expenses       numeric(12,2) not null,
  expected_cash  numeric(12,2) not null,
  counted_cash   numeric(12,2) not null,
  difference     numeric(12,2) not null,
  methods        jsonb not null default '[]'::jsonb,
  notes          varchar(255) null,
  created_at     timestamp not null default localtimestamp
);
create index if not exists idx_cash_cuts_date on la_obra_v2.cash_cuts(business_date);

-- ---------- Utilidades ----------
-- Día del corte: el empleado siempre hoy; el administrador puede pedir otro día
create or replace function la_obra_v2.cash_day(u la_obra_v2.users, v jsonb)
returns date language plpgsql as $$
declare d date;
begin
  if v is null or coalesce(la_obra_v2.jtext(v), '') = '' then return current_date; end if;
  d := la_obra_v2.dateval(v);
  if u.role = 'employee' and d <> current_date then
    perform la_obra_v2.fail(403, 'El empleado solo puede consultar la caja de hoy');
  end if;
  if d > current_date then perform la_obra_v2.fail(422, 'La fecha no puede ser futura'); end if;
  return d;
end $$;

create or replace function la_obra_v2.cash_opening_json(p_date date)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', o.id, 'date', o.business_date, 'amount', o.amount::float8,
           'user_id', o.user_id, 'user_name', u.name, 'created_at', o.created_at,
           'updated_at', o.updated_at, 'updated_by_name', ub.name)
    from la_obra_v2.cash_openings o
    join la_obra_v2.users u on u.id = o.user_id
    left join la_obra_v2.users ub on ub.id = o.updated_by
   where o.business_date = p_date;
$$;

-- Cálculo del corte de un día (toda la caja, todos los usuarios)
create or replace function la_obra_v2.cash_cut_calc(p_date date)
returns jsonb language plpgsql stable as $$
declare v_fund numeric; v_methods jsonb; v_total numeric; v_cash numeric; v_exp numeric; v_pending record; v_count int;
begin
  select coalesce((select amount from la_obra_v2.cash_openings where business_date = p_date), 0) into v_fund;

  -- Todos los métodos activos (aunque estén en $0) más los que tuvieron ventas
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'orders', orders, 'amount', amount::float8,
           'commission', commission::float8, 'cash', is_cash) order by is_cash desc, amount desc, id), '[]'),
         coalesce(sum(amount), 0), coalesce(sum(amount) filter (where is_cash), 0), coalesce(sum(orders), 0)
    into v_methods, v_total, v_cash, v_count
    from (
      select pm.id, pm.name, lower(btrim(pm.name)) = 'efectivo' as is_cash,
             count(s.order_id)::int orders, coalesce(sum(s.amount), 0) amount, coalesce(sum(s.commission_amount), 0) commission
        from la_obra_v2.payment_methods pm
        left join (
          select pay.payment_method_id, pay.order_id, pay.amount, pay.commission_amount
            from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id
           where o.order_status <> 'cancelled' and o.payment_status = 'paid' and pay.paid_at::date = p_date
        ) s on s.payment_method_id = pm.id
       group by pm.id, pm.name, pm.status
      having pm.status = 'active' or count(s.order_id) > 0
    ) m;

  select coalesce(sum(amount), 0) into v_exp from la_obra_v2.expenses where status = 'active' and created_at::date = p_date;

  select count(*)::int n, coalesce(sum(total), 0) amount into v_pending
    from la_obra_v2.orders where order_status <> 'cancelled' and payment_status = 'pending' and created_at::date = p_date;

  return jsonb_build_object(
    'date', p_date,
    'fund', round(v_fund, 2)::float8,
    'opening', la_obra_v2.cash_opening_json(p_date),
    'methods', v_methods,
    'paid_orders', v_count,
    'total_sales', round(v_total, 2)::float8,
    'cash_sales', round(v_cash, 2)::float8,
    'non_cash_sales', round(v_total - v_cash, 2)::float8,
    'expenses', round(v_exp, 2)::float8,
    'expenses_list', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'amount', e.amount::float8, 'reason', e.reason,
                        'user_name', u.name, 'created_at', e.created_at, 'status', e.status) order by e.created_at, e.id), '[]')
                        from la_obra_v2.expenses e join la_obra_v2.users u on u.id = e.user_id
                       where e.status = 'active' and e.created_at::date = p_date),
    'cash_from_sales', round(v_cash - v_exp, 2)::float8,
    'expected_cash', round(v_fund + v_cash - v_exp, 2)::float8,
    'pending_orders', v_pending.n,
    'pending_amount', round(v_pending.amount, 2)::float8);
end $$;

-- ---------- cash/opening.php ----------
create or replace function la_obra_v2.ep_cash__opening(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_date date; v_amount numeric; o la_obra_v2.cash_openings;
begin
  u := la_obra_v2.auth(t);
  if m = 'GET' then
    v_date := la_obra_v2.cash_day(u, la_obra_v2.qparam(q, 'date'));
    return la_obra_v2.ok(200, 'Fondo consultado', jsonb_build_object('opening', la_obra_v2.cash_opening_json(v_date)));
  elsif m = 'POST' then
    b := la_obra_v2.body(b);
    v_date := la_obra_v2.cash_day(u, b -> 'date');
    v_amount := la_obra_v2.money(b -> 'amount', false);
    select * into o from la_obra_v2.cash_openings where business_date = v_date for update;
    if o.id is null then
      insert into la_obra_v2.cash_openings(business_date, amount, user_id) values (v_date, v_amount, u.id);
      return la_obra_v2.ok(201, 'Fondo de caja registrado', jsonb_build_object('opening', la_obra_v2.cash_opening_json(v_date)));
    end if;
    if o.amount <> v_amount then
      insert into la_obra_v2.cash_opening_history(opening_id, old_amount, new_amount, changed_by) values (o.id, o.amount, v_amount, u.id);
      update la_obra_v2.cash_openings set amount = v_amount, updated_by = u.id, updated_at = localtimestamp where id = o.id;
    end if;
    return la_obra_v2.ok(200, 'Fondo de caja actualizado', jsonb_build_object('opening', la_obra_v2.cash_opening_json(v_date)));
  end if;
  perform la_obra_v2.fail(405, 'Método no permitido');
  return null;
end $$;

-- ---------- cash/cut.php ----------
create or replace function la_obra_v2.ep_cash__cut(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_date date; c jsonb; v_counted numeric; v_notes text; v_id int;
begin
  u := la_obra_v2.auth(t);
  if m = 'GET' then
    v_date := la_obra_v2.cash_day(u, la_obra_v2.qparam(q, 'date'));
    c := la_obra_v2.cash_cut_calc(v_date);
    -- Cortes guardados ese día (el empleado ve solo los suyos)
    c := c || jsonb_build_object('saved_cuts', (
      select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'user_name', us.name, 'created_at', k.created_at,
               'expected_cash', k.expected_cash::float8, 'counted_cash', k.counted_cash::float8,
               'difference', k.difference::float8, 'notes', k.notes) order by k.created_at desc, k.id desc), '[]')
        from la_obra_v2.cash_cuts k join la_obra_v2.users us on us.id = k.user_id
       where k.business_date = v_date and (u.role = 'admin' or k.user_id = u.id)));
    return la_obra_v2.ok(200, 'Corte calculado', jsonb_build_object('cut', c));
  elsif m = 'POST' then
    b := la_obra_v2.body(b);
    v_date := la_obra_v2.cash_day(u, b -> 'date');
    v_counted := la_obra_v2.money(b -> 'counted_cash', false);
    v_notes := nullif(la_obra_v2.jstr(b -> 'notes'), '');
    if char_length(coalesce(v_notes, '')) > 255 then perform la_obra_v2.fail(422, 'La nota es demasiado larga'); end if;
    c := la_obra_v2.cash_cut_calc(v_date);
    insert into la_obra_v2.cash_cuts(business_date, user_id, fund, total_sales, cash_sales, expenses, expected_cash,
                                     counted_cash, difference, methods, notes)
    values (v_date, u.id, (c ->> 'fund')::numeric, (c ->> 'total_sales')::numeric, (c ->> 'cash_sales')::numeric,
            (c ->> 'expenses')::numeric, (c ->> 'expected_cash')::numeric, v_counted,
            round(v_counted - (c ->> 'expected_cash')::numeric, 2), c -> 'methods', v_notes)
    returning id into v_id;
    return la_obra_v2.ok(201, 'Corte guardado', jsonb_build_object('cut', c || jsonb_build_object(
      'id', v_id, 'counted_cash', v_counted::float8, 'difference', round(v_counted - (c ->> 'expected_cash')::numeric, 2)::float8)));
  end if;
  perform la_obra_v2.fail(405, 'Método no permitido');
  return null;
end $$;

-- ---------- Permisos (igual que el archivo 10: nada del esquema privado es público) ----------
revoke all on all tables in schema la_obra_v2 from public;
revoke all on all functions in schema la_obra_v2 from public;
revoke all on all sequences in schema la_obra_v2 from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all tables in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all functions in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all sequences in schema la_obra_v2 from anon, authenticated';
  end if;
end $$;

notify pgrst, 'reload schema';

select 'Caja lista: ' || count(*) || ' rutas de caja' as resultado
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'la_obra_v2' and p.proname in ('ep_cash__opening', 'ep_cash__cut');
