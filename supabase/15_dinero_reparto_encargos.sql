-- =====================================================================
-- La Obra v2 · 15 · Dinero, reparto de la venta, "nos deben" y encargos
-- Se puede correr solo (Supabase → SQL Editor → New query → pegar → Run) sobre una base ya
-- instalada, y se puede volver a correr. No borra datos.
--
--  · Cuentas: Efectivo, Banco (tarjeta) y tus apartados. Hay dos tipos de apartado:
--      - Gasto fijo: una cantidad fija por día (ej. $300).
--      - Por porcentaje: un % de lo que sobra después de los gastos fijos.
--    Se agregan, cambian o archivan desde la app (Dinero → Cómo reparto mi venta).
--  · Saldo de cada cuenta = movimientos + ventas (menos comisión) − gastos − compras,
--    contados desde que se creó la cuenta. "Ajustar saldo" corrige con la realidad.
--  · Reparto del día (en el corte): venta del día − gastos fijos = sobrante; a cada apartado
--    le toca su % del sobrante. Se guarda como cambio de la cuenta origen a cada apartado.
--  · Nos deben: quién, cuánto, por qué; se cobra en partes.
--  · Encargos: quién va, a dónde, qué compra con su costo estimado, cuánto se le da.
--    Al cerrarlo se pone lo que gastó: queda como gasto y la app dice cuánto devuelve
--    o cuánto hay que reponerle.
--  · Planes y créditos: se quedan como pantalla de muestra, pero ya no bloquean nada.
-- =====================================================================
set check_function_bodies = off;

-- ---------- Tablas ----------
create table if not exists la_obra_v2.money_accounts (
  id             serial primary key,
  name           varchar(60) not null,
  kind           text not null check (kind in ('cash','bank','fixed','percent')),
  value          numeric(12,2) not null default 0 check (value >= 0),
  sort           int not null default 0,
  status         text not null default 'active' check (status in ('active','archived')),
  tracking_since timestamp not null default localtimestamp,
  created_at     timestamp not null default localtimestamp
);

create table if not exists la_obra_v2.money_settings (
  id                int primary key default 1 check (id = 1),
  round_step        numeric(8,2) not null default 5,
  round_mode        text not null default 'down' check (round_mode in ('down','up','nearest','none')),
  source_account_id int null references la_obra_v2.money_accounts(id),
  updated_at        timestamp null
);

create table if not exists la_obra_v2.money_movements (
  id            serial primary key,
  account_id    int not null references la_obra_v2.money_accounts(id),
  amount        numeric(12,2) not null,
  kind          text not null check (kind in ('in','out','transfer','adjust','reserve','errand','debt','debt_payment')),
  reason        varchar(255) not null,
  moved_at      timestamp not null default localtimestamp,
  group_id      int null,
  ref_type      text null,
  ref_id        int null,
  user_id       int not null references la_obra_v2.users(id),
  status        text not null default 'active' check (status in ('active','cancelled')),
  cancelled_at  timestamp null,
  cancel_reason varchar(255) null,
  created_at    timestamp not null default localtimestamp
);
create index if not exists idx_money_mov_account on la_obra_v2.money_movements(account_id, moved_at);
create index if not exists idx_money_mov_ref on la_obra_v2.money_movements(ref_type, ref_id);
create sequence if not exists la_obra_v2.money_group_seq;

create table if not exists la_obra_v2.money_reserves (
  id                serial primary key,
  business_date     date not null unique,
  total_sales       numeric(12,2) not null,
  fixed_total       numeric(12,2) not null,
  leftover          numeric(12,2) not null,
  items             jsonb not null default '[]'::jsonb,
  source_account_id int not null references la_obra_v2.money_accounts(id),
  user_id           int not null references la_obra_v2.users(id),
  created_at        timestamp not null default localtimestamp,
  updated_at        timestamp null
);

create table if not exists la_obra_v2.money_debts (
  id            serial primary key,
  person        varchar(100) not null,
  reason        varchar(255) not null,
  amount        numeric(12,2) not null check (amount > 0),
  account_id    int null references la_obra_v2.money_accounts(id),
  status        text not null default 'open' check (status in ('open','paid','cancelled')),
  user_id       int not null references la_obra_v2.users(id),
  created_at    timestamp not null default localtimestamp,
  closed_at     timestamp null,
  cancel_reason varchar(255) null
);

create table if not exists la_obra_v2.errands (
  id             serial primary key,
  person         varchar(100) not null,
  place          varchar(150) null,
  items          jsonb not null default '[]'::jsonb,
  estimate_total numeric(12,2) not null default 0,
  given          numeric(12,2) not null default 0 check (given >= 0),
  account_id     int not null references la_obra_v2.money_accounts(id),
  status         text not null default 'open' check (status in ('open','closed','cancelled')),
  spent          numeric(12,2) null,
  expense_id     int null references la_obra_v2.expenses(id),
  note           varchar(255) null,
  user_id        int not null references la_obra_v2.users(id),
  created_at     timestamp not null default localtimestamp,
  closed_at      timestamp null,
  closed_by      int null references la_obra_v2.users(id)
);
create index if not exists idx_errands_status on la_obra_v2.errands(status, created_at);

alter table la_obra_v2.payment_methods add column if not exists account_id int null references la_obra_v2.money_accounts(id);
alter table la_obra_v2.expenses add column if not exists account_id int null references la_obra_v2.money_accounts(id);

-- Cuentas iniciales (solo si no hay ninguna; también después de restaurar un respaldo viejo)
create or replace function la_obra_v2.money_ensure_defaults()
returns void language plpgsql as $$
begin
  if not exists (select 1 from la_obra_v2.money_accounts) then
    insert into la_obra_v2.money_accounts(name, kind, value, sort) values
      ('Efectivo', 'cash', 0, 1),
      ('Banco (tarjeta)', 'bank', 0, 2),
      ('Gasto fijo', 'fixed', 0, 10),
      ('Ahorro', 'percent', 5, 20),
      ('Gasto fuerte', 'percent', 5, 21),
      ('Mantenimiento', 'percent', 5, 22),
      ('Salario', 'percent', 5, 23);
  end if;
  insert into la_obra_v2.money_settings(id) values (1) on conflict (id) do nothing;
end $$;
select la_obra_v2.money_ensure_defaults();

-- El respaldo también guarda el dinero (en orden: las cuentas antes que métodos de pago y gastos)
create or replace function la_obra_v2.backup_tables()
returns text[] language sql immutable as $$
  select array['users','sessions','money_accounts','money_settings','categories','payment_methods','inputs','input_units','products',
               'preparations','preparation_inputs','recipes','product_components','orders','order_items','payments','purchases',
               'purchase_items','purchase_history','expenses','expense_history','waste_records','inventory_movements',
               'order_test_invoices','work_location','attendance','notes','money_movements','money_reserves','money_debts','errands'];
