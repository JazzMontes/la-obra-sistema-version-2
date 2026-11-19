-- =====================================================================
-- La Obra v2 · 13 · Planes de suscripción (Bronze, Silver, Gold) y créditos
--
-- Todo pertenece al NEGOCIO que contrata el sistema (tabla businesses), no a cada usuario:
--   · El plan, los créditos, los desbloqueos y los pagos son del negocio.
--   · Todos los usuarios del negocio (administradores y empleados) usan lo que el negocio tiene.
--   · Solo un administrador del negocio puede contratar, comprar créditos o desbloquear.
--
-- Cómo se controla el acceso (automático, en el servidor):
--   · La función pública la_obra_v2_api revisa cada petición con billing_gate(): si la ruta
--     pertenece a una función (inventario, reportes…) que el negocio no tiene vigente, responde
--     402 y no ejecuta nada. No depende de la app, así que no se puede saltar desde el navegador.
--   · Una función está vigente si la incluye el plan vigente o si hay un desbloqueo con créditos
--     que todavía no termina. Los vencimientos se calculan con la hora actual en cada petición:
--     no hace falta ninguna tarea programada para que algo se vuelva a bloquear.
--   · El límite de usuarios activos del plan se revisa con un disparador en la tabla users.
--
-- Solo AGREGA tablas y una columna (users.business_id); no borra ni cambia datos existentes.
-- Se puede volver a correr: los precios y planes que ya existan no se sobrescriben.
-- =====================================================================
set check_function_bodies = off;

-- Hora de México (las tablas guardan hora local, igual que el resto del sistema)
create or replace function la_obra_v2.mx_now()
returns timestamp language sql stable as $$
  select (now() at time zone 'America/Mexico_City')::timestamp(0);
$$;

-- ---------- Negocio que contrata el sistema ----------
create table if not exists la_obra_v2.businesses (
  id             serial primary key,
  name           varchar(120) not null,
  contact_email  varchar(150) null,
  credit_balance int not null default 0 check (credit_balance >= 0),
  created_at     timestamp not null default localtimestamp
);
insert into la_obra_v2.businesses(id, name)
select 1, 'La Obra' where not exists (select 1 from la_obra_v2.businesses);
select setval(pg_get_serial_sequence('la_obra_v2.businesses', 'id'),
              greatest((select max(id) from la_obra_v2.businesses), 1));

-- Cada usuario pertenece a un negocio (los actuales quedan en el negocio 1)
alter table la_obra_v2.users add column if not exists business_id int null
  references la_obra_v2.businesses(id) on delete set null;
update la_obra_v2.users set business_id = (select min(id) from la_obra_v2.businesses) where business_id is null;
create index if not exists idx_users_business on la_obra_v2.users(business_id);

create or replace function la_obra_v2.default_business()
returns int language sql stable as $$ select min(id) from la_obra_v2.businesses; $$;

-- ---------- Catálogo: funciones, planes y paquetes de créditos ----------
create table if not exists la_obra_v2.features (
  key              varchar(30) primary key,
  name             varchar(80) not null,
  description      varchar(255) not null default '',
  credits_per_hour int null check (credits_per_hour is null or credits_per_hour > 0),
  credits_per_day  int null check (credits_per_day is null or credits_per_day > 0),
  sort             smallint not null default 0
);

create table if not exists la_obra_v2.plans (
  code          varchar(20) primary key,
  name          varchar(40) not null,
  description   varchar(255) not null default '',
  monthly_price numeric(10,2) not null check (monthly_price >= 0),
  annual_price  numeric(10,2) not null check (annual_price >= 0),
  max_users     int null check (max_users is null or max_users > 0),   -- null = sin límite
  sort          smallint not null default 0,
  status        text not null default 'active' check (status in ('active','inactive'))
);

create table if not exists la_obra_v2.plan_features (
  plan_code   varchar(20) not null references la_obra_v2.plans(code) on delete cascade,
  feature_key varchar(30) not null references la_obra_v2.features(key) on delete cascade,
  primary key (plan_code, feature_key)
);

create table if not exists la_obra_v2.credit_packages (
  id      serial primary key,
  name    varchar(60) not null,
  credits int not null check (credits > 0),
  bonus   int not null default 0 check (bonus >= 0),
  price   numeric(10,2) not null check (price > 0),
  sort    smallint not null default 0,
  status  text not null default 'active' check (status in ('active','inactive'))
);

-- Ajustes del cobro (un solo renglón)
--   payment_mode 'simulated': el pago se aprueba al momento (modo de prueba, no se cobra dinero real)
--   payment_mode 'manual'   : el pago queda pendiente hasta que el proveedor lo confirme en el SQL Editor
create table if not exists la_obra_v2.billing_settings (
  id           smallint primary key default 1 check (id = 1),
  payment_mode text not null default 'simulated' check (payment_mode in ('simulated','manual')),
  trial_days   int not null default 30 check (trial_days >= 0),
  trial_plan   varchar(20) not null default 'gold',
  currency     varchar(3) not null default 'MXN',
  credit_value numeric(10,2) not null default 1.00 check (credit_value > 0),   -- pesos por crédito (para prorrateos)
  bank_info    varchar(255) not null default ''
);
insert into la_obra_v2.billing_settings(id) values (1) on conflict (id) do nothing;

-- ---------- Movimientos del negocio ----------
-- Sin llaves foráneas hacia users: así borrar o restaurar usuarios nunca borra el historial de cobros.
create table if not exists la_obra_v2.billing_payments (
  id              serial primary key,
  business_id     int not null references la_obra_v2.businesses(id) on delete cascade,
  concept         text not null check (concept in ('subscription','credits')),
  description     varchar(150) not null,
  amount          numeric(10,2) not null check (amount >= 0),
  method          text not null check (method in ('card_test','transfer','cash','provider')),
  reference       varchar(80) null,
  status          text not null default 'pending' check (status in ('pending','paid','rejected','cancelled')),
  details         jsonb not null default '{}'::jsonb,
  created_by      int null,
  created_by_name varchar(100) null,
  created_at      timestamp not null default localtimestamp,
  resolved_at     timestamp null,
  resolved_note   varchar(255) null
);
create index if not exists idx_bpay_business on la_obra_v2.billing_payments(business_id, created_at);