$$;

-- ---------- Utilidades ----------
create or replace function la_obra_v2.money_cash_account()
returns int language sql stable as $$
  select id from la_obra_v2.money_accounts where kind = 'cash' and status = 'active' order by sort, id limit 1;
$$;

create or replace function la_obra_v2.money_bank_account()
returns int language sql stable as $$
  select id from la_obra_v2.money_accounts where kind = 'bank' and status = 'active' order by sort, id limit 1;
$$;

-- A qué cuenta cae el dinero de un método de pago (si no se eligió: Efectivo → Efectivo; lo demás → Banco)
create or replace function la_obra_v2.money_method_account(p_method int)
returns int language sql stable as $$
  select coalesce(pm.account_id,
           case when lower(btrim(pm.name)) = 'efectivo' then la_obra_v2.money_cash_account()
                else coalesce(la_obra_v2.money_bank_account(), la_obra_v2.money_cash_account()) end)
    from la_obra_v2.payment_methods pm where pm.id = p_method;
$$;

-- De qué cuenta salen los apartados del día
create or replace function la_obra_v2.money_source_account()
returns int language sql stable as $$
  select coalesce((select s.source_account_id from la_obra_v2.money_settings s
                     join la_obra_v2.money_accounts a on a.id = s.source_account_id and a.status = 'active' where s.id = 1),
                  la_obra_v2.money_bank_account(), la_obra_v2.money_cash_account());
$$;

create or replace function la_obra_v2.money_balance(p_account int)
returns numeric language plpgsql stable as $$
declare a la_obra_v2.money_accounts; v_mov numeric; v_sales numeric; v_exp numeric; v_pur numeric;
begin
  select * into a from la_obra_v2.money_accounts where id = p_account;
  if a.id is null then return 0; end if;
  select coalesce(sum(amount), 0) into v_mov from la_obra_v2.money_movements where account_id = a.id and status = 'active';
  select coalesce(sum(pay.amount - coalesce(pay.commission_amount, 0)), 0) into v_sales
    from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id
   where o.order_status <> 'cancelled' and o.payment_status = 'paid' and pay.paid_at >= a.tracking_since
     and la_obra_v2.money_method_account(pay.payment_method_id) = a.id;
  select coalesce(sum(amount), 0) into v_exp from la_obra_v2.expenses
   where status = 'active' and created_at >= a.tracking_since
     and coalesce(account_id, la_obra_v2.money_cash_account()) = a.id;
  select coalesce(sum(total), 0) into v_pur from la_obra_v2.purchases
   where created_at >= a.tracking_since and la_obra_v2.money_method_account(payment_method_id) = a.id;
  return round(v_mov + v_sales - v_exp - v_pur, 2);
end $$;

create or replace function la_obra_v2.money_account_json(a la_obra_v2.money_accounts, p_with_balance boolean default true)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind, 'value', a.value::float8, 'sort', a.sort,
           'status', a.status, 'tracking_since', a.tracking_since,
           'is_reserve', a.kind in ('fixed','percent'))
         || case when p_with_balance then jsonb_build_object('balance', la_obra_v2.money_balance(a.id)::float8) else '{}'::jsonb end;
$$;

create or replace function la_obra_v2.money_accounts_list(p_with_balance boolean default true, p_all boolean default false)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(la_obra_v2.money_account_json(a, p_with_balance) order by a.status, a.sort, a.id), '[]')
    from la_obra_v2.money_accounts a where p_all or a.status = 'active';
$$;

create or replace function la_obra_v2.money_settings_json()
returns jsonb language sql stable as $$
  select jsonb_build_object('round_step', s.round_step::float8, 'round_mode', s.round_mode,
           'source_account_id', la_obra_v2.money_source_account(),
           'methods', (select coalesce(jsonb_agg(jsonb_build_object('id', pm.id, 'name', pm.name,
                         'account_id', la_obra_v2.money_method_account(pm.id)) order by pm.id), '[]')
                         from la_obra_v2.payment_methods pm where pm.status = 'active'))
    from la_obra_v2.money_settings s where s.id = 1;
$$;

create or replace function la_obra_v2.money_round(p numeric, p_step numeric, p_mode text)
returns numeric language sql immutable as $$
  select case when p_mode = 'none' or coalesce(p_step, 0) <= 0 then round(p, 2)
              when p_mode = 'up' then ceil(p / p_step) * p_step
              when p_mode = 'nearest' then round(p / p_step) * p_step
              else floor(p / p_step) * p_step end;
$$;

-- Fecha y hora opcional del cuerpo ("2026-11-25T14:30" o "2026-11-25 14:30"); si no viene, ahora
create or replace function la_obra_v2.money_when(v jsonb)
returns timestamp language plpgsql as $$
declare s text := la_obra_v2.jstr(v); r timestamp;
begin
  if s = '' then return localtimestamp; end if;
  begin r := replace(s, 'T', ' ')::timestamp; exception when others then perform la_obra_v2.fail(422, 'Fecha y hora inválidas'); end;
  if r > localtimestamp + interval '5 minutes' then perform la_obra_v2.fail(422, 'La fecha no puede ser futura'); end if;
  return r;
end $$;

create or replace function la_obra_v2.money_active_account(v jsonb, p_message text default 'Elige una cuenta')
returns int language plpgsql as $$
declare v_id int;
begin
  if v is null or coalesce(la_obra_v2.jtext(v), '') = '' then perform la_obra_v2.fail(422, p_message); end if;
  v_id := la_obra_v2.positive_id(v, p_message);
  if not exists (select 1 from la_obra_v2.money_accounts where id = v_id and status = 'active') then
    perform la_obra_v2.fail(422, 'La cuenta no existe o está archivada');
  end if;
  return v_id;
end $$;

create or replace function la_obra_v2.money_reason(v jsonb, p_message text default 'Escribe el motivo')
returns text language plpgsql as $$
declare s text := la_obra_v2.jstr(v);
begin
  if s = '' then perform la_obra_v2.fail(422, p_message); end if;
  if char_length(s) > 255 then perform la_obra_v2.fail(422, 'El texto es demasiado largo'); end if;
  return s;
end $$;

create or replace function la_obra_v2.money_move(p_account int, p_amount numeric, p_kind text, p_reason text,
  p_user int, p_when timestamp default localtimestamp, p_group int default null, p_ref_type text default null, p_ref_id int default null)
returns int language plpgsql as $$
declare v_id int;
begin
  insert into la_obra_v2.money_movements(account_id, amount, kind, reason, moved_at, group_id, ref_type, ref_id, user_id)
  values (p_account, round(p_amount, 2), p_kind, left(p_reason, 255), coalesce(p_when, localtimestamp), p_group, p_ref_type, p_ref_id, p_user)
  returning id into v_id;
  return v_id;
end $$;

create or replace function la_obra_v2.money_cancel_ref(p_ref_type text, p_ref_id int, p_reason text)
returns void language sql as $$
  update la_obra_v2.money_movements set status = 'cancelled', cancelled_at = localtimestamp, cancel_reason = left(p_reason, 255)
   where ref_type = p_ref_type and ref_id = p_ref_id and status = 'active';
$$;

-- Lista de lo que pasó en una cuenta (movimientos, ventas por día, gastos y compras)
create or replace function la_obra_v2.money_account_history(p_account int, p_limit int default 80)
returns jsonb language plpgsql stable as $$
declare a la_obra_v2.money_accounts; r jsonb;
begin
  select * into a from la_obra_v2.money_accounts where id = p_account;
  select coalesce(jsonb_agg(x order by x ->> 'at' desc), '[]') into r from (
    select x from (
      select jsonb_build_object('type', 'movement', 'id', mv.id, 'kind', mv.kind, 'amount', mv.amount::float8, 'reason', mv.reason,
               'at', to_char(mv.moved_at, 'YYYY-MM-DD"T"HH24:MI:SS'), 'user_name', u.name, 'status', mv.status,
               'cancel_reason', mv.cancel_reason, 'group_id', mv.group_id, 'manual', mv.ref_type is null) x
        from la_obra_v2.money_movements mv join la_obra_v2.users u on u.id = mv.user_id where mv.account_id = a.id
      union all
      select jsonb_build_object('type', 'sales', 'amount', sum(pay.amount - coalesce(pay.commission_amount, 0))::float8,
               'reason', 'Ventas del día (' || count(*) || ')', 'at', to_char(max(pay.paid_at), 'YYYY-MM-DD"T"HH24:MI:SS'), 'status', 'active')
        from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id
       where o.order_status <> 'cancelled' and o.payment_status = 'paid' and pay.paid_at >= a.tracking_since
         and la_obra_v2.money_method_account(pay.payment_method_id) = a.id
       group by pay.paid_at::date
      union all
      select jsonb_build_object('type', 'expense', 'id', e.id, 'amount', (-e.amount)::float8, 'reason', 'Gasto: ' || e.reason,
               'at', to_char(e.created_at, 'YYYY-MM-DD"T"HH24:MI:SS'), 'status', 'active')
        from la_obra_v2.expenses e
       where e.status = 'active' and e.created_at >= a.tracking_since and coalesce(e.account_id, la_obra_v2.money_cash_account()) = a.id
      union all
      select jsonb_build_object('type', 'purchase', 'id', p.id, 'amount', (-p.total)::float8,
               'reason', 'Compra' || coalesce(' en ' || nullif(p.supplier, ''), ''),
               'at', to_char(p.created_at, 'YYYY-MM-DD"T"HH24:MI:SS'), 'status', 'active')
        from la_obra_v2.purchases p
       where p.created_at >= a.tracking_since and la_obra_v2.money_method_account(p.payment_method_id) = a.id
    ) all_rows order by x ->> 'at' desc limit p_limit
  ) lim;
  return r;
end $$;

-- ---------- Reparto del día ----------
create or replace function la_obra_v2.money_reserve_calc(p_date date)
returns jsonb language plpgsql stable as $$
declare v_total numeric; v_fixed numeric := 0; v_left numeric; v_room numeric; s la_obra_v2.money_settings;
        v_items jsonb := '[]'; a record; v_exact numeric; v_saved la_obra_v2.money_reserves; v_pct numeric := 0;
begin
  select * into s from la_obra_v2.money_settings where id = 1;
  select coalesce(sum(pay.amount), 0) into v_total
    from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id
   where o.order_status <> 'cancelled' and o.payment_status = 'paid' and pay.paid_at::date = p_date;

  -- 1) Gastos fijos, en orden; si la venta no alcanza, se cubren hasta donde llegue
  v_room := v_total;
  for a in select * from la_obra_v2.money_accounts where status = 'active' and kind = 'fixed' order by sort, id loop
    v_exact := least(a.value, greatest(v_room, 0));
    v_room := v_room - v_exact;
    v_fixed := v_fixed + v_exact;
    v_items := v_items || jsonb_build_array(jsonb_build_object('account_id', a.id, 'name', a.name, 'kind', 'fixed',
                 'value', a.value::float8, 'exact', v_exact::float8, 'suggested', v_exact::float8, 'short', a.value > v_exact));
  end loop;
  v_left := greatest(v_total - v_fixed, 0);

  -- 2) Apartados por porcentaje del sobrante
  for a in select * from la_obra_v2.money_accounts where status = 'active' and kind = 'percent' order by sort, id loop
    v_exact := round(v_left * a.value / 100, 2);
    v_pct := v_pct + a.value;
    v_items := v_items || jsonb_build_array(jsonb_build_object('account_id', a.id, 'name', a.name, 'kind', 'percent',
                 'value', a.value::float8, 'exact', v_exact::float8,
                 'suggested', greatest(la_obra_v2.money_round(v_exact, s.round_step, s.round_mode), 0)::float8));
  end loop;

  select * into v_saved from la_obra_v2.money_reserves where business_date = p_date;
  return jsonb_build_object(
    'date', p_date, 'total_sales', round(v_total, 2)::float8, 'fixed_total', round(v_fixed, 2)::float8,
    'leftover', round(v_left, 2)::float8, 'percent_total', v_pct::float8, 'items', v_items,
    'source_account_id', la_obra_v2.money_source_account(),
    'source_name', (select name from la_obra_v2.money_accounts where id = la_obra_v2.money_source_account()),
    'round_step', s.round_step::float8, 'round_mode', s.round_mode,
    'saved', case when v_saved.id is null then null else jsonb_build_object('id', v_saved.id, 'items', v_saved.items,
               'total_sales', v_saved.total_sales::float8, 'created_at', v_saved.created_at, 'updated_at', v_saved.updated_at,
               'user_name', (select name from la_obra_v2.users where id = v_saved.user_id)) end);
end $$;

-- ---------- Corte de caja (reemplaza la del archivo 11) ----------
-- Ahora solo resta los gastos pagados con Efectivo, y suma los movimientos de Efectivo del día
-- (dinero entregado para encargos, depósitos, préstamos, cobros…). Los ajustes de saldo no cuentan.
create or replace function la_obra_v2.cash_cut_calc(p_date date)
returns jsonb language plpgsql stable as $$
declare v_fund numeric; v_methods jsonb; v_total numeric; v_cash numeric; v_exp numeric; v_pending record; v_count int;
        v_cash_acc int := la_obra_v2.money_cash_account(); v_moves numeric;