create table if not exists la_obra_v2.subscriptions (
  id            serial primary key,
  business_id   int not null references la_obra_v2.businesses(id) on delete cascade,
  plan_code     varchar(20) not null references la_obra_v2.plans(code),
  billing_cycle text not null check (billing_cycle in ('monthly','annual','trial','gift')),
  price         numeric(10,2) not null default 0,
  starts_at     timestamp not null,
  ends_at       timestamp not null,
  status        text not null default 'active' check (status in ('active','replaced','cancelled')),
  payment_id    int null references la_obra_v2.billing_payments(id) on delete set null,
  created_by    int null,
  created_at    timestamp not null default localtimestamp,
  closed_at     timestamp null,
  check (ends_at > starts_at)
);
create index if not exists idx_subs_business on la_obra_v2.subscriptions(business_id, starts_at);

create table if not exists la_obra_v2.feature_unlocks (
  id              serial primary key,
  business_id     int not null references la_obra_v2.businesses(id) on delete cascade,
  feature_key     varchar(30) not null references la_obra_v2.features(key),
  duration_unit   text not null check (duration_unit in ('hour','day')),
  duration_qty    int not null check (duration_qty > 0),
  credits_spent   int not null check (credits_spent >= 0),
  starts_at       timestamp not null,
  ends_at         timestamp not null,
  created_by      int null,
  created_by_name varchar(100) null,
  created_at      timestamp not null default localtimestamp,
  check (ends_at > starts_at)
);
create index if not exists idx_unlocks_business on la_obra_v2.feature_unlocks(business_id, feature_key, ends_at);

-- Libro de créditos: cada entrada o salida con el saldo que quedó
create table if not exists la_obra_v2.credit_transactions (
  id              serial primary key,
  business_id     int not null references la_obra_v2.businesses(id) on delete cascade,
  type            text not null check (type in ('purchase','bonus','spend','proration','refund','adjust')),
  amount          int not null,
  balance_after   int not null check (balance_after >= 0),
  description     varchar(200) not null,
  feature_key     varchar(30) null,
  payment_id      int null references la_obra_v2.billing_payments(id) on delete set null,
  unlock_id       int null references la_obra_v2.feature_unlocks(id) on delete set null,
  created_by      int null,
  created_by_name varchar(100) null,
  created_at      timestamp not null default localtimestamp
);
create index if not exists idx_ctx_business on la_obra_v2.credit_transactions(business_id, created_at);

-- ---------- Datos iniciales (solo si faltan; si ya cambiaste precios no se tocan) ----------
insert into la_obra_v2.features(key, name, description, credits_per_hour, credits_per_day, sort) values
  ('ventas',      'Ventas y caja',            'Punto de venta, pedidos, cobros, corte de caja, productos, categorías y métodos de pago', 2, 15, 1),
  ('gastos',      'Gastos',                   'Registro y control de gastos del día',                                                      1,  5, 2),
  ('inventario',  'Inventario y compras',     'Insumos, existencias, kárdex, compras con ticket y mermas',                                  3, 20, 3),
  ('asistencia',  'Asistencia con ubicación', 'Entradas y salidas del personal con geolocalización',                                       2, 10, 4),
  ('reportes',    'Reportes',                 'Ventas por día, por producto, por categoría y por método de pago',                         3, 15, 5),
  ('recetas',     'Recetas y costos',         'Preparaciones, recetas por producto y costo contra precio de venta',                        4, 25, 6),
  ('facturacion', 'Facturación de prueba',    'Genera la factura (CFDI de prueba) de un pedido',                                            3, 15, 7),
  ('respaldos',   'Respaldos',                'Descargar y restaurar un respaldo completo de la información',                              5, 15, 8)
on conflict (key) do nothing;

insert into la_obra_v2.plans(code, name, description, monthly_price, annual_price, max_users, sort) values
  ('bronze', 'Bronze', 'Lo esencial para vender y cortar caja',                     299.00,  2990.00, 3,    1),
  ('silver', 'Silver', 'Controla inventario, compras, asistencia y reportes',       599.00,  5990.00, 8,    2),
  ('gold',   'Gold',   'Todo el sistema: recetas y costos, facturación y respaldos', 999.00,  9990.00, null, 3)
on conflict (code) do nothing;

insert into la_obra_v2.plan_features(plan_code, feature_key)
select p, f from (values
  ('bronze','ventas'), ('bronze','gastos'),
  ('silver','ventas'), ('silver','gastos'), ('silver','inventario'), ('silver','asistencia'), ('silver','reportes'),
  ('gold','ventas'), ('gold','gastos'), ('gold','inventario'), ('gold','asistencia'), ('gold','reportes'),
  ('gold','recetas'), ('gold','facturacion'), ('gold','respaldos')
) v(p, f)
where not exists (select 1 from la_obra_v2.plan_features)   -- solo la primera vez
on conflict do nothing;

insert into la_obra_v2.credit_packages(name, credits, bonus, price, sort)
select * from (values
  ('Paquete 50',   50,   0,  50.00::numeric, 1),
  ('Paquete 100', 100,  10, 100.00::numeric, 2),
  ('Paquete 250', 250,  40, 250.00::numeric, 3),
  ('Paquete 500', 500, 100, 500.00::numeric, 4)
) v(name, credits, bonus, price, sort)
where not exists (select 1 from la_obra_v2.credit_packages);

-- Prueba gratis: solo a los negocios que nunca han tenido un plan
insert into la_obra_v2.subscriptions(business_id, plan_code, billing_cycle, price, starts_at, ends_at)
select b.id, s.trial_plan, 'trial', 0, la_obra_v2.mx_now(), la_obra_v2.mx_now() + make_interval(days => s.trial_days)
  from la_obra_v2.businesses b cross join la_obra_v2.billing_settings s
 where s.trial_days > 0 and exists (select 1 from la_obra_v2.plans where code = s.trial_plan)
   and not exists (select 1 from la_obra_v2.subscriptions x where x.business_id = b.id);