begin
  select coalesce((select amount from la_obra_v2.cash_openings where business_date = p_date), 0) into v_fund;

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

  select coalesce(sum(amount), 0) into v_exp from la_obra_v2.expenses
   where status = 'active' and created_at::date = p_date and coalesce(account_id, v_cash_acc) is not distinct from v_cash_acc;

  select coalesce(sum(amount), 0) into v_moves from la_obra_v2.money_movements
   where account_id = v_cash_acc and status = 'active' and kind <> 'adjust' and moved_at::date = p_date;

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
                       where e.status = 'active' and e.created_at::date = p_date
                         and coalesce(e.account_id, v_cash_acc) is not distinct from v_cash_acc),
    'cash_moves', round(v_moves, 2)::float8,
    'cash_moves_list', (select coalesce(jsonb_agg(jsonb_build_object('id', mv.id, 'amount', mv.amount::float8, 'reason', mv.reason,
                          'user_name', u.name, 'created_at', mv.moved_at) order by mv.moved_at, mv.id), '[]')
                          from la_obra_v2.money_movements mv join la_obra_v2.users u on u.id = mv.user_id
                         where mv.account_id = v_cash_acc and mv.status = 'active' and mv.kind <> 'adjust' and mv.moved_at::date = p_date),
    'cash_from_sales', round(v_cash - v_exp + v_moves, 2)::float8,
    'expected_cash', round(v_fund + v_cash - v_exp + v_moves, 2)::float8,
    'pending_orders', v_pending.n,
    'pending_amount', round(v_pending.amount, 2)::float8);
end $$;

-- ---------- Gastos: ahora dicen de qué cuenta salió el dinero ----------
create or replace function la_obra_v2.ep_expenses__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_amount numeric; v_reason text; v_id int; v_acc int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_amount := la_obra_v2.money(b -> 'amount');
  v_reason := la_obra_v2.jstr(b -> 'reason');
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo inválido'); end if;
  if coalesce(la_obra_v2.jtext(b -> 'account_id'), '') <> '' then v_acc := la_obra_v2.money_active_account(b -> 'account_id'); end if;
  insert into la_obra_v2.expenses(amount, reason, user_id, status, account_id) values (v_amount, v_reason, u.id, 'active', v_acc) returning id into v_id;
  return la_obra_v2.ok(201, 'Gasto registrado correctamente', jsonb_build_object('expense', la_obra_v2.expense_json(v_id)));
end $$;

create or replace function la_obra_v2.ep_expenses__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_why text; v_old jsonb; v_amount numeric; v_reason text; v_new jsonb; v_acc int;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_why := coalesce(nullif(la_obra_v2.jstr(b -> 'change_reason'), ''), 'Corrección');
  if char_length(v_why) > 255 then perform la_obra_v2.fail(422, 'El motivo es demasiado largo'); end if;
  v_old := la_obra_v2.expense_json(v_id, true);
  perform la_obra_v2.expense_access(v_old, u);
  if v_old ->> 'status' <> 'active' then perform la_obra_v2.fail(409, 'El gasto ya está cancelado'); end if;
  v_amount := case when b ? 'amount' then la_obra_v2.money(b -> 'amount') else (v_old ->> 'amount')::numeric end;
  v_reason := case when b ? 'reason' then la_obra_v2.jstr(b -> 'reason') else v_old ->> 'reason' end;
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo del gasto inválido'); end if;
  v_acc := case when not (b ? 'account_id') then (v_old ->> 'account_id')::int
                when coalesce(la_obra_v2.jtext(b -> 'account_id'), '') = '' then null
                else la_obra_v2.money_active_account(b -> 'account_id') end;
  update la_obra_v2.expenses set amount = v_amount, reason = v_reason, account_id = v_acc, updated_at = localtimestamp where id = v_id;
  v_new := la_obra_v2.expense_json(v_id);
  insert into la_obra_v2.expense_history(expense_id, action, previous_data, new_data, change_reason, changed_by)
  values (v_id, 'updated', v_old::text, v_new::text, v_why, u.id);
  return la_obra_v2.ok(200, 'Gasto actualizado correctamente', jsonb_build_object('expense', v_new));
end $$;

-- ---------- money/accounts (lista corta para elegir cuenta; cualquier usuario) ----------
create or replace function la_obra_v2.ep_money__accounts(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users;
begin
  perform la_obra_v2.money_ensure_defaults();
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  return la_obra_v2.ok(200, 'Cuentas', jsonb_build_object('accounts', la_obra_v2.money_accounts_list(false),
    'cash_account_id', la_obra_v2.money_cash_account()));
end $$;

-- ---------- money/summary ----------
create or replace function la_obra_v2.ep_money__summary(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users;
begin
  perform la_obra_v2.money_ensure_defaults();
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t, true);
  return la_obra_v2.ok(200, 'Dinero', jsonb_build_object(
    'accounts', la_obra_v2.money_accounts_list(true, true),
    'settings', la_obra_v2.money_settings_json(),
    'debts', (select coalesce(jsonb_agg(la_obra_v2.money_debt_json(d.id) order by d.status = 'open' desc, d.created_at desc), '[]')
                from la_obra_v2.money_debts d where d.status = 'open' or d.closed_at > localtimestamp - interval '30 days'),
    'open_errands', (select count(*) from la_obra_v2.errands where status = 'open'),
    'today', la_obra_v2.money_reserve_calc(current_date)));
end $$;

-- ---------- money/account (historial de una cuenta) ----------
create or replace function la_obra_v2.ep_money__account(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; a la_obra_v2.money_accounts;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.qparam(q, 'id'));
  select * into a from la_obra_v2.money_accounts where id = v_id;
  if a.id is null then perform la_obra_v2.fail(404, 'Cuenta no encontrada'); end if;
  return la_obra_v2.ok(200, 'Cuenta', jsonb_build_object('account', la_obra_v2.money_account_json(a),
    'history', la_obra_v2.money_account_history(a.id)));
end $$;

-- ---------- money/account-save { id?, name, kind, value, sort? } ----------
create or replace function la_obra_v2.ep_money__account_save(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_name text; v_kind text; v_value numeric; a la_obra_v2.money_accounts;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_name := la_obra_v2.jstr(b -> 'name');
  if v_name = '' or char_length(v_name) > 60 then perform la_obra_v2.fail(422, 'Escribe un nombre (máx. 60 letras)'); end if;
  v_kind := la_obra_v2.jstr(b -> 'kind');
  if v_kind not in ('cash','bank','fixed','percent') then perform la_obra_v2.fail(422, 'Tipo de cuenta inválido'); end if;
  v_value := case when v_kind in ('fixed','percent') then la_obra_v2.money(coalesce(b -> 'value', '0'::jsonb), false) else 0 end;
  if v_kind = 'percent' and v_value > 100 then perform la_obra_v2.fail(422, 'El porcentaje no puede pasar de 100'); end if;

  if coalesce(la_obra_v2.jtext(b -> 'id'), '') <> '' then
    v_id := la_obra_v2.positive_id(b -> 'id');
    select * into a from la_obra_v2.money_accounts where id = v_id for update;
    if a.id is null then perform la_obra_v2.fail(404, 'Cuenta no encontrada'); end if;
    -- Una cuenta con dinero no cambia entre "apartado" y "efectivo/banco" para no confundir saldos
    update la_obra_v2.money_accounts set name = v_name, kind = v_kind, value = v_value,
           sort = coalesce(la_obra_v2.num(b -> 'sort')::int, sort), status = 'active' where id = v_id;
  else
    insert into la_obra_v2.money_accounts(name, kind, value, sort)
    values (v_name, v_kind, v_value, coalesce(la_obra_v2.num(b -> 'sort')::int,
            (select coalesce(max(sort), 0) + 1 from la_obra_v2.money_accounts)))
    returning id into v_id;
  end if;
  return la_obra_v2.ok(200, 'Cuenta guardada', jsonb_build_object('accounts', la_obra_v2.money_accounts_list(true, true)));
end $$;

-- ---------- money/account-archive { id } ----------
create or replace function la_obra_v2.ep_money__account_archive(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; a la_obra_v2.money_accounts; v_bal numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select * into a from la_obra_v2.money_accounts where id = v_id for update;
  if a.id is null then perform la_obra_v2.fail(404, 'Cuenta no encontrada'); end if;
  if a.kind in ('cash','bank') and (select count(*) from la_obra_v2.money_accounts where kind = a.kind and status = 'active') <= 1 then
    perform la_obra_v2.fail(409, 'Debe quedar al menos una cuenta de ' || case when a.kind = 'cash' then 'efectivo' else 'banco' end);
  end if;
  v_bal := la_obra_v2.money_balance(a.id);
  if v_bal <> 0 then
    perform la_obra_v2.fail(409, 'La cuenta todavía tiene ' || to_char(v_bal, 'FM$999,999,990.00') ||
      '. Pásalo a otra cuenta (Movimiento → Cambio entre cuentas) y luego archívala.');
  end if;
  update la_obra_v2.money_accounts set status = 'archived' where id = v_id;
  update la_obra_v2.payment_methods set account_id = null where account_id = v_id;
  update la_obra_v2.money_settings set source_account_id = null where source_account_id = v_id;
  return la_obra_v2.ok(200, 'Cuenta archivada', jsonb_build_object('accounts', la_obra_v2.money_accounts_list(true, true)));
end $$;

-- ---------- money/settings { round_step, round_mode, source_account_id, methods:[{id, account_id}] } ----------
create or replace function la_obra_v2.ep_money__settings(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_step numeric; v_mode text; x jsonb;
begin
  u := la_obra_v2.auth(t, true);
  if m = 'GET' then
    return la_obra_v2.ok(200, 'Configuración', jsonb_build_object('settings', la_obra_v2.money_settings_json(),
      'accounts', la_obra_v2.money_accounts_list(false)));
  end if;
  perform la_obra_v2.method(m, 'POST');
  b := la_obra_v2.body(b);
  if b ? 'round_step' then
    v_step := la_obra_v2.num(b -> 'round_step');
    if v_step is null or v_step not in (1, 5, 10, 50, 100) then perform la_obra_v2.fail(422, 'Redondeo inválido'); end if;
    update la_obra_v2.money_settings set round_step = v_step where id = 1;
  end if;
  if b ? 'round_mode' then
    v_mode := la_obra_v2.jstr(b -> 'round_mode');
    if v_mode not in ('down','up','nearest','none') then perform la_obra_v2.fail(422, 'Redondeo inválido'); end if;
    update la_obra_v2.money_settings set round_mode = v_mode where id = 1;
  end if;
  if b ? 'source_account_id' then
    update la_obra_v2.money_settings set source_account_id = la_obra_v2.money_active_account(b -> 'source_account_id') where id = 1;
  end if;
  if jsonb_typeof(b -> 'methods') = 'array' then
    for x in select * from jsonb_array_elements(b -> 'methods') loop
      update la_obra_v2.payment_methods set account_id = la_obra_v2.money_active_account(x -> 'account_id')
       where id = la_obra_v2.positive_id(x -> 'id');
    end loop;
  end if;
  update la_obra_v2.money_settings set updated_at = localtimestamp where id = 1;
  return la_obra_v2.ok(200, 'Configuración guardada', jsonb_build_object('settings', la_obra_v2.money_settings_json()));
end $$;

-- ---------- money/movement { type: in|out|transfer, account_id, to_account_id?, amount, reason, moved_at? } ----------
create or replace function la_obra_v2.ep_money__movement(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_type text; v_from int; v_to int; v_amount numeric; v_reason text; v_when timestamp; v_group int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_type := la_obra_v2.jstr(b -> 'type');
  if v_type not in ('in','out','transfer') then perform la_obra_v2.fail(422, 'Tipo de movimiento inválido'); end if;
  v_from := la_obra_v2.money_active_account(b -> 'account_id');
  v_amount := la_obra_v2.money(b -> 'amount');
  v_reason := la_obra_v2.money_reason(b -> 'reason');
  v_when := la_obra_v2.money_when(b -> 'moved_at');
  if v_type = 'transfer' then
    v_to := la_obra_v2.money_active_account(b -> 'to_account_id', 'Elige a qué cuenta pasa el dinero');
    if v_to = v_from then perform la_obra_v2.fail(422, 'Elige dos cuentas distintas'); end if;
    v_group := nextval('la_obra_v2.money_group_seq');
    perform la_obra_v2.money_move(v_from, -v_amount, 'transfer', v_reason, u.id, v_when, v_group);
    perform la_obra_v2.money_move(v_to, v_amount, 'transfer', v_reason, u.id, v_when, v_group);
  else
    perform la_obra_v2.money_move(v_from, case when v_type = 'in' then v_amount else -v_amount end, v_type, v_reason, u.id, v_when);
  end if;
  return la_obra_v2.ok(201, 'Movimiento registrado', jsonb_build_object('accounts', la_obra_v2.money_accounts_list(true, true)));
end $$;

-- ---------- money/movement-cancel { id, reason } (anula también la otra mitad de un cambio entre cuentas) ----------
create or replace function la_obra_v2.ep_money__movement_cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; mv la_obra_v2.money_movements; v_reason text;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_reason := la_obra_v2.money_reason(b -> 'reason');
  select * into mv from la_obra_v2.money_movements where id = v_id for update;
  if mv.id is null then perform la_obra_v2.fail(404, 'Movimiento no encontrado'); end if;
  if mv.status <> 'active' then perform la_obra_v2.fail(409, 'El movimiento ya estaba anulado'); end if;
  if mv.ref_type is not null then
    perform la_obra_v2.fail(409, 'Este movimiento viene de ' || case mv.ref_type when 'reserve' then 'los apartados del corte'
      when 'errand' then 'un encargo' when 'debt' then '"Nos deben"' else 'otra pantalla' end || '; corrígelo desde ahí.');
  end if;
  update la_obra_v2.money_movements set status = 'cancelled', cancelled_at = localtimestamp, cancel_reason = v_reason
   where status = 'active' and (id = mv.id or (mv.group_id is not null and group_id = mv.group_id));
  return la_obra_v2.ok(200, 'Movimiento anulado', jsonb_build_object('accounts', la_obra_v2.money_accounts_list(true, true)));
end $$;

-- ---------- money/adjust { account_id, real_balance, reason } ----------
create or replace function la_obra_v2.ep_money__adjust(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_acc int; v_real numeric; v_reason text; v_diff numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_acc := la_obra_v2.money_active_account(b -> 'account_id');
  if not la_obra_v2.is_num(b -> 'real_balance') then perform la_obra_v2.fail(422, 'Escribe cuánto hay de verdad'); end if;
  v_real := round(la_obra_v2.num(b -> 'real_balance'), 2);
  v_reason := la_obra_v2.money_reason(b -> 'reason');
  v_diff := v_real - la_obra_v2.money_balance(v_acc);
  if v_diff = 0 then
    return la_obra_v2.ok(200, 'El saldo ya era ese', jsonb_build_object('accounts', la_obra_v2.money_accounts_list(true, true)));
  end if;
  perform la_obra_v2.money_move(v_acc, v_diff, 'adjust', v_reason, u.id);
  return la_obra_v2.ok(201, 'Saldo ajustado', jsonb_build_object('difference', v_diff::float8,
    'accounts', la_obra_v2.money_accounts_list(true, true)));
end $$;

-- ---------- money/reserve  GET ?date → cálculo · POST { date, items:[{account_id, amount}] } → guarda ----------
create or replace function la_obra_v2.ep_money__reserve(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_date date; c jsonb; x jsonb; v_src int; v_amt numeric; v_acc int; v_items jsonb := '[]';
        r la_obra_v2.money_reserves; v_name text; v_when timestamp;
begin
  u := la_obra_v2.auth(t, true);
  if m = 'GET' then
    v_date := la_obra_v2.cash_day(u, la_obra_v2.qparam(q, 'date'));
    return la_obra_v2.ok(200, 'Reparto del día', jsonb_build_object('reserve', la_obra_v2.money_reserve_calc(v_date)));
  end if;
  perform la_obra_v2.method(m, 'POST');
  b := la_obra_v2.body(b);
  v_date := la_obra_v2.cash_day(u, b -> 'date');
  if jsonb_typeof(b -> 'items') <> 'array' then perform la_obra_v2.fail(422, 'Faltan los montos'); end if;
  c := la_obra_v2.money_reserve_calc(v_date);
  v_src := la_obra_v2.money_source_account();
  v_when := case when v_date = current_date then localtimestamp else v_date + time '23:59' end;

  select * into r from la_obra_v2.money_reserves where business_date = v_date for update;
  if r.id is null then
    insert into la_obra_v2.money_reserves(business_date, total_sales, fixed_total, leftover, source_account_id, user_id)
    values (v_date, (c ->> 'total_sales')::numeric, (c ->> 'fixed_total')::numeric, (c ->> 'leftover')::numeric, v_src, u.id)
    returning * into r;
  else
    perform la_obra_v2.money_cancel_ref('reserve', r.id, 'Se volvieron a guardar los apartados');
  end if;

  for x in select * from jsonb_array_elements(b -> 'items') loop
    v_acc := la_obra_v2.money_active_account(x -> 'account_id');
    v_amt := la_obra_v2.money(coalesce(x -> 'amount', '0'::jsonb), false);
    if v_amt = 0 or v_acc = v_src then continue; end if;
    select name into v_name from la_obra_v2.money_accounts where id = v_acc;
    perform la_obra_v2.money_move(v_src, -v_amt, 'reserve', 'Apartado ' || v_name || ' del ' || to_char(v_date, 'DD/MM'), u.id, v_when, null, 'reserve', r.id);
    perform la_obra_v2.money_move(v_acc, v_amt, 'reserve', 'Apartado del ' || to_char(v_date, 'DD/MM'), u.id, v_when, null, 'reserve', r.id);
    v_items := v_items || jsonb_build_array(jsonb_build_object('account_id', v_acc, 'name', v_name, 'amount', v_amt::float8));
  end loop;

  update la_obra_v2.money_reserves set items = v_items, total_sales = (c ->> 'total_sales')::numeric,
         fixed_total = (c ->> 'fixed_total')::numeric, leftover = (c ->> 'leftover')::numeric,
         source_account_id = v_src, user_id = u.id, updated_at = case when r.items <> '[]'::jsonb then localtimestamp end
   where id = r.id;
  return la_obra_v2.ok(200, 'Apartados guardados', jsonb_build_object('reserve', la_obra_v2.money_reserve_calc(v_date)));
end $$;

-- ---------- Nos deben ----------
create or replace function la_obra_v2.money_debt_json(p_id int)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', d.id, 'person', d.person, 'reason', d.reason, 'amount', d.amount::float8,
           'account_id', d.account_id, 'status', d.status, 'created_at', d.created_at, 'closed_at', d.closed_at,
           'cancel_reason', d.cancel_reason, 'user_name', u.name,
           'paid', coalesce((select sum(amount) from la_obra_v2.money_movements
                              where ref_type = 'debt' and ref_id = d.id and kind = 'debt_payment' and status = 'active'), 0)::float8,
           'payments', (select coalesce(jsonb_agg(jsonb_build_object('amount', mv.amount::float8, 'at', mv.moved_at,
                          'account', a.name) order by mv.moved_at), '[]')
                          from la_obra_v2.money_movements mv join la_obra_v2.money_accounts a on a.id = mv.account_id
                         where mv.ref_type = 'debt' and mv.ref_id = d.id and mv.kind = 'debt_payment' and mv.status = 'active'))
    from la_obra_v2.money_debts d join la_obra_v2.users u on u.id = d.user_id where d.id = p_id;
$$;

-- money/debt-save { person, amount, reason, account_id? (si se le prestó de una cuenta) }
create or replace function la_obra_v2.ep_money__debt_save(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_person text; v_amount numeric; v_reason text; v_acc int; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_person := la_obra_v2.jstr(b -> 'person');
  if v_person = '' or char_length(v_person) > 100 then perform la_obra_v2.fail(422, '¿Quién debe?'); end if;
  v_amount := la_obra_v2.money(b -> 'amount');
  v_reason := la_obra_v2.money_reason(b -> 'reason', '¿Por qué debe?');
  if coalesce(la_obra_v2.jtext(b -> 'account_id'), '') <> '' then v_acc := la_obra_v2.money_active_account(b -> 'account_id'); end if;
  insert into la_obra_v2.money_debts(person, reason, amount, account_id, user_id) values (v_person, v_reason, v_amount, v_acc, u.id)
  returning id into v_id;
  if v_acc is not null then
    perform la_obra_v2.money_move(v_acc, -v_amount, 'debt', 'Préstamo a ' || v_person || ': ' || v_reason, u.id, localtimestamp, null, 'debt', v_id);
  end if;
  return la_obra_v2.ok(201, 'Registrado', jsonb_build_object('debt', la_obra_v2.money_debt_json(v_id)));
end $$;

-- money/debt-collect { id, amount, account_id }
create or replace function la_obra_v2.ep_money__debt_collect(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; d la_obra_v2.money_debts; v_amount numeric; v_acc int; v_paid numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  select * into d from la_obra_v2.money_debts where id = la_obra_v2.positive_id(b -> 'id') for update;
  if d.id is null then perform la_obra_v2.fail(404, 'No encontrado'); end if;
  if d.status <> 'open' then perform la_obra_v2.fail(409, 'Ya está cerrado'); end if;
  v_amount := la_obra_v2.money(b -> 'amount');
  v_acc := la_obra_v2.money_active_account(b -> 'account_id', '¿A qué cuenta entra el dinero?');
  perform la_obra_v2.money_move(v_acc, v_amount, 'debt_payment', 'Pago de ' || d.person || ': ' || d.reason, u.id, localtimestamp, null, 'debt', d.id);
  v_paid := (la_obra_v2.money_debt_json(d.id) ->> 'paid')::numeric;
  if v_paid >= d.amount then update la_obra_v2.money_debts set status = 'paid', closed_at = localtimestamp where id = d.id; end if;
  return la_obra_v2.ok(200, case when v_paid >= d.amount then 'Pagado completo' else 'Pago registrado' end,
    jsonb_build_object('debt', la_obra_v2.money_debt_json(d.id)));
end $$;

-- money/debt-cancel { id, reason } (ya no se cobrará)
create or replace function la_obra_v2.ep_money__debt_cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; d la_obra_v2.money_debts; v_reason text;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  select * into d from la_obra_v2.money_debts where id = la_obra_v2.positive_id(b -> 'id') for update;
  if d.id is null then perform la_obra_v2.fail(404, 'No encontrado'); end if;
  if d.status <> 'open' then perform la_obra_v2.fail(409, 'Ya está cerrado'); end if;
  v_reason := la_obra_v2.money_reason(b -> 'reason');
  update la_obra_v2.money_debts set status = 'cancelled', closed_at = localtimestamp, cancel_reason = v_reason where id = d.id;
  return la_obra_v2.ok(200, 'Ya no se cobrará', jsonb_build_object('debt', la_obra_v2.money_debt_json(d.id)));
end $$;

-- ---------- Encargos de compra ----------
create or replace function la_obra_v2.errand_json(p_id int)
returns jsonb language sql stable as $$
  select la_obra_v2.fix_dates(jsonb_build_object('id', e.id, 'person', e.person, 'place', e.place, 'items', e.items,
           'estimate_total', e.estimate_total::float8, 'given', e.given::float8, 'account_id', e.account_id,
           'account_name', a.name, 'status', e.status, 'spent', e.spent::float8, 'expense_id', e.expense_id, 'note', e.note,
           'change', case when e.spent is null then null else (e.given - e.spent)::float8 end,
           'user_name', u.name, 'created_at', e.created_at, 'closed_at', e.closed_at, 'closed_by_name', cb.name))
    from la_obra_v2.errands e
    join la_obra_v2.money_accounts a on a.id = e.account_id
    join la_obra_v2.users u on u.id = e.user_id
    left join la_obra_v2.users cb on cb.id = e.closed_by
   where e.id = p_id;
$$;

-- Limpia la lista: [{ name, qty?, estimate?, real? }]
create or replace function la_obra_v2.errand_items(v jsonb)
returns jsonb language plpgsql as $$
declare x jsonb; r jsonb := '[]'; v_name text;
begin
  if v is null or jsonb_typeof(v) <> 'array' then return '[]'; end if;
  for x in select * from jsonb_array_elements(v) loop
    v_name := left(la_obra_v2.jstr(x -> 'name'), 120);
    if v_name = '' then continue; end if;
    r := r || jsonb_build_array(jsonb_build_object('name', v_name,
           'qty', nullif(left(la_obra_v2.jstr(x -> 'qty'), 40), ''),
           'estimate', case when la_obra_v2.is_num(x -> 'estimate') then round(abs(la_obra_v2.num(x -> 'estimate')), 2)::float8 end,
           'real', case when la_obra_v2.is_num(x -> 'real') then round(abs(la_obra_v2.num(x -> 'real')), 2)::float8 end));
  end loop;
  return r;
end $$;

-- errands/index ?status=open|closed|all
create or replace function la_obra_v2.ep_errands__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_status text := coalesce(la_obra_v2.jtext(la_obra_v2.qparam(q, 'status')), 'open');
begin
  perform la_obra_v2.money_ensure_defaults();
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  return la_obra_v2.ok(200, 'Encargos', jsonb_build_object(
    'errands', (select coalesce(jsonb_agg(la_obra_v2.errand_json(e.id) order by e.created_at desc), '[]')
                  from (select id, created_at from la_obra_v2.errands
                         where (v_status = 'all' or status = v_status)
                           and (v_status = 'open' or created_at > localtimestamp - interval '45 days')
                         order by created_at desc limit 60) e),
    'accounts', la_obra_v2.money_accounts_list(false),
    'cash_account_id', la_obra_v2.money_cash_account()));
end $$;

-- errands/save { id?, person, place?, items, given, account_id?, note? }
create or replace function la_obra_v2.ep_errands__save(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; e la_obra_v2.errands; v_person text; v_place text; v_items jsonb; v_est numeric;
        v_given numeric; v_acc int; v_note text;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_person := la_obra_v2.jstr(b -> 'person');
  if v_person = '' or char_length(v_person) > 100 then perform la_obra_v2.fail(422, '¿Quién va a comprar?'); end if;
  v_place := nullif(left(la_obra_v2.jstr(b -> 'place'), 150), '');
  v_items := la_obra_v2.errand_items(b -> 'items');
  if jsonb_array_length(v_items) = 0 then perform la_obra_v2.fail(422, 'Agrega al menos una cosa a la lista'); end if;
  select coalesce(sum((x ->> 'estimate')::numeric), 0) into v_est from jsonb_array_elements(v_items) x;
  v_given := la_obra_v2.money(coalesce(b -> 'given', '0'::jsonb), false);
  v_acc := case when coalesce(la_obra_v2.jtext(b -> 'account_id'), '') = '' then la_obra_v2.money_cash_account()
                else la_obra_v2.money_active_account(b -> 'account_id') end;
  v_note := nullif(left(la_obra_v2.jstr(b -> 'note'), 255), '');

  if coalesce(la_obra_v2.jtext(b -> 'id'), '') <> '' then
    v_id := la_obra_v2.positive_id(b -> 'id');
    select * into e from la_obra_v2.errands where id = v_id for update;
    if e.id is null then perform la_obra_v2.fail(404, 'Encargo no encontrado'); end if;
    if e.status <> 'open' then perform la_obra_v2.fail(409, 'El encargo ya está cerrado; ábrelo de nuevo para cambiarlo'); end if;
    update la_obra_v2.errands set person = v_person, place = v_place, items = v_items, estimate_total = v_est,
           given = v_given, account_id = v_acc, note = v_note where id = v_id;
    perform la_obra_v2.money_cancel_ref('errand', v_id, 'Se editó el encargo');
  else
    insert into la_obra_v2.errands(person, place, items, estimate_total, given, account_id, note, user_id)
    values (v_person, v_place, v_items, v_est, v_given, v_acc, v_note, u.id) returning id into v_id;
  end if;
  if v_given > 0 then
    perform la_obra_v2.money_move(v_acc, -v_given, 'errand', 'Entregado a ' || v_person || coalesce(' para comprar en ' || v_place, ' para un encargo'),
      u.id, localtimestamp, null, 'errand', v_id);
  end if;
  return la_obra_v2.ok(200, 'Encargo guardado', jsonb_build_object('errand', la_obra_v2.errand_json(v_id)));
end $$;

-- errands/close { id, spent, items? (con "real") } → gasto + regreso del dinero entregado
create or replace function la_obra_v2.ep_errands__close(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; e la_obra_v2.errands; v_spent numeric; v_items jsonb; v_exp int; v_reason text;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  select * into e from la_obra_v2.errands where id = la_obra_v2.positive_id(b -> 'id') for update;
  if e.id is null then perform la_obra_v2.fail(404, 'Encargo no encontrado'); end if;
  if e.status <> 'open' then perform la_obra_v2.fail(409, 'El encargo ya está cerrado'); end if;
  v_spent := la_obra_v2.money(coalesce(b -> 'spent', '0'::jsonb), false);
  v_items := case when jsonb_typeof(b -> 'items') = 'array' then la_obra_v2.errand_items(b -> 'items') else e.items end;
  if jsonb_array_length(v_items) = 0 then v_items := e.items; end if;

  -- El dinero entregado "regresa" y lo gastado sale como gasto: así el saldo queda en lo real
  -- (si gastó más de lo que se le dio, la diferencia se le repone de la misma cuenta).
  if e.given > 0 then
    perform la_obra_v2.money_move(e.account_id, e.given, 'errand', 'Cierre del encargo de ' || e.person, u.id, localtimestamp, null, 'errand', e.id);
  end if;
  if v_spent > 0 then
    v_reason := left('Encargo: ' || coalesce(e.place || ' · ', '') || e.person, 255);
    insert into la_obra_v2.expenses(amount, reason, user_id, status, account_id) values (v_spent, v_reason, u.id, 'active', e.account_id)
    returning id into v_exp;
  end if;
  update la_obra_v2.errands set status = 'closed', spent = v_spent, items = v_items, expense_id = v_exp,
         closed_at = localtimestamp, closed_by = u.id where id = e.id;
  return la_obra_v2.ok(200, case when v_spent > e.given then 'Encargo cerrado: hay que reponerle ' || to_char(v_spent - e.given, 'FM$999,990.00')
                                 when v_spent < e.given then 'Encargo cerrado: te devuelve ' || to_char(e.given - v_spent, 'FM$999,990.00')
                                 else 'Encargo cerrado: salió exacto' end,
    jsonb_build_object('errand', la_obra_v2.errand_json(e.id)));
end $$;

-- errands/reopen { id } → deshace el cierre
create or replace function la_obra_v2.ep_errands__reopen(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; e la_obra_v2.errands;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  select * into e from la_obra_v2.errands where id = la_obra_v2.positive_id(b -> 'id') for update;
  if e.id is null then perform la_obra_v2.fail(404, 'Encargo no encontrado'); end if;
  if e.status <> 'closed' then perform la_obra_v2.fail(409, 'El encargo no está cerrado'); end if;
  if e.expense_id is not null then
    update la_obra_v2.expenses set status = 'cancelled', cancelled_by = u.id, cancelled_at = localtimestamp,
           cancellation_reason = 'Se reabrió el encargo' where id = e.expense_id and status = 'active';
  end if;
  -- Quita el "regreso" del dinero entregado (el más reciente de este encargo) y deja la entrega
  update la_obra_v2.money_movements set status = 'cancelled', cancelled_at = localtimestamp, cancel_reason = 'Se reabrió el encargo'
   where id = (select id from la_obra_v2.money_movements where ref_type = 'errand' and ref_id = e.id and status = 'active' and amount > 0
                order by id desc limit 1);
  update la_obra_v2.errands set status = 'open', spent = null, expense_id = null, closed_at = null, closed_by = null where id = e.id;
  return la_obra_v2.ok(200, 'Encargo abierto de nuevo', jsonb_build_object('errand', la_obra_v2.errand_json(e.id)));
end $$;

-- errands/cancel { id } → no se hizo; el dinero entregado regresa
create or replace function la_obra_v2.ep_errands__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; e la_obra_v2.errands;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  select * into e from la_obra_v2.errands where id = la_obra_v2.positive_id(b -> 'id') for update;
  if e.id is null then perform la_obra_v2.fail(404, 'Encargo no encontrado'); end if;
  if e.status <> 'open' then perform la_obra_v2.fail(409, 'Solo se cancela un encargo abierto'); end if;
  perform la_obra_v2.money_cancel_ref('errand', e.id, 'Encargo cancelado');
  update la_obra_v2.errands set status = 'cancelled', closed_at = localtimestamp, closed_by = u.id where id = e.id;
  return la_obra_v2.ok(200, 'Encargo cancelado', jsonb_build_object('errand', la_obra_v2.errand_json(e.id)));
end $$;

-- ---------- Planes y créditos: ya no bloquean nada ----------
-- La pantalla "Plan y créditos" sigue existiendo (trabajo de la escuela), pero todas las
-- funciones quedan activas y sin límite de usuarios.
create or replace function la_obra_v2.billing_feature_active(p_business int, p_feature text)
returns boolean language sql stable as $$ select true; $$;

create or replace function la_obra_v2.billing_max_users(p_business int)
returns int language sql stable as $$ select null::int; $$;

create or replace function la_obra_v2.billing_gate(p_path text, p_token text)
returns jsonb language sql stable as $$ select null::jsonb; $$;

-- ---------- Permisos ----------
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

select 'Dinero, reparto y encargos listos: ' || count(*) || ' rutas nuevas' as resultado
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'la_obra_v2' and (p.proname like 'ep_money__%' or p.proname like 'ep_errands__%');