-- Las tablas nuevas tampoco se pueden leer con la clave pública
alter table la_obra_v2.businesses          enable row level security;
alter table la_obra_v2.features            enable row level security;
alter table la_obra_v2.plans               enable row level security;
alter table la_obra_v2.plan_features       enable row level security;
alter table la_obra_v2.credit_packages     enable row level security;
alter table la_obra_v2.billing_settings    enable row level security;
alter table la_obra_v2.billing_payments    enable row level security;
alter table la_obra_v2.subscriptions       enable row level security;
alter table la_obra_v2.feature_unlocks     enable row level security;
alter table la_obra_v2.credit_transactions enable row level security;

-- =====================================================================
-- Reglas
-- =====================================================================

-- Negocio de un usuario
create or replace function la_obra_v2.user_business(u la_obra_v2.users)
returns int language sql stable as $$ select coalesce(u.business_id, la_obra_v2.default_business()); $$;

-- Plan vigente ahora mismo (el más reciente que ya empezó y no ha terminado)
create or replace function la_obra_v2.billing_current_sub(p_business int)
returns la_obra_v2.subscriptions language sql stable as $$
  select s.* from la_obra_v2.subscriptions s
   where s.business_id = p_business and s.status = 'active'
     and s.starts_at <= la_obra_v2.mx_now() and s.ends_at > la_obra_v2.mx_now()
   order by s.starts_at desc, s.id desc limit 1;
$$;

-- Hasta cuándo está pagado el negocio (incluye renovaciones ya pagadas que empiezan después)
create or replace function la_obra_v2.billing_paid_until(p_business int)
returns timestamp language sql stable as $$
  select max(ends_at) from la_obra_v2.subscriptions
   where business_id = p_business and status = 'active' and ends_at > la_obra_v2.mx_now();
$$;

-- Fin del desbloqueo con créditos de una función (null si no hay uno vigente)
create or replace function la_obra_v2.billing_unlock_until(p_business int, p_feature text)
returns timestamp language sql stable as $$
  select max(ends_at) from la_obra_v2.feature_unlocks
   where business_id = p_business and feature_key = p_feature
     and starts_at <= la_obra_v2.mx_now() and ends_at > la_obra_v2.mx_now();
$$;

create or replace function la_obra_v2.billing_feature_in_plan(p_business int, p_feature text)
returns boolean language sql stable as $$
  select exists (select 1 from la_obra_v2.plan_features pf
                  where pf.plan_code = (la_obra_v2.billing_current_sub(p_business)).plan_code and pf.feature_key = p_feature);
$$;

-- ¿El negocio puede usar esta función ahora? (por su plan o por créditos)
create or replace function la_obra_v2.billing_feature_active(p_business int, p_feature text)
returns boolean language sql stable as $$
  select la_obra_v2.billing_feature_in_plan(p_business, p_feature)
      or la_obra_v2.billing_unlock_until(p_business, p_feature) is not null;
$$;

-- Usuarios activos que permite el plan vigente (null = sin límite).
-- Sin plan vigente se permite lo del plan más chico, para que el administrador pueda seguir entrando.
create or replace function la_obra_v2.billing_max_users(p_business int)
returns int language plpgsql stable as $$
declare s la_obra_v2.subscriptions; v int;
begin
  s := la_obra_v2.billing_current_sub(p_business);
  if s.id is not null then
    select max_users into v from la_obra_v2.plans where code = s.plan_code;
    return v;
  end if;
  select max_users into v from la_obra_v2.plans where status = 'active' order by sort, monthly_price limit 1;
  return v;
end $$;

create or replace function la_obra_v2.billing_active_users(p_business int)
returns int language sql stable as $$
  select count(*)::int from la_obra_v2.users
   where coalesce(business_id, la_obra_v2.default_business()) = p_business and status = 'active' and role in ('admin','employee');
$$;

-- Qué función se necesita para cada ruta de la API. null = ruta libre (sesión, perfil, usuarios, plan…).
-- Si devuelve varias, basta con tener una (ej. el catálogo de insumos lo usan Inventario y Recetas).
create or replace function la_obra_v2.billing_route_features(p text)
returns text[] language sql immutable as $$
  select case
    -- Insumos: los usan Inventario y también Recetas (para armar recetas hay que dar de alta insumos)
    when p ~ '^inputs/' or p in ('inventory/index', 'preparations/index') then array['inventario','recetas']
    when p in ('products/components', 'products/save-components') then array['recetas']
    when p ~ '^(orders|sales|cash|categories|products|payment-methods)/' then array['ventas']
    when p ~ '^expenses/' then array['gastos']
    when p ~ '^(inventory|inputs|purchases|waste)/' then array['inventario']
    when p ~ '^attendance/' then array['asistencia']
    when p ~ '^reports/' then array['reportes']
    when p ~ '^(preparations|recipes|costs)/' then array['recetas']
    when p ~ '^invoices/' then array['facturacion']
    when p ~ '^backup/' then array['respaldos']
    else null end;
$$;

-- Revisión que hace la función pública antes de ejecutar cada ruta.
-- Devuelve null si se permite, o la respuesta 402 si el negocio no tiene esa función vigente.
-- Si no hay sesión válida no decide nada: la ruta responde 401 como siempre.
create or replace function la_obra_v2.billing_gate(p_path text, p_token text)
returns jsonb language plpgsql stable as $$
declare
  p text := regexp_replace(lower(coalesce(p_path, '')), '\.php$', '');
  v_feats text[]; u la_obra_v2.users; v_biz int; f la_obra_v2.features; v_paid timestamp;
begin
  v_feats := la_obra_v2.billing_route_features(p);
  if v_feats is null or p_token is null or btrim(p_token) = '' then return null; end if;
  select us.* into u from la_obra_v2.sessions s join la_obra_v2.users us on us.id = s.user_id
   where s.token_hash = la_obra_v2.sha256(btrim(p_token)) and s.expires_at > localtimestamp limit 1;
  if u.id is null then return null; end if;
  v_biz := la_obra_v2.user_business(u);
  if exists (select 1 from unnest(v_feats) x where la_obra_v2.billing_feature_active(v_biz, x)) then return null; end if;

  select * into f from la_obra_v2.features where key = v_feats[1];
  v_paid := la_obra_v2.billing_paid_until(v_biz);
  return jsonb_build_object('status', 402, 'body', jsonb_build_object(
    'success', false,
    'plan_required', true,
    'feature', f.key,
    'feature_name', f.name,
    'message', case
      when (la_obra_v2.billing_current_sub(v_biz)).id is null and v_paid is null then
        'El plan del negocio terminó. ' || case when u.role = 'admin'
          then 'Renuévalo o desbloquea "' || f.name || '" con créditos en Plan y créditos.'
          else 'Pide al administrador que lo renueve.' end
      else '"' || f.name || '" no está incluida en el plan del negocio o su tiempo contratado terminó. ' ||
        case when u.role = 'admin' then 'Mejora el plan o desbloquéala con créditos en Plan y créditos.'
             else 'Pide al administrador que la active.' end
    end));
end $$;

-- ---------- Disparadores en users ----------
-- a) Todo usuario nuevo (o restaurado de un respaldo) queda en un negocio que exista
create or replace function la_obra_v2.tg_users_business()
returns trigger language plpgsql as $$
begin
  if new.business_id is null or not exists (select 1 from la_obra_v2.businesses where id = new.business_id) then
    new.business_id := la_obra_v2.default_business();
  end if;
  return new;
end $$;
drop trigger if exists a_users_business on la_obra_v2.users;
create trigger a_users_business before insert or update of business_id on la_obra_v2.users
  for each row execute function la_obra_v2.tg_users_business();

-- b) Límite de usuarios activos del plan. Solo aplica a lo que se hace desde la app
--    (no a lo que hace el proveedor en el SQL Editor ni a restaurar un respaldo).
create or replace function la_obra_v2.tg_users_limit()
returns trigger language plpgsql as $$
declare v_max int; v_n int; v_plan text;
begin
  if coalesce(current_setting('la_obra_v2.in_api', true), '') <> 'on'
     or coalesce(current_setting('la_obra_v2.skip_user_limit', true), '') = 'on' then
    return new;
  end if;
  if new.status = 'active' and new.role in ('admin','employee')
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    v_max := la_obra_v2.billing_max_users(new.business_id);
    if v_max is not null then
      select count(*) into v_n from la_obra_v2.users
       where business_id = new.business_id and status = 'active' and role in ('admin','employee') and id <> new.id;
      if v_n >= v_max then
        select p.name into v_plan from la_obra_v2.plans p where p.code = (la_obra_v2.billing_current_sub(new.business_id)).plan_code;
        perform la_obra_v2.fail(402, 'El plan ' || coalesce(v_plan, 'actual') || ' permite hasta ' || v_max ||
          ' usuarios activos y ya tienes ' || v_n || '. Desactiva una cuenta o mejora el plan en Plan y créditos.',
          jsonb_build_object('plan_required', true, 'limit', 'users', 'max_users', v_max));
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists b_users_limit on la_obra_v2.users;
create trigger b_users_limit before insert or update of status, role on la_obra_v2.users
  for each row execute function la_obra_v2.tg_users_limit();

-- ---------- Créditos ----------
-- Suma o resta créditos con candado sobre el negocio (dos compras a la vez no se pisan).
-- Si el saldo no alcanza, falla y se deshace toda la petición.
create or replace function la_obra_v2.credit_move(p_business int, p_type text, p_amount int, p_desc text,
  p_user int default null, p_user_name text default null, p_feature text default null,
  p_payment int default null, p_unlock int default null)
returns int language plpgsql as $$
declare v_bal int;
begin
  select credit_balance into v_bal from la_obra_v2.businesses where id = p_business for update;
  if v_bal is null then perform la_obra_v2.fail(404, 'Negocio no encontrado'); end if;
  if v_bal + p_amount < 0 then
    perform la_obra_v2.fail(402, 'Créditos insuficientes: tienes ' || v_bal || ' y se necesitan ' || (-p_amount) || '.',
      jsonb_build_object('credits_required', true, 'balance', v_bal, 'needed', -p_amount));
  end if;
  update la_obra_v2.businesses set credit_balance = v_bal + p_amount where id = p_business;
  insert into la_obra_v2.credit_transactions(business_id, type, amount, balance_after, description, feature_key,
    payment_id, unlock_id, created_by, created_by_name)
  values (p_business, p_type, p_amount, v_bal + p_amount, left(p_desc, 200), p_feature, p_payment, p_unlock, p_user, p_user_name);
  return v_bal + p_amount;
end $$;

-- ---------- Aplicar un pago ya aprobado ----------
-- Suscripción: la activa (renovación, primera contratación o cambio de plan con prorrateo).
-- Créditos: los suma al saldo.
create or replace function la_obra_v2.billing_apply_payment(p_payment int)
returns jsonb language plpgsql as $$
declare
  pay la_obra_v2.billing_payments; cur la_obra_v2.subscriptions; q record; pl la_obra_v2.plans; st la_obra_v2.billing_settings;
  v_now timestamp := la_obra_v2.mx_now(); v_start timestamp; v_end timestamp; v_cycle text; v_plan text;
  v_refund numeric; v_cr int; v_sub int; v_note text := ''; v_pkg la_obra_v2.credit_packages;
begin
  select * into pay from la_obra_v2.billing_payments where id = p_payment for update;
  if pay.id is null then perform la_obra_v2.fail(404, 'Pago no encontrado'); end if;
  if pay.status <> 'paid' then perform la_obra_v2.fail(409, 'El pago no está aprobado'); end if;
  if coalesce((pay.details ->> 'applied')::boolean, false) then return pay.details; end if;
  select * into st from la_obra_v2.billing_settings where id = 1;
  perform 1 from la_obra_v2.businesses where id = pay.business_id for update;

  if pay.concept = 'credits' then
    v_cr := (pay.details ->> 'credits')::int + coalesce((pay.details ->> 'bonus')::int, 0);
    perform la_obra_v2.credit_move(pay.business_id, 'purchase', (pay.details ->> 'credits')::int,
      'Compra: ' || pay.description, pay.created_by, pay.created_by_name, null, pay.id);
    if coalesce((pay.details ->> 'bonus')::int, 0) > 0 then
      perform la_obra_v2.credit_move(pay.business_id, 'bonus', (pay.details ->> 'bonus')::int,
        'Bono del ' || pay.description, pay.created_by, pay.created_by_name, null, pay.id);
    end if;
    v_note := v_cr || ' créditos agregados';
  else
    v_plan := pay.details ->> 'plan_code';
    v_cycle := pay.details ->> 'cycle';
    select * into pl from la_obra_v2.plans where code = v_plan;
    if pl.code is null then perform la_obra_v2.fail(422, 'El plan ya no existe'); end if;
    cur := la_obra_v2.billing_current_sub(pay.business_id);

    if cur.id is not null and cur.plan_code = v_plan then
      -- Renovación del mismo plan: empieza cuando termina lo ya pagado
      v_start := greatest(v_now, coalesce(la_obra_v2.billing_paid_until(pay.business_id), v_now));
      v_note := 'Renovación: empieza el ' || to_char(v_start, 'DD/MM/YYYY');
    else
      -- Plan nuevo o cambio de plan: empieza ahora. Lo no usado del plan anterior (y de renovaciones
      -- futuras ya pagadas) se devuelve en créditos, para no cobrar dos veces el mismo tiempo.
      v_start := v_now;
      v_refund := 0;
      for q in select * from la_obra_v2.subscriptions
                where business_id = pay.business_id and status = 'active' and ends_at > v_now for update loop
        if q.billing_cycle in ('monthly','annual') and q.price > 0 then
          v_refund := v_refund + q.price * extract(epoch from (q.ends_at - greatest(q.starts_at, v_now)))
                                         / extract(epoch from (q.ends_at - q.starts_at));
        end if;
        update la_obra_v2.subscriptions set status = 'replaced', closed_at = v_now where id = q.id;
      end loop;
      v_cr := floor(v_refund / st.credit_value)::int;
      if v_cr > 0 then
        perform la_obra_v2.credit_move(pay.business_id, 'proration', v_cr,
          'Tiempo no usado del plan anterior al cambiar a ' || pl.name, pay.created_by, pay.created_by_name, null, pay.id);
        v_note := 'Se abonaron ' || v_cr || ' créditos por el tiempo no usado del plan anterior';
      else
        v_note := 'Plan activo desde hoy';
      end if;
    end if;
    v_end := v_start + case when v_cycle = 'annual' then interval '1 year' else interval '1 month' end;
    insert into la_obra_v2.subscriptions(business_id, plan_code, billing_cycle, price, starts_at, ends_at, payment_id, created_by)
    values (pay.business_id, v_plan, v_cycle, pay.amount, v_start, v_end, pay.id, pay.created_by) returning id into v_sub;
  end if;

  update la_obra_v2.billing_payments
     set details = details || jsonb_build_object('applied', true, 'note', v_note, 'subscription_id', v_sub)
   where id = pay.id;
  return jsonb_build_object('applied', true, 'note', v_note, 'subscription_id', v_sub);
end $$;

-- Registrar un pago y, en modo de prueba, aprobarlo y aplicarlo al momento
create or replace function la_obra_v2.billing_new_payment(u la_obra_v2.users, p_concept text, p_desc text, p_amount numeric,
  p_details jsonb, b jsonb)
returns jsonb language plpgsql as $$
declare st la_obra_v2.billing_settings; v_method text; v_ref text; v_id int; v_res jsonb; v_biz int := la_obra_v2.user_business(u);
begin
  select * into st from la_obra_v2.billing_settings where id = 1;
  v_method := coalesce(nullif(la_obra_v2.jstr(b -> 'method'), ''), 'card_test');
  if v_method not in ('card_test','transfer','cash') then perform la_obra_v2.fail(422, 'Método de pago no válido'); end if;
  v_ref := nullif(left(la_obra_v2.jstr(b -> 'reference'), 80), '');
  if st.payment_mode = 'manual' and v_method = 'transfer' and v_ref is null then
    perform la_obra_v2.fail(422, 'Escribe la referencia o folio de la transferencia');
  end if;
  if exists (select 1 from la_obra_v2.billing_payments where business_id = v_biz and status = 'pending' and concept = p_concept) then
    perform la_obra_v2.fail(409, 'Ya hay un pago pendiente de confirmar para esto. Espera la confirmación o cancélalo.');
  end if;
  insert into la_obra_v2.billing_payments(business_id, concept, description, amount, method, reference, status, details,
    created_by, created_by_name, resolved_at)
  values (v_biz, p_concept, p_desc, p_amount, v_method, v_ref,
          case when st.payment_mode = 'simulated' then 'paid' else 'pending' end, p_details, u.id, u.name,
          case when st.payment_mode = 'simulated' then la_obra_v2.mx_now() end)
  returning id into v_id;
  if st.payment_mode = 'simulated' then
    v_res := la_obra_v2.billing_apply_payment(v_id);
    return jsonb_build_object('payment_id', v_id, 'status', 'paid', 'note', v_res ->> 'note');
  end if;
  return jsonb_build_object('payment_id', v_id, 'status', 'pending',
    'note', 'Pago registrado. Se activará cuando el proveedor lo confirme.');
end $$;

-- Pagos pendientes de más de 15 días se cancelan solos
create or replace function la_obra_v2.billing_maintenance()
returns void language sql as $$
  update la_obra_v2.billing_payments set status = 'cancelled', resolved_at = la_obra_v2.mx_now(),
         resolved_note = 'Cancelado automáticamente: no se confirmó en 15 días'
   where status = 'pending' and created_at < la_obra_v2.mx_now() - interval '15 days';
$$;

-- ---------- Estado completo del negocio (lo que ve la pantalla Plan y créditos) ----------
create or replace function la_obra_v2.billing_status_json(p_business int, p_admin boolean)
returns jsonb language plpgsql stable as $$
declare
  biz la_obra_v2.businesses; cur la_obra_v2.subscriptions; pl la_obra_v2.plans; st la_obra_v2.billing_settings;
  v_now timestamp := la_obra_v2.mx_now(); v_paid timestamp; v_last la_obra_v2.subscriptions;
begin
  select * into biz from la_obra_v2.businesses where id = p_business;
  select * into st from la_obra_v2.billing_settings where id = 1;
  cur := la_obra_v2.billing_current_sub(p_business);
  select * into pl from la_obra_v2.plans where code = cur.plan_code;
  v_paid := la_obra_v2.billing_paid_until(p_business);
  select * into v_last from la_obra_v2.subscriptions where business_id = p_business and status = 'active'
   order by ends_at desc limit 1;

  return jsonb_build_object(
    'business', jsonb_build_object('id', biz.id, 'name', biz.name),
    'now', la_obra_v2.fmt_ts(v_now),
    'credits', biz.credit_balance,
    'payment_mode', st.payment_mode,
    'currency', st.currency,
    'bank_info', st.bank_info,
    'subscription', case when cur.id is null then null else jsonb_build_object(
      'id', cur.id, 'plan_code', cur.plan_code, 'plan_name', pl.name, 'cycle', cur.billing_cycle, 'price', cur.price,
      'starts_at', la_obra_v2.fmt_ts(cur.starts_at), 'ends_at', la_obra_v2.fmt_ts(cur.ends_at),
      'paid_until', la_obra_v2.fmt_ts(v_paid),
      'days_left', greatest(0, ceil(extract(epoch from (v_paid - v_now)) / 86400))::int) end,
    'last_plan', case when cur.id is null and v_last.id is not null then jsonb_build_object(
      'plan_code', v_last.plan_code, 'ends_at', la_obra_v2.fmt_ts(v_last.ends_at)) end,
    'queued', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'plan_code', s.plan_code, 'cycle', s.billing_cycle,
        'starts_at', la_obra_v2.fmt_ts(s.starts_at), 'ends_at', la_obra_v2.fmt_ts(s.ends_at)) order by s.starts_at)
      from la_obra_v2.subscriptions s where s.business_id = p_business and s.status = 'active' and s.starts_at > v_now), '[]'),
    'users', jsonb_build_object('active', la_obra_v2.billing_active_users(p_business), 'max', la_obra_v2.billing_max_users(p_business)),
    'features', (select coalesce(jsonb_agg(jsonb_build_object(
        'key', f.key, 'name', f.name, 'description', f.description,
        'credits_per_hour', f.credits_per_hour, 'credits_per_day', f.credits_per_day,
        'in_plan', la_obra_v2.billing_feature_in_plan(p_business, f.key),
        'unlocked_until', la_obra_v2.fmt_ts(la_obra_v2.billing_unlock_until(p_business, f.key)),
        'active', la_obra_v2.billing_feature_active(p_business, f.key)) order by f.sort, f.key), '[]')
      from la_obra_v2.features f),
    'plans', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', p.code, 'name', p.name, 'description', p.description,
        'monthly_price', p.monthly_price, 'annual_price', p.annual_price, 'max_users', p.max_users,
        'features', (select coalesce(jsonb_agg(pf.feature_key order by f.sort), '[]')
                       from la_obra_v2.plan_features pf join la_obra_v2.features f on f.key = pf.feature_key
                      where pf.plan_code = p.code)) order by p.sort, p.monthly_price), '[]')
      from la_obra_v2.plans p where p.status = 'active'),
    'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'credits', k.credits,
        'bonus', k.bonus, 'price', k.price) order by k.sort, k.price), '[]')
      from la_obra_v2.credit_packages k where k.status = 'active'),
    'pending_payments', case when p_admin then (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'concept', x.concept,
        'description', x.description, 'amount', x.amount, 'method', x.method, 'reference', x.reference,
        'created_at', la_obra_v2.fmt_ts(x.created_at)) order by x.id desc), '[]')
      from la_obra_v2.billing_payments x where x.business_id = p_business and x.status = 'pending') else '[]'::jsonb end
  );
end $$;

-- =====================================================================
-- Rutas de la API (billing/*)
-- =====================================================================

-- billing/status · cualquier usuario del negocio (los empleados lo usan para saber qué está bloqueado)
create or replace function la_obra_v2.ep_billing__status(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  perform la_obra_v2.billing_maintenance();
  return la_obra_v2.ok(200, 'Plan del negocio', jsonb_build_object('billing',
    la_obra_v2.billing_status_json(la_obra_v2.user_business(u), u.role = 'admin')));
end $$;

-- billing/subscribe · POST {plan_code, cycle: monthly|annual, method, reference}
create or replace function la_obra_v2.ep_billing__subscribe(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; pl la_obra_v2.plans; v_cycle text; v_price numeric; v_res jsonb; v_biz int; v_users int; cur la_obra_v2.subscriptions;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t, true, 'Solo un administrador del negocio puede contratar o cambiar el plan');
  b := la_obra_v2.body(b);
  v_biz := la_obra_v2.user_business(u);
  select * into pl from la_obra_v2.plans where code = lower(la_obra_v2.jstr(b -> 'plan_code')) and status = 'active';
  if pl.code is null then perform la_obra_v2.fail(422, 'Elige un plan válido'); end if;
  v_cycle := la_obra_v2.jstr(b -> 'cycle');
  if v_cycle not in ('monthly','annual') then perform la_obra_v2.fail(422, 'Elige pago mensual o anual'); end if;
  v_price := case when v_cycle = 'annual' then pl.annual_price else pl.monthly_price end;

  cur := la_obra_v2.billing_current_sub(v_biz);
  if cur.id is null or cur.plan_code <> pl.code then
    -- Al bajar de plan, primero deben caber los usuarios activos
    v_users := la_obra_v2.billing_active_users(v_biz);
    if pl.max_users is not null and v_users > pl.max_users then
      perform la_obra_v2.fail(422, 'El plan ' || pl.name || ' permite ' || pl.max_users || ' usuarios activos y tienes ' || v_users ||
        '. Desactiva cuentas en Usuarios antes de cambiar.');
    end if;
  end if;

  v_res := la_obra_v2.billing_new_payment(u, 'subscription',
    'Plan ' || pl.name || ' ' || case when v_cycle = 'annual' then 'anual' else 'mensual' end, v_price,
    jsonb_build_object('plan_code', pl.code, 'cycle', v_cycle), b);
  return la_obra_v2.ok(201, case when v_res ->> 'status' = 'paid' then 'Plan ' || pl.name || ' activado' else 'Pago registrado' end,
    jsonb_build_object('result', v_res, 'billing', la_obra_v2.billing_status_json(v_biz, true)));
end $$;

-- billing/buy-credits · POST {package_id, method, reference}
create or replace function la_obra_v2.ep_billing__buy_credits(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; k la_obra_v2.credit_packages; v_res jsonb; v_biz int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t, true, 'Solo un administrador del negocio puede comprar créditos');
  b := la_obra_v2.body(b);
  v_biz := la_obra_v2.user_business(u);
  select * into k from la_obra_v2.credit_packages
   where id = la_obra_v2.positive_id(b -> 'package_id', 'Elige un paquete de créditos') and status = 'active';
  if k.id is null then perform la_obra_v2.fail(422, 'Elige un paquete de créditos'); end if;
  v_res := la_obra_v2.billing_new_payment(u, 'credits', k.name || ' (' || k.credits || ' créditos' ||
    case when k.bonus > 0 then ' + ' || k.bonus || ' de bono' else '' end || ')', k.price,
    jsonb_build_object('package_id', k.id, 'credits', k.credits, 'bonus', k.bonus), b);
  return la_obra_v2.ok(201, case when v_res ->> 'status' = 'paid' then 'Créditos agregados' else 'Pago registrado' end,
    jsonb_build_object('result', v_res, 'billing', la_obra_v2.billing_status_json(v_biz, true)));
end $$;

-- billing/unlock · POST {feature, unit: hour|day, quantity}
-- Gasta créditos y desbloquea la función ese tiempo. Si ya estaba desbloqueada, se suma al final.
create or replace function la_obra_v2.ep_billing__unlock(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; f la_obra_v2.features; v_unit text; v_qty int; v_cost int; v_start timestamp; v_end timestamp;
        v_id int; v_biz int; v_now timestamp := la_obra_v2.mx_now();
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t, true, 'Solo un administrador del negocio puede desbloquear funciones');
  b := la_obra_v2.body(b);
  v_biz := la_obra_v2.user_business(u);
  select * into f from la_obra_v2.features where key = la_obra_v2.jstr(b -> 'feature');
  if f.key is null then perform la_obra_v2.fail(422, 'Elige una función'); end if;
  v_unit := la_obra_v2.jstr(b -> 'unit');
  if v_unit not in ('hour','day') then perform la_obra_v2.fail(422, 'Elige horas o días'); end if;
  if not la_obra_v2.is_int(b -> 'quantity') then perform la_obra_v2.fail(422, 'Cantidad no válida'); end if;
  v_qty := la_obra_v2.jtext(b -> 'quantity')::int;
  if v_qty < 1 or (v_unit = 'hour' and v_qty > 72) or (v_unit = 'day' and v_qty > 90) then
    perform la_obra_v2.fail(422, 'Puedes desbloquear de 1 a 72 horas o de 1 a 90 días');
  end if;
  if (v_unit = 'hour' and f.credits_per_hour is null) or (v_unit = 'day' and f.credits_per_day is null) then
    perform la_obra_v2.fail(422, '"' || f.name || '" no se puede desbloquear por ' || case when v_unit = 'hour' then 'horas' else 'días' end);
  end if;
  if la_obra_v2.billing_feature_in_plan(v_biz, f.key) then
    perform la_obra_v2.fail(409, '"' || f.name || '" ya está incluida en tu plan');
  end if;

  perform 1 from la_obra_v2.businesses where id = v_biz for update;
  v_cost := v_qty * case when v_unit = 'hour' then f.credits_per_hour else f.credits_per_day end;
  v_start := greatest(v_now, coalesce((select max(ends_at) from la_obra_v2.feature_unlocks
                                       where business_id = v_biz and feature_key = f.key and ends_at > v_now), v_now));
  v_end := v_start + case when v_unit = 'hour' then make_interval(hours => v_qty) else make_interval(days => v_qty) end;
  insert into la_obra_v2.feature_unlocks(business_id, feature_key, duration_unit, duration_qty, credits_spent, starts_at, ends_at,
    created_by, created_by_name)
  values (v_biz, f.key, v_unit, v_qty, v_cost, v_start, v_end, u.id, u.name) returning id into v_id;
  perform la_obra_v2.credit_move(v_biz, 'spend', -v_cost,
    f.name || ': ' || v_qty || case when v_unit = 'hour' then ' hora' else ' día' end || case when v_qty > 1 then 's' else '' end,
    u.id, u.name, f.key, null, v_id);
  return la_obra_v2.ok(201, '"' || f.name || '" desbloqueada hasta el ' || to_char(v_end, 'DD/MM/YYYY HH24:MI'),
    jsonb_build_object('unlock', jsonb_build_object('id', v_id, 'feature', f.key, 'starts_at', la_obra_v2.fmt_ts(v_start),
      'ends_at', la_obra_v2.fmt_ts(v_end), 'credits_spent', v_cost),
      'billing', la_obra_v2.billing_status_json(v_biz, true)));
end $$;

-- billing/cancel-payment · POST {id} (solo pagos pendientes)
create or replace function la_obra_v2.ep_billing__cancel_payment(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_biz int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t, true);
  v_biz := la_obra_v2.user_business(u);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  update la_obra_v2.billing_payments set status = 'cancelled', resolved_at = la_obra_v2.mx_now(), resolved_note = 'Cancelado por ' || u.name
   where id = v_id and business_id = v_biz and status = 'pending';
  if not found then perform la_obra_v2.fail(404, 'No hay un pago pendiente con ese número'); end if;
  return la_obra_v2.ok(200, 'Pago cancelado', jsonb_build_object('billing', la_obra_v2.billing_status_json(v_biz, true)));
end $$;

-- billing/history · pagos, movimientos de créditos, desbloqueos y planes (solo administradores)
create or replace function la_obra_v2.ep_billing__history(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_biz int; v_now timestamp := la_obra_v2.mx_now();
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t, true, 'Solo un administrador puede ver el historial de cobros');
  v_biz := la_obra_v2.user_business(u);
  return la_obra_v2.ok(200, 'Historial', jsonb_build_object(
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'concept', x.concept, 'description', x.description,
        'amount', x.amount, 'method', x.method, 'reference', x.reference, 'status', x.status, 'note', coalesce(x.resolved_note, x.details ->> 'note'),
        'created_by_name', x.created_by_name, 'created_at', la_obra_v2.fmt_ts(x.created_at)) order by x.id desc), '[]')
      from (select * from la_obra_v2.billing_payments where business_id = v_biz order by id desc limit 100) x),
    'credits', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'type', x.type, 'amount', x.amount,
        'balance_after', x.balance_after, 'description', x.description, 'created_by_name', x.created_by_name,
        'created_at', la_obra_v2.fmt_ts(x.created_at)) order by x.id desc), '[]')
      from (select * from la_obra_v2.credit_transactions where business_id = v_biz order by id desc limit 100) x),
    'unlocks', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'feature', x.feature_key, 'feature_name', f.name,
        'unit', x.duration_unit, 'quantity', x.duration_qty, 'credits_spent', x.credits_spent,
        'starts_at', la_obra_v2.fmt_ts(x.starts_at), 'ends_at', la_obra_v2.fmt_ts(x.ends_at),
        'state', case when x.ends_at <= v_now then 'expired' when x.starts_at > v_now then 'scheduled' else 'active' end,
        'created_by_name', x.created_by_name) order by x.id desc), '[]')
      from (select * from la_obra_v2.feature_unlocks where business_id = v_biz order by id desc limit 100) x
      join la_obra_v2.features f on f.key = x.feature_key),
    'subscriptions', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'plan_code', s.plan_code, 'plan_name', p.name,
        'cycle', s.billing_cycle, 'price', s.price, 'starts_at', la_obra_v2.fmt_ts(s.starts_at), 'ends_at', la_obra_v2.fmt_ts(s.ends_at),
        'state', case when s.status <> 'active' then s.status when s.ends_at <= v_now then 'expired'
                      when s.starts_at > v_now then 'scheduled' else 'active' end) order by s.starts_at desc, s.id desc), '[]')
      from (select * from la_obra_v2.subscriptions where business_id = v_biz order by starts_at desc limit 50) s
      join la_obra_v2.plans p on p.code = s.plan_code)));
end $$;

-- =====================================================================
-- Herramientas del PROVEEDOR (tú). Se usan solo desde el SQL Editor de Supabase;
-- la app no las puede llamar. Ejemplos:
--   select la_obra_v2.proveedor_modo_pago('manual');          -- pagos pendientes hasta confirmarlos
--   select * from la_obra_v2.billing_payments where status = 'pending';
--   select la_obra_v2.proveedor_confirmar_pago(5);
--   select la_obra_v2.proveedor_rechazar_pago(6, 'No se recibió la transferencia');
--   select la_obra_v2.proveedor_regalar_creditos(50, 'Compensación');
--   select la_obra_v2.proveedor_asignar_plan('gold', 30);        -- 30 días de Gold sin cobro
--   update la_obra_v2.plans set monthly_price = 349 where code = 'bronze';   -- cambiar precios
-- =====================================================================
create or replace function la_obra_v2.proveedor_modo_pago(p_mode text)
returns text language plpgsql as $$
begin
  if p_mode not in ('simulated','manual') then raise exception 'Usa simulated o manual'; end if;
  update la_obra_v2.billing_settings set payment_mode = p_mode where id = 1;
  return 'Modo de pago: ' || p_mode;
end $$;

create or replace function la_obra_v2.proveedor_confirmar_pago(p_id int, p_note text default 'Confirmado por el proveedor')
returns text language plpgsql as $$
declare r jsonb;
begin
  update la_obra_v2.billing_payments set status = 'paid', resolved_at = la_obra_v2.mx_now(), resolved_note = p_note
   where id = p_id and status = 'pending';
  if not found then raise exception 'No hay un pago pendiente con id %', p_id; end if;
  r := la_obra_v2.billing_apply_payment(p_id);
  return 'Pago ' || p_id || ' confirmado. ' || coalesce(r ->> 'note', '');
end $$;

create or replace function la_obra_v2.proveedor_rechazar_pago(p_id int, p_note text default 'Rechazado por el proveedor')
returns text language plpgsql as $$
begin
  update la_obra_v2.billing_payments set status = 'rejected', resolved_at = la_obra_v2.mx_now(), resolved_note = p_note
   where id = p_id and status = 'pending';
  if not found then raise exception 'No hay un pago pendiente con id %', p_id; end if;
  return 'Pago ' || p_id || ' rechazado';
end $$;

create or replace function la_obra_v2.proveedor_regalar_creditos(p_credits int, p_note text default 'Ajuste del proveedor',
  p_business int default null)
returns text language plpgsql as $$
declare v_bal int;
begin
  v_bal := la_obra_v2.credit_move(coalesce(p_business, la_obra_v2.default_business()),
    case when p_credits >= 0 then 'bonus' else 'adjust' end, p_credits, p_note, null, 'Proveedor');
  return 'Saldo actual: ' || v_bal || ' créditos';
exception when sqlstate 'LO001' then
  raise exception '%', (sqlerrm::jsonb) #>> '{body,message}';
end $$;

create or replace function la_obra_v2.proveedor_asignar_plan(p_plan text, p_days int, p_business int default null)
returns text language plpgsql as $$
declare v_biz int := coalesce(p_business, la_obra_v2.default_business()); v_now timestamp := la_obra_v2.mx_now();
begin
  if not exists (select 1 from la_obra_v2.plans where code = p_plan) then raise exception 'Plan % no existe', p_plan; end if;
  if p_days < 1 then raise exception 'Días no válidos'; end if;
  update la_obra_v2.subscriptions set status = 'replaced', closed_at = v_now
   where business_id = v_biz and status = 'active' and ends_at > v_now;
  insert into la_obra_v2.subscriptions(business_id, plan_code, billing_cycle, price, starts_at, ends_at)
  values (v_biz, p_plan, 'gift', 0, v_now, v_now + make_interval(days => p_days));
  return 'Plan ' || p_plan || ' asignado por ' || p_days || ' días';
end $$;
