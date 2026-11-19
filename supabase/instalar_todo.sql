-- =====================================================================
-- La Obra v2 · INSTALAR TODO (Supabase → SQL Editor → New query → pegar → Run)
-- Crea el esquema privado la_obra_v2, sus tablas y la API (función public.la_obra_v2_api).
-- Se puede volver a correr: no borra datos, solo crea lo que falta y actualiza las funciones.
-- Generado a partir de los archivos 01 … 13 de esta carpeta (el 11, 12 y 13 van antes del 10, que pone los permisos).
-- =====================================================================


-- >>>>>>>>>> 01_esquema.sql
-- =====================================================================
-- La Obra v2 · 01 · Esquema (tablas) en PostgreSQL / Supabase
-- Conversión de database/schema.sql + todas las migraciones de MySQL.
-- Todo vive en el esquema privado la_obra_v2 (no se publica en la API).
-- Se puede correr varias veces: solo crea lo que falta.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create schema if not exists la_obra_v2;

-- ---------- Usuarios y sesiones ----------
create table if not exists la_obra_v2.users (
  id                   serial primary key,
  name                 varchar(100) not null,
  username             varchar(50)  not null unique,
  email                varchar(150) not null unique,
  password_hash        varchar(255) not null,
  status               text not null default 'pending' check (status in ('pending','active','rejected','inactive')),
  role                 text null check (role in ('admin','employee')),
  must_change_password boolean not null default false,
  created_at           timestamp not null default localtimestamp,
  updated_at           timestamp not null default localtimestamp
);

create table if not exists la_obra_v2.sessions (
  id         serial primary key,
  user_id    int not null references la_obra_v2.users(id) on delete cascade,
  token_hash varchar(255) not null unique,
  expires_at timestamp not null,
  created_at timestamp not null default localtimestamp
);
create index if not exists idx_sessions_user on la_obra_v2.sessions(user_id);

-- ---------- Catálogo ----------
create table if not exists la_obra_v2.categories (
  id     serial primary key,
  name   varchar(100) not null unique,
  status text not null default 'active' check (status in ('active','inactive'))
);

create table if not exists la_obra_v2.products (
  id           serial primary key,
  name         varchar(100) not null,
  description  varchar(255) not null default '',
  category_id  int not null references la_obra_v2.categories(id) on update cascade on delete restrict,
  type         text not null check (type in ('prepared','resale')),
  price        numeric(10,2) not null,
  is_available boolean not null default true,
  status       text not null default 'active' check (status in ('active','inactive')),
  image_path   varchar(255) null
);

create table if not exists la_obra_v2.inputs (
  id                   serial primary key,
  name                 varchar(100) not null,
  unit                 varchar(20) not null,
  package_type         varchar(40) not null default 'unidad',
  package_quantity     numeric(12,3) not null default 1.000,
  package_content_unit varchar(30) null,
  status               text not null default 'active' check (status in ('active','inactive')),
  min_stock            numeric(14,3) null
);

create table if not exists la_obra_v2.recipes (
  id         serial primary key,
  product_id int not null references la_obra_v2.products(id) on update cascade on delete restrict,
  input_id   int not null references la_obra_v2.inputs(id) on update cascade on delete restrict,
  quantity   numeric(10,3) not null,
  constraint uq_recipe_product_input unique (product_id, input_id)
);

create table if not exists la_obra_v2.preparations (
  id              serial primary key,
  name            varchar(120) not null,
  description     varchar(255) not null default '',
  yield_quantity  numeric(12,3) not null,
  yield_unit      text not null check (yield_unit in ('portion','piece','g','ml')),
  yield_estimated boolean not null default false,
  created_at      timestamp not null default localtimestamp,
  updated_at      timestamp null
);

create table if not exists la_obra_v2.preparation_inputs (
  id             serial primary key,
  preparation_id int not null references la_obra_v2.preparations(id) on delete cascade,
  input_id       int not null references la_obra_v2.inputs(id) on delete restrict,
  quantity       numeric(12,3) not null,
  is_estimated   boolean not null default false
);
create index if not exists idx_prep_inputs_prep on la_obra_v2.preparation_inputs(preparation_id);

create table if not exists la_obra_v2.product_components (
  id             serial primary key,
  product_id     int not null references la_obra_v2.products(id) on delete cascade,
  input_id       int null references la_obra_v2.inputs(id) on delete restrict,
  preparation_id int null references la_obra_v2.preparations(id) on delete restrict,
  quantity       numeric(12,3) not null,
  is_estimated   boolean not null default false,
  delivery_mode  text not null default 'always' check (delivery_mode in ('always','local','takeaway'))
);
create index if not exists idx_components_product on la_obra_v2.product_components(product_id);

-- ---------- Pedidos, pagos ----------
create table if not exists la_obra_v2.orders (
  id              serial primary key,
  user_id         int not null references la_obra_v2.users(id) on update cascade on delete restrict,
  order_status    text not null default 'open' check (order_status in ('open','confirmed','cancelled')),
  payment_status  text not null default 'pending' check (payment_status in ('pending','paid')),
  delivery_status text not null default 'pending' check (delivery_status in ('pending','delivered')),
  delivery_mode   text not null default 'local' check (delivery_mode in ('local','takeaway')),
  customer_name   varchar(80) null,
  total           numeric(10,2) not null default 0.00,
  created_at      timestamp not null default localtimestamp,
  confirmed_at    timestamp null,
  delivered_at    timestamp null,
  cancelled_at    timestamp null
);
create index if not exists idx_orders_created on la_obra_v2.orders(created_at);

create table if not exists la_obra_v2.order_items (
  id                 serial primary key,
  order_id           int not null references la_obra_v2.orders(id) on update cascade on delete cascade,
  product_id         int not null references la_obra_v2.products(id) on update cascade on delete restrict,
  quantity           int not null,
  unit_price         numeric(10,2) not null,
  subtotal           numeric(10,2) not null,
  standard_unit_cost numeric(12,4) null,
  constraint uq_order_product unique (order_id, product_id)
);

create table if not exists la_obra_v2.payment_methods (
  id     serial primary key,
  name   varchar(60) not null unique,
  status text not null default 'active' check (status in ('active','inactive'))
);

create table if not exists la_obra_v2.payments (
  id                serial primary key,
  order_id          int not null references la_obra_v2.orders(id) on update cascade on delete restrict,
  payment_method_id int not null references la_obra_v2.payment_methods(id) on update cascade on delete restrict,
  amount            numeric(10,2) not null,
  cash_received     numeric(10,2) null,
  change_amount     numeric(10,2) null,
  paid_at           timestamp not null default localtimestamp,
  constraint uq_payment_order unique (order_id)
);

-- ---------- Compras y gastos ----------
create table if not exists la_obra_v2.purchases (
  id                serial primary key,
  purchase_date     date not null,
  supplier          varchar(150) null,
  buyer             varchar(100) null,
  ticket_path       varchar(255) null,
  payment_method_id int not null references la_obra_v2.payment_methods(id),
  user_id           int not null references la_obra_v2.users(id),
  total             numeric(12,2) not null default 0.00,
  created_at        timestamp not null default localtimestamp,
  updated_at        timestamp null
);
create index if not exists idx_purchases_date on la_obra_v2.purchases(purchase_date);

create table if not exists la_obra_v2.purchase_items (
  id                  serial primary key,
  purchase_id         int not null references la_obra_v2.purchases(id),
  input_id            int not null references la_obra_v2.inputs(id),
  quantity            numeric(10,3) not null,
  unit_cost           numeric(12,2) not null,
  subtotal            numeric(12,2) not null,
  content_per_package numeric(12,3) not null default 1.000,
  content_unit        varchar(30) null,
  total_base_quantity numeric(14,3) null
);
create index if not exists idx_purchase_items_purchase on la_obra_v2.purchase_items(purchase_id);
create index if not exists idx_purchase_items_input on la_obra_v2.purchase_items(input_id);

create table if not exists la_obra_v2.purchase_history (
  id            serial primary key,
  purchase_id   int not null references la_obra_v2.purchases(id),
  changed_by    int not null references la_obra_v2.users(id),
  previous_data text not null,
  new_data      text not null,
  change_reason varchar(255) null,
  changed_at    timestamp not null default localtimestamp
);

create table if not exists la_obra_v2.expenses (
  id                  serial primary key,
  amount              numeric(12,2) not null,
  reason              varchar(255) not null,
  user_id             int not null references la_obra_v2.users(id),
  status              text not null default 'active' check (status in ('active','cancelled')),
  created_at          timestamp not null default localtimestamp,
  updated_at          timestamp null,
  cancelled_by        int null references la_obra_v2.users(id),
  cancelled_at        timestamp null,
  cancellation_reason varchar(255) null
);
create index if not exists idx_expenses_date on la_obra_v2.expenses(created_at);

create table if not exists la_obra_v2.expense_history (
  id            serial primary key,
  expense_id    int not null references la_obra_v2.expenses(id),
  action        text not null check (action in ('updated','cancelled')),
  previous_data text not null,
  new_data      text not null,
  change_reason varchar(255) not null,
  changed_by    int not null references la_obra_v2.users(id),
  changed_at    timestamp not null default localtimestamp
);

-- ---------- Mermas ----------
create table if not exists la_obra_v2.waste_records (
  id                   serial primary key,
  affected_type        text not null check (affected_type in ('input','product','preparation')),
  input_id             int null references la_obra_v2.inputs(id) on update cascade on delete restrict,
  product_id           int null references la_obra_v2.products(id) on update cascade on delete restrict,
  preparation_id       int null,
  quantity             numeric(12,3) not null,
  is_approximate       boolean not null default false,
  waste_date           date not null,
  reason               varchar(500) not null,
  classification       varchar(100) not null,
  estimated_unit_cost  numeric(12,4) null,
  estimated_total_cost numeric(14,2) null,
  cost_status          text not null default 'unavailable' check (cost_status in ('calculated','unavailable')),
  user_id              int not null references la_obra_v2.users(id) on update cascade on delete restrict,
  created_at           timestamp not null default localtimestamp
);
create index if not exists idx_waste_date on la_obra_v2.waste_records(waste_date);

-- ---------- Inventario (kárdex) ----------
create table if not exists la_obra_v2.inventory_movements (
  id             serial primary key,
  input_id       int not null references la_obra_v2.inputs(id) on delete restrict,
  movement_type  text not null check (movement_type in ('purchase','sale','sale_reversal','waste','adjustment')),
  quantity       numeric(14,3) not null,
  unit_cost      numeric(14,6) null,
  reference_type varchar(30) null,
  reference_id   int null,
  note           varchar(255) null,
  user_id        int null references la_obra_v2.users(id) on delete set null,
  created_at     timestamp not null default localtimestamp
);
create index if not exists idx_inv_input on la_obra_v2.inventory_movements(input_id);
create index if not exists idx_inv_reference on la_obra_v2.inventory_movements(reference_type, reference_id);

-- ---------- Factura de prueba ----------
create table if not exists la_obra_v2.order_test_invoices (
  order_id    bigint not null primary key,
  request_id  char(32) not null unique,
  request_xml text not null,
  stamped_xml text null,
  uuid        char(36) null unique
);

-- ---------- Asistencia con geolocalización ----------
create table if not exists la_obra_v2.work_location (
  id         smallint not null primary key,
  name       varchar(100) not null default 'La Obra',
  latitude   numeric(10,7) not null,
  longitude  numeric(10,7) not null,
  radius_m   int not null default 100,
  updated_by int null references la_obra_v2.users(id) on delete set null,
  updated_at timestamp not null default localtimestamp
);

create table if not exists la_obra_v2.attendance (
  id         serial primary key,
  user_id    int not null references la_obra_v2.users(id) on delete cascade,
  type       text not null check (type in ('in','out')),
  latitude   numeric(10,7) not null,
  longitude  numeric(10,7) not null,
  accuracy_m numeric(8,1) not null,
  distance_m numeric(10,1) not null,
  note       varchar(255) null,
  created_at timestamp not null default localtimestamp
);
create index if not exists idx_att_user_date on la_obra_v2.attendance(user_id, created_at);

-- ---------- Archivos (fotos de productos y tickets) ----------
-- Antes vivían en backend/uploads/. Se guarda la misma ruta relativa "uploads/<carpeta>/<nombre>".
create table if not exists la_obra_v2.files (
  path       varchar(255) primary key,
  mime       varchar(40) not null,
  data       bytea not null,
  created_at timestamp not null default localtimestamp
);

-- ---------- Reglas de "valor único" (por si la tabla ya existía de una versión anterior sin ellas) ----------
-- "create table if not exists" no modifica tablas existentes; aquí se agregan si faltan.
-- Si hubiera datos repetidos no se fuerza nada (no se borra ni cambia ningún dato): solo se avisa.
do $$
begin
  begin
    create unique index if not exists uq_payment_methods_name on la_obra_v2.payment_methods(name);
  exception when others then raise notice 'payment_methods: hay nombres repetidos (%); se deja igual.', sqlerrm;
  end;
  begin
    create unique index if not exists uq_users_username on la_obra_v2.users(username);
  exception when others then raise notice 'users: hay usuarios repetidos (%); se deja igual.', sqlerrm;
  end;
  begin
    create unique index if not exists uq_work_location_id on la_obra_v2.work_location(id);
  exception when others then raise notice 'work_location: (%); se deja igual.', sqlerrm;
  end;
end $$;

-- ---------- Datos iniciales ----------
-- Solo agrega los métodos de pago que falten (no depende de reglas de valor único).
insert into la_obra_v2.payment_methods (name, status)
select v.name, 'active'
from (values ('Efectivo'), ('Transferencia'), ('Tarjeta')) as v(name)
where not exists (select 1 from la_obra_v2.payment_methods p where lower(p.name) = lower(v.name));

-- ---------- Mejoras (noviembre 2026) ----------
-- Solo AGREGAN columnas y tablas; no borran ni cambian lo que ya está guardado.
-- Todas las columnas nuevas aceptan vacío (null) para que los respaldos anteriores se puedan restaurar.

-- Foto de perfil de cada usuario (la imagen vive en la_obra_v2.files, carpeta uploads/avatars/)
alter table la_obra_v2.users add column if not exists avatar_path varchar(255) null;

-- Otras medidas de un insumo: "1 pieza de tomate = 120 g", "1 cucharada de mostaza = 15 g".
-- unit_amount de "name" equivalen a base_amount de la unidad principal del insumo (inputs.unit).
-- El inventario y los costos siguen en la unidad principal; estas medidas solo sirven para capturar.
create table if not exists la_obra_v2.input_units (
  id          serial primary key,
  input_id    int not null references la_obra_v2.inputs(id) on delete cascade,
  name        varchar(30) not null,
  unit_amount numeric(12,3) not null default 1 check (unit_amount > 0),
  base_amount numeric(14,4) not null check (base_amount > 0),
  created_at  timestamp null default localtimestamp
);
create unique index if not exists uq_input_units_name on la_obra_v2.input_units(input_id, lower(name));

-- En qué medida se capturó cada ingrediente. "quantity" sigue guardando la cantidad en la unidad
-- principal (la que usan costos e inventario), así que lo anterior funciona igual.
alter table la_obra_v2.preparation_inputs add column if not exists unit_id int null references la_obra_v2.input_units(id) on delete set null;
alter table la_obra_v2.preparation_inputs add column if not exists unit_quantity numeric(12,3) null;
alter table la_obra_v2.product_components add column if not exists unit_id int null references la_obra_v2.input_units(id) on delete set null;
alter table la_obra_v2.product_components add column if not exists unit_quantity numeric(12,3) null;

-- Comisión de la terminal por método de pago (porcentaje) y lo que se descontó en cada cobro
alter table la_obra_v2.payment_methods add column if not exists commission_percent numeric(5,2) null
  check (commission_percent is null or (commission_percent >= 0 and commission_percent < 100));
alter table la_obra_v2.payments add column if not exists commission_amount numeric(10,2) null;
-- Tarjeta: 4 % (solo si nunca se ha configurado; si después lo cambias, no se vuelve a tocar)
update la_obra_v2.payment_methods set commission_percent = 4.00
 where commission_percent is null and lower(name) like '%tarjeta%';

-- ---------- Nadie entra a las tablas directamente ----------
-- Seguridad por fila activada y sin políticas: ni la clave pública ni usuarios de Supabase
-- pueden leer o escribir. Solo la función pública la_obra_v2_api (security definer).
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'la_obra_v2' loop
    execute format('alter table la_obra_v2.%I enable row level security', t.tablename);
  end loop;
end $$;

-- >>>>>>>>>> 02_nucleo.sql
set check_function_bodies = off;
-- =====================================================================
-- La Obra v2 · 02 · Núcleo
-- Equivalente a config/service_helpers.php, cost_engine.php, inventory.php y attendance.php.
--
-- Cómo responde cada "endpoint":
--   ok(código, mensaje, datos)   → termina bien: devuelve {status, body:{success:true, message, ...datos}}
--   fail(código, mensaje, datos) → lanza un error controlado; la función pública lo convierte en
--                                  {status, body:{success:false, message, ...}} y DESHACE todo lo que
--                                  se haya escrito en esa petición (igual que un rollback).
-- =====================================================================

-- ---------- Respuestas ----------
create or replace function la_obra_v2.ok(p_code int, p_message text, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('status', p_code,
    'body', jsonb_build_object('success', p_code < 400, 'message', p_message) || coalesce(p_extra, '{}'::jsonb));
$$;

create or replace function la_obra_v2.fail(p_code int, p_message text, p_extra jsonb default '{}'::jsonb)
returns void language plpgsql as $$
begin
  raise exception using errcode = 'LO001',
    message = jsonb_build_object('status', p_code,
      'body', jsonb_build_object('success', false, 'message', p_message) || coalesce(p_extra, '{}'::jsonb))::text;
end $$;

-- Igual que fail() pero devuelve cualquier tipo, para usarse dentro de expresiones
create or replace function la_obra_v2.method(p_method text, p_expected text)
returns void language plpgsql as $$
begin
  if p_method is distinct from p_expected then perform la_obra_v2.fail(405, 'Método no permitido'); end if;
end $$;

-- ---------- Lectura de valores JSON ----------
-- Texto de un valor JSON (cadena, número o booleano); null si no viene o es null
create or replace function la_obra_v2.jtext(v jsonb)
returns text language sql immutable as $$
  select case when v is null or jsonb_typeof(v) = 'null' then null
              when jsonb_typeof(v) = 'string' then v #>> '{}'
              when jsonb_typeof(v) in ('number','boolean') then v::text
              else null end;
$$;

-- trim((string)($d['x'] ?? '')) de PHP
create or replace function la_obra_v2.jstr(v jsonb)
returns text language sql immutable as $$
  select btrim(coalesce(la_obra_v2.jtext(v), ''), E' \t\n\r\x0B');
$$;

-- ¿Es escalar? (cadena, número o booleano)
create or replace function la_obra_v2.is_scalar(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and jsonb_typeof(v) in ('string','number','boolean');
$$;

-- is_numeric() de PHP
create or replace function la_obra_v2.is_num(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and (jsonb_typeof(v) = 'number'
    or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') ~ '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$'));
$$;

create or replace function la_obra_v2.num(v jsonb)
returns numeric language sql immutable as $$
  select case when la_obra_v2.is_num(v) then btrim(la_obra_v2.jtext(v))::numeric else null end;
$$;

-- filter_var(..., FILTER_VALIDATE_INT)
create or replace function la_obra_v2.is_int(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and (
    (jsonb_typeof(v) = 'number' and (v::text)::numeric = trunc((v::text)::numeric) and v::text !~ '[.eE]')
    or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') ~ '^[+-]?\d{1,9}$'));
$$;

create or replace function la_obra_v2.body(b jsonb)
returns jsonb language plpgsql as $$
begin
  if b is null or jsonb_typeof(b) not in ('object','array') then perform la_obra_v2.fail(422, 'JSON inválido'); end if;
  return b;
end $$;

create or replace function la_obra_v2.positive_id(v jsonb, p_message text default 'ID inválido')
returns int language plpgsql as $$
begin
  if not la_obra_v2.is_int(v) or btrim(la_obra_v2.jtext(v))::int <= 0 then perform la_obra_v2.fail(422, p_message); end if;
  return btrim(la_obra_v2.jtext(v))::int;
end $$;

-- money(): monto con máximo 2 decimales; positivo (> 0) o no negativo (>= 0)
create or replace function la_obra_v2.money(v jsonb, p_positive boolean default true)
returns numeric language plpgsql as $$
declare n numeric;
begin
  if not la_obra_v2.is_scalar(v) or not la_obra_v2.is_num(v) then perform la_obra_v2.fail(422, 'Monto o costo inválido'); end if;
  n := la_obra_v2.num(v);
  if (p_positive and n <= 0) or (not p_positive and n < 0) or round(n, 2) <> n then
    perform la_obra_v2.fail(422, 'Monto o costo inválido');
  end if;
  return round(n, 2);
end $$;

create or replace function la_obra_v2.dateval(v jsonb, p_message text default 'Fecha inválida')
returns date language plpgsql as $$
declare s text := la_obra_v2.jtext(v); d date;
begin
  if v is null or jsonb_typeof(v) <> 'string' or s !~ '^\d{4}-\d{2}-\d{2}$' then perform la_obra_v2.fail(422, p_message); end if;
  begin d := s::date; exception when others then perform la_obra_v2.fail(422, p_message); end;
  if to_char(d, 'YYYY-MM-DD') <> s then perform la_obra_v2.fail(422, p_message); end if;
  return d;
end $$;

-- Valor de un parámetro de la URL (?x=...) o null si no viene / viene vacío
create or replace function la_obra_v2.qparam(q jsonb, k text)
returns jsonb language sql immutable as $$
  select case when q ? k and coalesce(la_obra_v2.jtext(q -> k), '') <> '' then q -> k else null end;
$$;

-- Validación de correo (aproximación a FILTER_VALIDATE_EMAIL)
create or replace function la_obra_v2.valid_email(e text)
returns boolean language sql immutable as $$
  select e ~ '^[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'
     and e !~ '\.\.' and e !~ '^\.' and e !~ '\.@';
$$;

-- ---------- Contraseñas (compatibles con password_hash de PHP) ----------
create or replace function la_obra_v2.hash_password(p text)
returns text language sql volatile as $$
  select extensions.crypt(p, extensions.gen_salt('bf', 10));
$$;

create or replace function la_obra_v2.check_password(p text, h text)
returns boolean language plpgsql as $$
declare hh text;
begin
  if p is null or h is null or h = '' then return false; end if;
  -- PHP genera $2y$; pgcrypto entiende $2a$ (es el mismo algoritmo)
  hh := regexp_replace(h, '^\$2[by]\$', '$2a$');
  return extensions.crypt(p, hh) = hh;
exception when others then
  return false;
end $$;

create or replace function la_obra_v2.sha256(t text)
returns text language sql immutable as $$
  select encode(extensions.digest(t, 'sha256'), 'hex');
$$;

-- ---------- Sesión ----------
-- Devuelve el usuario de la sesión: {id, role, status, name, username, email, must_change_password}
-- p_admin: exige rol administrador. p_admin_message: mensaje si no es admin.
create or replace function la_obra_v2.session_user_row(p_token text, p_admin boolean default false,
  p_admin_message text default 'Se requiere rol administrador', p_style text default 'helper')
returns la_obra_v2.users language plpgsql as $$
declare u la_obra_v2.users; exp timestamp;
begin
  if p_token is null or btrim(p_token) = '' or btrim(p_token) ~ '\s' then
    perform la_obra_v2.fail(401, 'Token de autenticación requerido');
  end if;
  select us.* into u from la_obra_v2.sessions s join la_obra_v2.users us on us.id = s.user_id
   where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  select s.expires_at into exp from la_obra_v2.sessions s where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  if u.id is null then
    perform la_obra_v2.fail(401, case when p_style = 'helper' then 'Sesión inválida o expirada' else 'Sesión inválida' end);
  end if;
  if exp <= localtimestamp then
    perform la_obra_v2.fail(401, case when p_style = 'helper' then 'Sesión inválida o expirada' else 'La sesión ha expirado' end);
  end if;
  if u.status <> 'active' or u.role is null or u.role not in ('admin','employee') then
    perform la_obra_v2.fail(403, case when p_style = 'helper' then 'Cuenta sin acceso' else 'La cuenta no tiene acceso al sistema' end);
  end if;
  if p_admin and u.role <> 'admin' then perform la_obra_v2.fail(403, p_admin_message); end if;
  return u;
end $$;

-- user() de service_helpers.php
create or replace function la_obra_v2.auth(p_token text, p_admin boolean default false)
returns la_obra_v2.users language sql as $$
  select la_obra_v2.session_user_row(p_token, p_admin);
$$;

-- Validación usada por los archivos PHP "largos" (mensajes: Sesión inválida / La sesión ha expirado / ...)
create or replace function la_obra_v2.auth_long(p_token text, p_admin boolean default false,
  p_admin_message text default 'No tienes permisos para realizar esta acción')
returns la_obra_v2.users language sql as $$
  select la_obra_v2.session_user_row(p_token, p_admin, p_admin_message, 'long');
$$;

-- ---------- Utilidades de JSON ----------
-- json_encode(...) estilo PHP para historiales
create or replace function la_obra_v2.audit_json(v jsonb)
returns text language sql immutable as $$ select v::text; $$;

-- ---------- Motor de costos (cost_engine.php) ----------
-- Costo por unidad base de un insumo según su última compra válida
create or replace function la_obra_v2.input_cost(p_input int)
returns numeric language sql stable as $$
  select pi.subtotal / pi.total_base_quantity
    from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id
   where pi.input_id = p_input and pi.total_base_quantity > 0 and pi.subtotal >= 0
   order by p.purchase_date desc, p.id desc, pi.id desc limit 1;
$$;

-- Costo de una preparación (lote y por unidad de rendimiento)
create or replace function la_obra_v2.preparation_cost(p_id int)
returns jsonb language plpgsql stable as $$
declare p la_obra_v2.preparations; r record; v_sum numeric := 0; v_missing jsonb := '[]'; v_detail jsonb := '[]'; v_unit numeric; v_n int := 0;
begin
  select * into p from la_obra_v2.preparations where id = p_id;
  if p.id is null or p.yield_quantity <= 0 then return null; end if;
  for r in select pi.*, i.name, i.unit from la_obra_v2.preparation_inputs pi join la_obra_v2.inputs i on i.id = pi.input_id
            where pi.preparation_id = p_id order by pi.id loop
    v_n := v_n + 1;
    v_unit := la_obra_v2.input_cost(r.input_id);
    if v_unit is null then v_missing := v_missing || to_jsonb(r.name); else v_sum := v_sum + v_unit * r.quantity; end if;
    v_detail := v_detail || jsonb_build_object('name', r.name, 'quantity', r.quantity, 'unit', r.unit, 'unit_cost', v_unit,
      'cost', case when v_unit is null then null else v_unit * r.quantity end, 'estimated', r.is_estimated);
  end loop;
  if v_n = 0 then return null; end if;
  return jsonb_build_object('name', p.name, 'yield_quantity', p.yield_quantity, 'yield_unit', p.yield_unit,
    'batch_cost', case when jsonb_array_length(v_missing) > 0 then null else v_sum end,
    'unit_cost', case when jsonb_array_length(v_missing) > 0 then null else v_sum / p.yield_quantity end,
    'missing', v_missing, 'ingredients', v_detail);
end $$;

-- Costo estándar de un producto para una modalidad (local / takeaway)
create or replace function la_obra_v2.product_cost(p_id int, p_mode text default 'local')
returns jsonb language plpgsql stable as $$
declare pr record; c record; v_total numeric := 0; v_missing jsonb := '[]'; v_detail jsonb := '[]'; v_cost numeric; v_prep jsonb;
        v_name text; v_n int := 0; v_complete boolean; v_profit numeric;
begin
  select id, name, price into pr from la_obra_v2.products where id = p_id;
  if pr.id is null then return null; end if;
  for c in select pc.*, i.name as input_name, i.unit as input_unit, p2.name as preparation_name
             from la_obra_v2.product_components pc
             left join la_obra_v2.inputs i on i.id = pc.input_id
             left join la_obra_v2.preparations p2 on p2.id = pc.preparation_id
            where pc.product_id = p_id and pc.delivery_mode in ('always', p_mode) order by pc.id loop
    v_n := v_n + 1;
    v_prep := null;
    if c.input_id is not null then
      v_cost := la_obra_v2.input_cost(c.input_id); v_name := c.input_name;
    else
      v_prep := la_obra_v2.preparation_cost(c.preparation_id);
      v_cost := (v_prep ->> 'unit_cost')::numeric; v_name := c.preparation_name;
    end if;
    if v_cost is null then v_missing := v_missing || to_jsonb(v_name); else v_total := v_total + c.quantity * v_cost; end if;
    v_detail := v_detail || jsonb_build_object('name', v_name, 'type', case when c.input_id is not null then 'input' else 'preparation' end,
      'quantity', c.quantity, 'unit', case when c.input_id is not null then c.input_unit else coalesce(v_prep ->> 'yield_unit', '') end,
      'unit_cost', v_cost, 'cost', case when v_cost is null then null else v_cost * c.quantity end,
      'estimated', c.is_estimated, 'delivery_mode', c.delivery_mode);
  end loop;
  v_complete := jsonb_array_length(v_missing) = 0 and v_n > 0;
  v_profit := case when v_complete then pr.price - v_total else null end;
  return jsonb_build_object('product_id', pr.id, 'name', pr.name, 'delivery_mode', p_mode, 'sale_price', pr.price,
    'standard_cost', case when v_complete then round(v_total, 4) else null end,
    'gross_profit', case when v_profit is null then null else round(v_profit, 4) end,
    'gross_margin', case when v_profit is null or pr.price = 0 then null else round(v_profit / pr.price * 100, 2) end,
    'missing_prices', v_missing, 'components', v_detail, 'complete', v_complete);
end $$;

-- ---------- Inventario (inventory.php) ----------
create or replace function la_obra_v2.inv_record(p_input int, p_type text, p_qty numeric, p_unit_cost numeric,
  p_ref_type text, p_ref_id int, p_note text, p_user int)
returns void language plpgsql as $$
begin
  if abs(coalesce(p_qty, 0)) < 0.0005 then return; end if;
  insert into la_obra_v2.inventory_movements(input_id, movement_type, quantity, unit_cost, reference_type, reference_id, note, user_id)
  values (p_input, p_type, round(p_qty, 3), case when p_unit_cost is null then null else round(p_unit_cost, 6) end, p_ref_type, p_ref_id, p_note, p_user);
end $$;

create or replace function la_obra_v2.inv_stock(p_input int)
returns numeric language sql stable as $$
  select coalesce(sum(quantity), 0) from la_obra_v2.inventory_movements where input_id = p_input;
$$;

create or replace function la_obra_v2.inv_sync_purchase(p_purchase int, p_user int)
returns void language plpgsql as $$
declare i record;
begin
  delete from la_obra_v2.inventory_movements where reference_type = 'purchase' and reference_id = p_purchase;
  for i in select input_id, subtotal, total_base_quantity from la_obra_v2.purchase_items where purchase_id = p_purchase order by id loop
    if coalesce(i.total_base_quantity, 0) <= 0 then continue; end if;
    perform la_obra_v2.inv_record(i.input_id, 'purchase', i.total_base_quantity, i.subtotal / i.total_base_quantity, 'purchase', p_purchase, null, p_user);
  end loop;
end $$;

-- Insumos por unidad de producto (receta + preparaciones), según modalidad
create or replace function la_obra_v2.inv_product_parts(p_product int, p_mode text default 'local')
returns table(input_id int, qty numeric) language sql stable as $$
  select x.input_id, sum(x.qty) from (
    select pc.input_id, pc.quantity as qty
      from la_obra_v2.product_components pc
     where pc.product_id = p_product and pc.delivery_mode in ('always', p_mode) and pc.input_id is not null
    union all
    select pi.input_id, pi.quantity / pr.yield_quantity * pc.quantity
      from la_obra_v2.product_components pc
      join la_obra_v2.preparations pr on pr.id = pc.preparation_id and pr.yield_quantity > 0
      join la_obra_v2.preparation_inputs pi on pi.preparation_id = pr.id
     where pc.product_id = p_product and pc.delivery_mode in ('always', p_mode) and pc.input_id is null
  ) x group by x.input_id;
$$;

create or replace function la_obra_v2.inv_consume_order(p_order int, p_user int)
returns void language plpgsql as $$
declare o record; r record;
begin
  select id, delivery_mode into o from la_obra_v2.orders where id = p_order;
  if o.id is null then return; end if;
  if exists(select 1 from la_obra_v2.inventory_movements where reference_type = 'order' and reference_id = p_order and movement_type = 'sale') then return; end if;
  for r in select pp.input_id, sum(pp.qty * oi.quantity) as qty
             from la_obra_v2.order_items oi
             cross join lateral la_obra_v2.inv_product_parts(oi.product_id, coalesce(nullif(o.delivery_mode, ''), 'local')) pp
            where oi.order_id = p_order group by pp.input_id order by pp.input_id loop
    perform la_obra_v2.inv_record(r.input_id, 'sale', -r.qty, la_obra_v2.input_cost(r.input_id), 'order', p_order, null, p_user);
  end loop;
end $$;

create or replace function la_obra_v2.inv_reverse_order(p_order int, p_user int)
returns void language plpgsql as $$
declare m record;
begin
  if exists(select 1 from la_obra_v2.inventory_movements where reference_type = 'order' and reference_id = p_order and movement_type = 'sale_reversal') then return; end if;
  for m in select input_id, quantity, unit_cost from la_obra_v2.inventory_movements
            where reference_type = 'order' and reference_id = p_order and movement_type = 'sale' order by id loop
    perform la_obra_v2.inv_record(m.input_id, 'sale_reversal', -m.quantity, m.unit_cost, 'order', p_order, 'Venta cancelada', p_user);
  end loop;
end $$;

-- Otras medidas de un insumo: [{id, name, unit_amount, base_amount, factor}] (factor = unidades principales por 1 de esta medida)
create or replace function la_obra_v2.input_units_json(p_input int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'unit_amount', u.unit_amount::float8,
           'base_amount', u.base_amount::float8, 'factor', (u.base_amount / u.unit_amount)::float8) order by lower(u.name), u.id), '[]'::jsonb)
    from la_obra_v2.input_units u where u.input_id = p_input;
$$;

create or replace function la_obra_v2.inv_list()
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.name, t.id), '[]'::jsonb) from (
    select s.id, s.name, s.unit, s.status, s.package_type, s.package_quantity, s.package_content_unit, s.min_stock,
           round(s.stock, 3) as stock, la_obra_v2.fmt_ts(s.last_purchase_at) as last_purchase_at,
           round(c.cost, 4) as unit_cost,
           case when c.cost is null then null else round(greatest(0, round(s.stock, 3)) * c.cost, 2) end as stock_value,
           case when round(s.stock, 3) <= 0 then 'out' when s.min_stock is not null and round(s.stock, 3) <= s.min_stock then 'low' else 'ok' end as level,
           la_obra_v2.input_units_json(s.id) as units
      from (select i.id, i.name, i.unit, i.status, i.package_type, i.package_quantity, i.package_content_unit, i.min_stock,
                   coalesce(sum(m.quantity), 0) as stock,
                   max(case when m.movement_type = 'purchase' then m.created_at end) as last_purchase_at
              from la_obra_v2.inputs i left join la_obra_v2.inventory_movements m on m.input_id = i.id
             group by i.id) s
      cross join lateral (select la_obra_v2.input_cost(s.id) as cost) c
  ) t;
$$;

-- ---------- Fechas como las daba MySQL: 'YYYY-MM-DD HH:MM:SS' ----------
create or replace function la_obra_v2.fmt_ts(t timestamp)
returns text language sql immutable as $$ select to_char(t, 'YYYY-MM-DD HH24:MI:SS'); $$;

-- Convierte un renglón a JSON con las fechas en formato MySQL (y deja números y booleanos como tales)
create or replace function la_obra_v2.js(r anyelement)
returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(k, case
      when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$'
        then to_jsonb(replace(substr(v #>> '{}', 1, 19), 'T', ' '))
      else v end), '{}'::jsonb)
  from jsonb_each(to_jsonb(r)) as e(k, v);
$$;

-- Lista de renglones (jsonb de cada uno ya con js()) en un arreglo
create or replace function la_obra_v2.fix_dates(j jsonb)
returns jsonb language sql immutable as $$
  select case jsonb_typeof(j)
    when 'object' then (select coalesce(jsonb_object_agg(k, la_obra_v2.fix_dates(v)), '{}'::jsonb) from jsonb_each(j) e(k, v))
    when 'array'  then (select coalesce(jsonb_agg(la_obra_v2.fix_dates(v) order by n), '[]'::jsonb) from jsonb_array_elements(j) with ordinality a(v, n))
    when 'string' then case when (j #>> '{}') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$'
                            then to_jsonb(replace(substr(j #>> '{}', 1, 19), 'T', ' ')) else j end
    else j end;
$$;

-- ---------- Asistencia (attendance.php) ----------
create or replace function la_obra_v2.coordinate(v jsonb, p_limit numeric, p_label text)
returns numeric language plpgsql as $$
begin
  if not la_obra_v2.is_scalar(v) or not la_obra_v2.is_num(v) or abs(la_obra_v2.num(v)) > p_limit then
    perform la_obra_v2.fail(422, p_label || ' inválida');
  end if;
  return round(la_obra_v2.num(v), 7);
end $$;

create or replace function la_obra_v2.distance_m(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(least(1, sqrt(
    sin(radians((lat2 - lat1)::float8) / 2) ^ 2
    + cos(radians(lat1::float8)) * cos(radians(lat2::float8)) * sin(radians((lng2 - lng1)::float8) / 2) ^ 2)));
$$;

create or replace function la_obra_v2.work_location_json()
returns jsonb language sql stable as $$
  select la_obra_v2.js(w) from (select id, name, latitude::float8 as latitude, longitude::float8 as longitude, radius_m, updated_at
                                   from la_obra_v2.work_location where id = 1) w;
$$;

create or replace function la_obra_v2.last_attendance_today(p_user int)
returns jsonb language sql stable as $$
  select la_obra_v2.js(a) from (select id, type, created_at from la_obra_v2.attendance
    where user_id = p_user and created_at::date = current_date order by created_at desc, id desc limit 1) a;
$$;

-- ---------- Mejoras (noviembre 2026) ----------

-- Cantidad de un ingrediente capturada en cualquiera de las medidas del insumo.
-- p_item: {quantity, unit_id?}. Si trae unit_id, "quantity" está en esa medida y se convierte
-- a la unidad principal; si no, "quantity" ya está en la unidad principal (como antes).
create or replace function la_obra_v2.item_quantity(p_input int, p_item jsonb,
  out o_qty numeric, out o_unit_id int, out o_unit_qty numeric)
language plpgsql as $$
declare v_q jsonb := coalesce(nullif(p_item -> 'unit_quantity', 'null'::jsonb), p_item -> 'quantity'); un la_obra_v2.input_units;
begin
  if not la_obra_v2.is_num(v_q) or la_obra_v2.num(v_q) <= 0 then perform la_obra_v2.fail(422, 'Indica la cantidad de cada ingrediente'); end if;
  if la_obra_v2.not_empty(p_item -> 'unit_id') then
    o_unit_id := la_obra_v2.positive_id(p_item -> 'unit_id', 'Medida inválida');
    select * into un from la_obra_v2.input_units where id = o_unit_id;
    if un.id is null or un.input_id <> p_input then perform la_obra_v2.fail(422, 'La medida elegida no corresponde al insumo'); end if;
    o_unit_qty := round(la_obra_v2.num(v_q), 3);
    o_qty := round(o_unit_qty * un.base_amount / un.unit_amount, 3);
    if o_qty <= 0 then perform la_obra_v2.fail(422, 'La cantidad es demasiado pequeña'); end if;
  else
    o_unit_id := null; o_unit_qty := null;
    o_qty := round(la_obra_v2.num(v_q), 3);
    if o_qty <= 0 then perform la_obra_v2.fail(422, 'Indica la cantidad de cada ingrediente'); end if;
  end if;
end $$;

-- Guarda las otras medidas de un insumo. p_units: [{id?, name, unit_amount, base_amount}]
-- Conserva las que siguen (por id), actualiza las recetas que las usan si cambió la equivalencia
-- y, si se quita una medida, sus ingredientes quedan con la misma cantidad en la unidad principal.
create or replace function la_obra_v2.save_input_units(p_input int, p_units jsonb)
returns void language plpgsql as $$
declare v_base text; it jsonb; v_name text; v_ua numeric; v_ba numeric; v_id int; v_keep int[] := '{}'; v_names text[] := '{}';
begin
  if p_units is null or jsonb_typeof(p_units) = 'null' then return; end if;
  if jsonb_typeof(p_units) <> 'array' then perform la_obra_v2.fail(422, 'Medidas inválidas'); end if;
  select lower(btrim(unit)) into v_base from la_obra_v2.inputs where id = p_input;
  -- Validar todo antes de escribir
  for it in select * from jsonb_array_elements(p_units) loop
    v_name := la_obra_v2.jstr(it -> 'name');
    if v_name = '' or char_length(v_name) > 30 then perform la_obra_v2.fail(422, 'Escribe el nombre de cada medida (máximo 30 letras)'); end if;
    if lower(v_name) = v_base then perform la_obra_v2.fail(422, '"' || v_name || '" ya es la unidad principal del insumo'); end if;
    if lower(v_name) = any(v_names) then perform la_obra_v2.fail(422, 'La medida "' || v_name || '" está repetida'); end if;
    v_names := v_names || lower(v_name);
    if not la_obra_v2.is_num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)) or la_obra_v2.num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)) <= 0
       or not la_obra_v2.is_num(it -> 'base_amount') or la_obra_v2.num(it -> 'base_amount') <= 0 then
      perform la_obra_v2.fail(422, 'Indica a cuánto equivale la medida "' || v_name || '"');
    end if;
    if la_obra_v2.not_empty(it -> 'id') then
      v_id := la_obra_v2.positive_id(it -> 'id', 'Medida inválida');
      if not exists(select 1 from la_obra_v2.input_units where id = v_id and input_id = p_input) then perform la_obra_v2.fail(422, 'Medida inválida'); end if;
      v_keep := v_keep || v_id;
    end if;
  end loop;
  -- Medidas quitadas: sus ingredientes conservan la cantidad (ya está en la unidad principal)
  update la_obra_v2.preparation_inputs set unit_id = null, unit_quantity = null
   where unit_id in (select id from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep)));
  update la_obra_v2.product_components set unit_id = null, unit_quantity = null
   where unit_id in (select id from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep)));
  delete from la_obra_v2.input_units where input_id = p_input and not (id = any(v_keep));
  -- Evitar choque de nombres al renombrar
  update la_obra_v2.input_units set name = '~' || id where input_id = p_input;
  for it in select * from jsonb_array_elements(p_units) loop
    v_name := la_obra_v2.jstr(it -> 'name');
    v_ua := round(la_obra_v2.num(coalesce(nullif(it -> 'unit_amount', 'null'::jsonb), '1'::jsonb)), 3);
    v_ba := round(la_obra_v2.num(it -> 'base_amount'), 4);
    if v_ua <= 0 or v_ba <= 0 then perform la_obra_v2.fail(422, 'Indica a cuánto equivale la medida "' || v_name || '"'); end if;
    if la_obra_v2.not_empty(it -> 'id') then
      v_id := la_obra_v2.num(it -> 'id')::int;
      update la_obra_v2.input_units set name = v_name, unit_amount = v_ua, base_amount = v_ba where id = v_id;
      -- Si cambió la equivalencia, las recetas capturadas en esta medida se recalculan
      update la_obra_v2.preparation_inputs set quantity = greatest(round(unit_quantity * v_ba / v_ua, 3), 0.001)
       where unit_id = v_id and unit_quantity is not null;
      update la_obra_v2.product_components set quantity = greatest(round(unit_quantity * v_ba / v_ua, 3), 0.001)
       where unit_id = v_id and unit_quantity is not null;
    else
      insert into la_obra_v2.input_units(input_id, name, unit_amount, base_amount) values (p_input, v_name, v_ua, v_ba);
    end if;
  end loop;
end $$;

-- Comisión que cobra la terminal por un pago (null si el método no tiene comisión)
create or replace function la_obra_v2.payment_commission(p_method int, p_amount numeric)
returns numeric language sql stable as $$
  select case when coalesce(pm.commission_percent, 0) > 0 and coalesce(p_amount, 0) > 0
              then round(p_amount * pm.commission_percent / 100, 2) end
    from la_obra_v2.payment_methods pm where pm.id = p_method;
$$;

-- >>>>>>>>>> 03_api_auth_usuarios.sql
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

-- users/delete.php (admin elimina una cuenta; si tiene historial, se desactiva para conservarlo)
create or replace function la_obra_v2.ep_users__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare me la_obra_v2.users; u la_obra_v2.users; v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  me := la_obra_v2.auth_long(t, true, 'No tienes permisos para eliminar usuarios');
  v_id := la_obra_v2.positive_id(coalesce(la_obra_v2.body(b) -> 'id', q -> 'id'), 'El id del usuario no es válido');
  select * into u from la_obra_v2.users where id = v_id for update;
  if u.id is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  if u.id = me.id then perform la_obra_v2.fail(422, 'No puedes eliminar tu propia cuenta'); end if;
  if u.role = 'admin' and u.status = 'active'
     and not exists(select 1 from la_obra_v2.users where role = 'admin' and status = 'active' and id <> v_id) then
    perform la_obra_v2.fail(422, 'El sistema debe conservar al menos un administrador activo');
  end if;
  begin
    -- Las asistencias se borrarían junto con la cuenta: se tratan como historial a conservar.
    if exists(select 1 from la_obra_v2.attendance where user_id = v_id) then
      raise foreign_key_violation;
    end if;
    delete from la_obra_v2.users where id = v_id;
    if u.avatar_path is not null then delete from la_obra_v2.files where path = u.avatar_path; end if;
    return la_obra_v2.ok(200, 'Usuario eliminado', jsonb_build_object('deleted', true, 'deactivated', false));
  exception when foreign_key_violation then
    -- Tiene ventas, compras, asistencias u otros registros: se conserva el historial y se bloquea el acceso.
    update la_obra_v2.users set status = 'inactive', updated_at = localtimestamp where id = v_id;
    delete from la_obra_v2.sessions where user_id = v_id;
    return la_obra_v2.ok(200, u.name || ' tiene movimientos registrados (ventas, compras, asistencias…). Para no perder ese historial, la cuenta se desactivó en lugar de borrarse.',
      jsonb_build_object('deleted', false, 'deactivated', true));
  end;
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

-- >>>>>>>>>> 04_api_catalogo_basico.sql
-- =====================================================================
-- La Obra v2 · 04 · categories/* y payment-methods/*
-- =====================================================================
set check_function_bodies = off;

-- Borrado que respeta las relaciones (el 23000 de MySQL = 23503 en PostgreSQL)
create or replace function la_obra_v2.delete_or_conflict(p_table text, p_id int)
returns jsonb language plpgsql as $$
begin
  begin
    execute format('delete from la_obra_v2.%I where id = $1', p_table) using p_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque el registro está relacionado con otros datos. Puedes desactivarlo para conservar el historial.');
  end;
  return la_obra_v2.ok(200, 'Registro eliminado correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Categorías', jsonb_build_object('categories', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status) order by name, id), '[]') from la_obra_v2.categories)));
end $$;

create or replace function la_obra_v2.ep_categories__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if v_name = '' then perform la_obra_v2.fail(422, 'El nombre es obligatorio'); end if;
  if exists(select 1 from la_obra_v2.categories where lower(name) = lower(v_name)) then perform la_obra_v2.fail(409, 'La categoría ya existe'); end if;
  insert into la_obra_v2.categories(name, status) values (v_name, 'active') returning id into v_id;
  return la_obra_v2.ok(201, 'Categoría registrada correctamente', jsonb_build_object('category', jsonb_build_object('id', v_id, 'name', v_name, 'status', 'active')));
end $$;

create or replace function la_obra_v2.ep_categories__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_id int;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 or v_name = '' then perform la_obra_v2.fail(422, 'Id y nombre válidos son obligatorios'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  if not exists(select 1 from la_obra_v2.categories where id = v_id) then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if exists(select 1 from la_obra_v2.categories where lower(name) = lower(v_name) and id <> v_id) then perform la_obra_v2.fail(409, 'Ya existe otra categoría con ese nombre'); end if;
  update la_obra_v2.categories set name = v_name where id = v_id;
  return la_obra_v2.ok(200, 'Categoría actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__activate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select status into v_status from la_obra_v2.categories where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if v_status = 'active' then perform la_obra_v2.fail(422, 'La categoría ya está activa'); end if;
  update la_obra_v2.categories set status = 'active' where id = v_id;
  return la_obra_v2.ok(200, 'Categoría activada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__deactivate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.categories where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if v_status <> 'active' then perform la_obra_v2.fail(422, 'La categoría ya está inactiva'); end if;
  update la_obra_v2.categories set status = 'inactive' where id = v_id;
  return la_obra_v2.ok(200, 'Categoría desactivada correctamente');
end $$;

create or replace function la_obra_v2.ep_categories__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.categories where id = v_id) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  return la_obra_v2.delete_or_conflict('categories', v_id);
end $$;

create or replace function la_obra_v2.ep_payment_methods__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Métodos de pago', jsonb_build_object('payment_methods', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status,
             'commission_percent', coalesce(commission_percent, 0)::float8) order by name, id), '[]') from la_obra_v2.payment_methods)));
end $$;

-- Porcentaje de comisión válido (0 a 99.99, dos decimales); p_default si no viene
create or replace function la_obra_v2.commission_value(v jsonb, p_default numeric default 0)
returns numeric language plpgsql as $$
begin
  if v is null or jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then return p_default; end if;
  if not la_obra_v2.is_num(v) or la_obra_v2.num(v) < 0 or la_obra_v2.num(v) >= 100 then
    perform la_obra_v2.fail(422, 'La comisión debe ser un porcentaje entre 0 y 99.99');
  end if;
  return round(la_obra_v2.num(v), 2);
end $$;

create or replace function la_obra_v2.ep_payment_methods__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if v_name = '' then perform la_obra_v2.fail(422, 'El nombre es obligatorio'); end if;
  if exists(select 1 from la_obra_v2.payment_methods where lower(name) = lower(v_name)) then perform la_obra_v2.fail(409, 'El método de pago ya existe'); end if;
  insert into la_obra_v2.payment_methods(name, status, commission_percent)
  values (v_name, 'active', la_obra_v2.commission_value(b -> 'commission_percent', case when lower(v_name) like '%tarjeta%' then 4 else 0 end)) returning id into v_id;
  return la_obra_v2.ok(201, 'Método de pago registrado correctamente', jsonb_build_object('payment_method', jsonb_build_object('id', v_id, 'name', v_name, 'status', 'active',
    'commission_percent', (select commission_percent::float8 from la_obra_v2.payment_methods where id = v_id))));
end $$;

create or replace function la_obra_v2.ep_payment_methods__status(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text := la_obra_v2.jtext(b -> 'status');
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 or coalesce(v_status, '') not in ('active','inactive') then
    perform la_obra_v2.fail(422, 'Datos inválidos');
  end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_id) then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
  update la_obra_v2.payment_methods set status = v_status where id = v_id;
  return la_obra_v2.ok(200, 'Estado del método de pago actualizado correctamente');
end $$;

-- payment-methods/commission.php · PATCH {id, commission_percent}: comisión de la terminal (ej. 4 para tarjeta)
-- Aplica a los cobros que se registren desde ese momento; los anteriores conservan la suya.
create or replace function la_obra_v2.ep_payment_methods__commission(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_pct numeric;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_id) then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
  if not (b ? 'commission_percent') then perform la_obra_v2.fail(422, 'Indica la comisión'); end if;
  v_pct := la_obra_v2.commission_value(b -> 'commission_percent', 0);
  update la_obra_v2.payment_methods set commission_percent = v_pct where id = v_id;
  return la_obra_v2.ok(200, 'Comisión actualizada', jsonb_build_object('payment_method', (
    select jsonb_build_object('id', id, 'name', name, 'status', status, 'commission_percent', commission_percent::float8)
      from la_obra_v2.payment_methods where id = v_id)));
end $$;

create or replace function la_obra_v2.ep_payment_methods__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_id) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  return la_obra_v2.delete_or_conflict('payment_methods', v_id);
end $$;

-- >>>>>>>>>> 05_api_productos.sql
-- =====================================================================
-- La Obra v2 · 05 · products/* y files/*
-- Las fotos se guardan en la tabla files con la misma ruta "uploads/<carpeta>/<nombre>".
-- La app manda la foto como data URL (data:image/jpeg;base64,...) en el campo "image".
-- =====================================================================
set check_function_bodies = off;

-- Valida y guarda una imagen enviada como data URL. Devuelve la ruta relativa.
create or replace function la_obra_v2.save_image(p_data jsonb, p_folder text, p_prefix text)
returns text language plpgsql as $$
declare s text := la_obra_v2.jtext(p_data); v_bytes bytea; v_mime text; v_ext text; v_path text;
begin
  if s is null or s = '' then perform la_obra_v2.fail(422, 'Selecciona una imagen'); end if;
  s := regexp_replace(s, '^data:[^,]*,', '');
  begin
    v_bytes := decode(regexp_replace(s, '\s', '', 'g'), 'base64');
  exception when others then perform la_obra_v2.fail(422, 'No se pudo recibir la imagen');
  end;
  if octet_length(v_bytes) <= 0 then perform la_obra_v2.fail(422, 'No se pudo recibir la imagen'); end if;
  if octet_length(v_bytes) > 3 * 1024 * 1024 then perform la_obra_v2.fail(413, 'La imagen debe pesar menos de 3 MB'); end if;
  -- Tipo real por los primeros bytes (no por lo que diga el cliente)
  if substring(v_bytes from 1 for 3) = '\xffd8ff'::bytea then v_mime := 'image/jpeg'; v_ext := 'jpg';
  elsif substring(v_bytes from 1 for 8) = '\x89504e470d0a1a0a'::bytea then v_mime := 'image/png'; v_ext := 'png';
  elsif substring(v_bytes from 1 for 4) = '\x52494646'::bytea and substring(v_bytes from 9 for 4) = '\x57454250'::bytea then v_mime := 'image/webp'; v_ext := 'webp';
  else perform la_obra_v2.fail(415, 'Formato no permitido. Usa JPG, PNG o WEBP');
  end if;
  v_path := 'uploads/' || p_folder || '/' || p_prefix || '_' || encode(extensions.gen_random_bytes(8), 'hex') || '.' || v_ext;
  insert into la_obra_v2.files(path, mime, data) values (v_path, v_mime, v_bytes);
  return v_path;
end $$;

create or replace function la_obra_v2.delete_file(p_path text, p_folder text)
returns void language sql as $$
  delete from la_obra_v2.files where p_path is not null and path = p_path and path like 'uploads/' || p_folder || '/%';
$$;

-- files/image.php?path=uploads/... → { data_url }
create or replace function la_obra_v2.ep_files__image(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_path text := coalesce(la_obra_v2.jtext(q -> 'path'), ''); f la_obra_v2.files;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  if v_path !~ '^uploads/(products|tickets|avatars)/[A-Za-z0-9_.-]+$' then perform la_obra_v2.fail(422, 'Ruta de imagen inválida'); end if;
  select * into f from la_obra_v2.files where path = v_path;
  if f.path is null then perform la_obra_v2.fail(404, 'La imagen no existe en el servidor'); end if;
  return la_obra_v2.ok(200, 'Imagen', jsonb_build_object('data_url', 'data:' || f.mime || ';base64,' || replace(encode(f.data, 'base64'), E'\n', '')));
end $$;

create or replace function la_obra_v2.product_json(p_id int)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description,
    'category', jsonb_build_object('id', c.id, 'name', c.name), 'type', p.type, 'price', p.price::float8,
    'is_available', p.is_available, 'status', p.status, 'image_path', p.image_path)
  from la_obra_v2.products p join la_obra_v2.categories c on c.id = p.category_id where p.id = p_id;
$$;

create or replace function la_obra_v2.ep_products__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Productos', jsonb_build_object('products',
    (select coalesce(jsonb_agg(la_obra_v2.product_json(id) order by id), '[]') from la_obra_v2.products)));
end $$;

create or replace function la_obra_v2.ep_products__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.is_int(q -> 'id') or la_obra_v2.num(q -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id del producto no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id')::int;
  r := la_obra_v2.product_json(v_id);
  if r is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok(200, 'Producto', jsonb_build_object('product', r));
end $$;

create or replace function la_obra_v2.ep_products__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text := la_obra_v2.jstr(b -> 'name'); v_desc text := la_obra_v2.jstr(b -> 'description');
        v_type text := la_obra_v2.jstr(b -> 'type'); v_cat int; v_price numeric; v_cs text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if v_name = '' or v_desc = '' or not la_obra_v2.is_int(b -> 'category_id') or la_obra_v2.num(b -> 'category_id') <= 0
     or v_type not in ('prepared','resale') or not la_obra_v2.is_num(b -> 'price') or la_obra_v2.num(b -> 'price') < 0 then
    perform la_obra_v2.fail(422, 'Los datos del producto no son válidos');
  end if;
  v_cat := la_obra_v2.num(b -> 'category_id')::int; v_price := la_obra_v2.num(b -> 'price');
  select status into v_cs from la_obra_v2.categories where id = v_cat;
  if v_cs is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
  if v_cs <> 'active' then perform la_obra_v2.fail(422, 'La categoría está inactiva'); end if;
  insert into la_obra_v2.products(name, description, category_id, type, price, is_available, status)
  values (v_name, v_desc, v_cat, v_type, round(v_price, 2), true, 'active') returning id into v_id;
  return la_obra_v2.ok(201, 'Producto registrado correctamente', jsonb_build_object('product', jsonb_build_object(
    'id', v_id, 'name', v_name, 'description', v_desc, 'category_id', v_cat, 'type', v_type, 'price', v_price::float8, 'is_available', true, 'status', 'active')));
end $$;

-- PHP: FILTER_VALIDATE_BOOLEAN con NULL_ON_FAILURE
create or replace function la_obra_v2.to_bool(v jsonb)
returns boolean language sql immutable as $$
  select case
    when v is null then null
    when jsonb_typeof(v) = 'boolean' then (v::text)::boolean
    when jsonb_typeof(v) = 'number' then case when v::text in ('1') then true when v::text in ('0') then false else null end
    when jsonb_typeof(v) = 'string' then case when lower(btrim(v #>> '{}')) in ('1','true','on','yes') then true
                                              when lower(btrim(v #>> '{}')) in ('0','false','off','no','') then false else null end
    when jsonb_typeof(v) = 'null' then false
    else null end;
$$;

create or replace function la_obra_v2.ep_products__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; p la_obra_v2.products; v text; v_cat int; v_cs text; v_bool boolean; n int := 0;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if b is null or jsonb_typeof(b) <> 'object' then b := '{}'; end if;
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select * into p from la_obra_v2.products where id = v_id;
  if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if b ? 'name' then
    v := la_obra_v2.jstr(b -> 'name'); if v = '' then perform la_obra_v2.fail(422, 'Nombre inválido'); end if;
    p.name := v; n := n + 1;
  end if;
  if b ? 'description' then
    v := la_obra_v2.jstr(b -> 'description'); if v = '' then perform la_obra_v2.fail(422, 'Descripción inválida'); end if;
    p.description := v; n := n + 1;
  end if;
  if b ? 'category_id' then
    if not la_obra_v2.is_int(b -> 'category_id') or la_obra_v2.num(b -> 'category_id') <= 0 then perform la_obra_v2.fail(422, 'Categoría inválida'); end if;
    v_cat := la_obra_v2.num(b -> 'category_id')::int;
    select status into v_cs from la_obra_v2.categories where id = v_cat;
    if v_cs is null then perform la_obra_v2.fail(404, 'Categoría no encontrada'); end if;
    if v_cs <> 'active' then perform la_obra_v2.fail(422, 'La categoría está inactiva'); end if;
    p.category_id := v_cat; n := n + 1;
  end if;
  if b ? 'type' then
    v := la_obra_v2.jstr(b -> 'type'); if v not in ('prepared','resale') then perform la_obra_v2.fail(422, 'Tipo inválido'); end if;
    p.type := v; n := n + 1;
  end if;
  if b ? 'price' then
    if not la_obra_v2.is_num(b -> 'price') or la_obra_v2.num(b -> 'price') < 0 then perform la_obra_v2.fail(422, 'Precio inválido'); end if;
    p.price := round(la_obra_v2.num(b -> 'price'), 2); n := n + 1;
  end if;
  if b ? 'is_available' then
    v_bool := la_obra_v2.to_bool(b -> 'is_available');
    if v_bool is null then perform la_obra_v2.fail(422, 'Disponibilidad inválida'); end if;
    p.is_available := v_bool; n := n + 1;
  end if;
  if n = 0 then perform la_obra_v2.fail(422, 'No se enviaron campos para actualizar'); end if;
  update la_obra_v2.products set name = p.name, description = p.description, category_id = p.category_id,
         type = p.type, price = p.price, is_available = p.is_available where id = v_id;
  return la_obra_v2.ok(200, 'Producto actualizado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__activate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.products where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_status = 'active' then perform la_obra_v2.fail(422, 'El producto ya está activo'); end if;
  update la_obra_v2.products set status = 'active', is_available = true where id = v_id;
  return la_obra_v2.ok(200, 'Producto activado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__deactivate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.products where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_status <> 'active' then perform la_obra_v2.fail(422, 'El producto ya está inactivo'); end if;
  update la_obra_v2.products set status = 'inactive', is_available = false where id = v_id;
  return la_obra_v2.ok(200, 'Producto desactivado correctamente');
end $$;

create or replace function la_obra_v2.ep_products__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_img text; r jsonb;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select image_path into v_img from la_obra_v2.products where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  r := la_obra_v2.delete_or_conflict('products', v_id);
  perform la_obra_v2.delete_file(v_img, 'products');
  return r;
end $$;

create or replace function la_obra_v2.ep_products__components(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  v_id := la_obra_v2.positive_id(q -> 'product_id');
  if not exists(select 1 from la_obra_v2.products where id = v_id) then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok(200, 'Composición consultada', jsonb_build_object('components',
    (select coalesce(jsonb_agg(to_jsonb(pc) order by pc.id), '[]') from la_obra_v2.product_components pc where pc.product_id = v_id)));
end $$;

-- "!empty(x)" de PHP
create or replace function la_obra_v2.not_empty(v jsonb)
returns boolean language sql immutable as $$
  select v is not null and jsonb_typeof(v) <> 'null' and not (
    (jsonb_typeof(v) = 'string' and (v #>> '{}') in ('', '0'))
    or (jsonb_typeof(v) = 'number' and (v::text)::numeric = 0)
    or (jsonb_typeof(v) = 'boolean' and v::text = 'false')
    or (jsonb_typeof(v) = 'array' and jsonb_array_length(v) = 0)
    or (jsonb_typeof(v) = 'object' and v = '{}'::jsonb));
$$;

create or replace function la_obra_v2.ep_products__save_components(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; it jsonb; v_in boolean; v_pr boolean; v_mode text; v_sid int; v_n bigint; v_qty numeric; v_uid int; v_uqty numeric;
begin
  perform la_obra_v2.method(m, 'PUT');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'product_id');
  if not exists(select 1 from la_obra_v2.products where id = v_id) then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if (b -> 'components') is null or jsonb_typeof(b -> 'components') not in ('array','object') then perform la_obra_v2.fail(422, 'Componentes inválidos'); end if;
  if jsonb_typeof(b -> 'components') = 'object' then b := jsonb_set(b, '{components}', (select coalesce(jsonb_agg(v), '[]') from jsonb_each(b -> 'components') e(k, v))); end if;
  for it in select * from jsonb_array_elements(b -> 'components') loop
    if jsonb_typeof(it) <> 'object' then perform la_obra_v2.fail(422, 'Componente inválido'); end if;
    v_in := la_obra_v2.not_empty(it -> 'input_id'); v_pr := la_obra_v2.not_empty(it -> 'preparation_id');
    v_mode := coalesce(la_obra_v2.jtext(it -> 'delivery_mode'), 'always');
    if v_in = v_pr or not la_obra_v2.is_num(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 or v_mode not in ('always','local','takeaway') then
      perform la_obra_v2.fail(422, 'Componente inválido');
    end if;
    v_sid := la_obra_v2.positive_id(case when v_in then it -> 'input_id' else it -> 'preparation_id' end);
    if (v_in and not exists(select 1 from la_obra_v2.inputs where id = v_sid)) or (v_pr and not exists(select 1 from la_obra_v2.preparations where id = v_sid)) then
      perform la_obra_v2.fail(422, 'Componente inexistente');
    end if;
    -- Insumo capturado en otra medida (pieza, cucharada…): se valida la medida
    if v_in then perform la_obra_v2.item_quantity(v_sid, it);
    elsif la_obra_v2.not_empty(it -> 'unit_id') then perform la_obra_v2.fail(422, 'Las preparaciones se capturan en su unidad de rendimiento');
    end if;
  end loop;
  delete from la_obra_v2.product_components where product_id = v_id;
  for it, v_n in select c, n from jsonb_array_elements(b -> 'components') with ordinality x(c, n) order by n loop
    v_in := la_obra_v2.not_empty(it -> 'input_id');
    if v_in then
      select o_qty, o_unit_id, o_unit_qty into v_qty, v_uid, v_uqty from la_obra_v2.item_quantity(la_obra_v2.num(it -> 'input_id')::int, it);
    else
      v_qty := round(la_obra_v2.num(it -> 'quantity'), 3); v_uid := null; v_uqty := null;
    end if;
    insert into la_obra_v2.product_components(product_id, input_id, preparation_id, quantity, is_estimated, delivery_mode, unit_id, unit_quantity)
    values (v_id,
            case when v_in then la_obra_v2.num(it -> 'input_id')::int end,
            case when la_obra_v2.not_empty(it -> 'preparation_id') then la_obra_v2.num(it -> 'preparation_id')::int end,
            v_qty,
            la_obra_v2.not_empty(it -> 'is_estimated'),
            coalesce(la_obra_v2.jtext(it -> 'delivery_mode'), 'always'),
            v_uid, v_uqty);
  end loop;
  return la_obra_v2.ok(200, 'Composición guardada');
end $$;

-- products/upload-image.php · campos: id, image (data URL)
create or replace function la_obra_v2.ep_products__upload_image(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text; v_path text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select image_path into v_old from la_obra_v2.products where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  v_path := la_obra_v2.save_image(b -> 'image', 'products', v_id::text);
  update la_obra_v2.products set image_path = v_path where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'products');
  return la_obra_v2.ok(200, 'Foto guardada correctamente', jsonb_build_object('image_path', v_path));
end $$;

create or replace function la_obra_v2.ep_products__delete_image(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select image_path into v_old from la_obra_v2.products where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if coalesce(v_old, '') = '' then return la_obra_v2.ok(200, 'El producto no tenía foto'); end if;
  update la_obra_v2.products set image_path = null where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'products');
  return la_obra_v2.ok(200, 'Foto eliminada correctamente');
end $$;

-- >>>>>>>>>> 06_api_insumos_recetas.sql
-- =====================================================================
-- La Obra v2 · 06 · inputs/*, recipes/*, preparations/*
-- =====================================================================
set check_function_bodies = off;

-- validInput() de service_helpers.php → (name, unit, package_type, package_quantity, min_stock)
create or replace function la_obra_v2.valid_input(d jsonb, out o_name text, out o_unit text, out o_ptype text, out o_pqty numeric, out o_min numeric)
language plpgsql as $$
declare v_qty jsonb; v_min jsonb;
begin
  o_name := la_obra_v2.jstr(d -> 'name'); o_unit := la_obra_v2.jstr(d -> 'unit');
  if o_name = '' or char_length(o_name) > 100 then perform la_obra_v2.fail(422, 'Escribe el nombre del insumo'); end if;
  if o_unit = '' or char_length(o_unit) > 20 then perform la_obra_v2.fail(422, 'Indica la unidad de medida'); end if;
  o_ptype := la_obra_v2.jstr(d -> 'package_type');
  if o_ptype = '' then o_ptype := o_unit; end if;
  if char_length(o_ptype) > 40 then perform la_obra_v2.fail(422, 'Presentación inválida'); end if;
  v_qty := coalesce(nullif(d -> 'package_quantity', 'null'::jsonb), '1'::jsonb);
  if not la_obra_v2.is_num(v_qty) or la_obra_v2.num(v_qty) <= 0 or la_obra_v2.num(v_qty) > 999999999 then
    perform la_obra_v2.fail(422, 'Indica cuántas unidades trae cada presentación');
  end if;
  o_pqty := round(la_obra_v2.num(v_qty), 3);
  v_min := d -> 'min_stock';
  if v_min is null or jsonb_typeof(v_min) = 'null' or (jsonb_typeof(v_min) = 'string' and v_min #>> '{}' = '') then
    o_min := null;
  else
    if not la_obra_v2.is_num(v_min) or la_obra_v2.num(v_min) < 0 then perform la_obra_v2.fail(422, 'Existencia mínima inválida'); end if;
    o_min := la_obra_v2.num(v_min);
  end if;
end $$;

create or replace function la_obra_v2.ep_inputs__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true);
  return la_obra_v2.ok(200, 'Insumos', jsonb_build_object('inputs', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'unit', unit, 'status', status, 'package_type', package_type,
      'package_quantity', package_quantity, 'package_content_unit', package_content_unit, 'min_stock', min_stock,
      'units', la_obra_v2.input_units_json(id)) order by name, id), '[]')
    from la_obra_v2.inputs)));
end $$;

create or replace function la_obra_v2.ep_inputs__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(q -> 'id') or la_obra_v2.num(q -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id')::int;
  select jsonb_build_object('id', id, 'name', name, 'unit', unit, 'status', status, 'package_type', package_type,
         'package_quantity', package_quantity, 'package_content_unit', package_content_unit, 'units', la_obra_v2.input_units_json(id))
    into r from la_obra_v2.inputs where id = v_id;
  if r is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok(200, 'Insumo', jsonb_build_object('input', r));
end $$;

create or replace function la_obra_v2.ep_inputs__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v record; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  select * into v from la_obra_v2.valid_input(b);
  if exists(select 1 from la_obra_v2.inputs where lower(name) = lower(v.o_name)) then perform la_obra_v2.fail(409, 'Ya existe un insumo con ese nombre'); end if;
  insert into la_obra_v2.inputs(name, unit, package_type, package_quantity, package_content_unit, min_stock, status)
  values (v.o_name, v.o_unit, v.o_ptype, v.o_pqty, v.o_unit, v.o_min, 'active') returning id into v_id;
  perform la_obra_v2.save_input_units(v_id, b -> 'units');
  return la_obra_v2.ok(201, 'Insumo registrado correctamente', jsonb_build_object('input', jsonb_build_object(
    'id', v_id, 'name', v.o_name, 'unit', v.o_unit, 'package_type', v.o_ptype, 'package_quantity', v.o_pqty::float8, 'min_stock', v.o_min, 'status', 'active',
    'stock', 0, 'unit_cost', null, 'stock_value', null, 'level', 'out', 'units', la_obra_v2.input_units_json(v_id))));
end $$;

create or replace function la_obra_v2.ep_inputs__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; o la_obra_v2.inputs; v record; merged jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select * into o from la_obra_v2.inputs where id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  merged := jsonb_build_object(
    'name', coalesce(nullif(b -> 'name', 'null'::jsonb), to_jsonb(o.name)),
    'unit', coalesce(nullif(b -> 'unit', 'null'::jsonb), to_jsonb(o.unit)),
    'package_type', coalesce(nullif(b -> 'package_type', 'null'::jsonb), to_jsonb(o.package_type)),
    'package_quantity', coalesce(nullif(b -> 'package_quantity', 'null'::jsonb), to_jsonb(o.package_quantity)),
    'min_stock', case when b ? 'min_stock' then b -> 'min_stock' else to_jsonb(o.min_stock) end);
  select * into v from la_obra_v2.valid_input(merged);
  if exists(select 1 from la_obra_v2.inputs where lower(name) = lower(v.o_name) and id <> v_id) then perform la_obra_v2.fail(409, 'Ya existe un insumo con ese nombre'); end if;
  update la_obra_v2.inputs set name = v.o_name, unit = v.o_unit, package_type = v.o_ptype, package_quantity = v.o_pqty,
         package_content_unit = v.o_unit, min_stock = v.o_min where id = v_id;
  if b ? 'units' then perform la_obra_v2.save_input_units(v_id, b -> 'units'); end if;
  return la_obra_v2.ok(200, 'Insumo actualizado correctamente', jsonb_build_object('units', la_obra_v2.input_units_json(v_id)));
end $$;

create or replace function la_obra_v2.ep_inputs__activate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  update la_obra_v2.inputs set status = 'active' where id = v_id;
  return la_obra_v2.ok(200, 'Insumo activado correctamente');
end $$;

create or replace function la_obra_v2.ep_inputs__deactivate(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_status text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'id') or la_obra_v2.num(b -> 'id') <= 0 then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'id')::int;
  select status into v_status from la_obra_v2.inputs where id = v_id;
  if v_status is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  if v_status <> 'active' then perform la_obra_v2.fail(422, 'El insumo ya está inactivo'); end if;
  update la_obra_v2.inputs set status = 'inactive' where id = v_id;
  return la_obra_v2.ok(200, 'Insumo desactivado correctamente');
end $$;

create or replace function la_obra_v2.ep_inputs__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Registro no encontrado'); end if;
  if exists(select 1 from la_obra_v2.inventory_movements where input_id = v_id)
     or exists(select 1 from la_obra_v2.purchase_items where input_id = v_id)
     or exists(select 1 from la_obra_v2.product_components where input_id = v_id)
     or exists(select 1 from la_obra_v2.preparation_inputs where input_id = v_id) then
    perform la_obra_v2.fail(409, 'Este insumo ya tiene compras, recetas o movimientos de inventario. Desactívalo para conservar el historial.');
  end if;
  return la_obra_v2.delete_or_conflict('inputs', v_id);
end $$;

-- inputs/dependencies.php?type=input|product|preparation|...&id=N
create or replace function la_obra_v2.ep_inputs__dependencies(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_type text := coalesce(la_obra_v2.jtext(q -> 'type'), 'input'); v_id int; v_table text; v_found boolean; rel jsonb := '[]';
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'id');
  v_table := case v_type when 'input' then 'inputs' when 'product' then 'products' when 'preparation' then 'preparations'
    when 'waste' then 'waste_records' when 'recipe' then 'recipes' when 'component' then 'product_components'
    when 'preparation_input' then 'preparation_inputs' when 'purchase_item' then 'purchase_items' when 'order_item' then 'order_items' end;
  if v_table is null then perform la_obra_v2.fail(422, 'Tipo de registro inválido'); end if;
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)', v_table) into v_found using v_id;
  if not v_found then perform la_obra_v2.fail(404, 'El registro ya no existe'); end if;

  if v_type = 'input' then
    select coalesce(jsonb_agg(x order by n), '[]') into rel from (
      select 1 n, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Producto que utiliza el insumo','deletable',true) x from la_obra_v2.recipes r join la_obra_v2.products p on p.id = r.product_id where r.input_id = v_id
      union all select 2, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Componente de producto','deletable',true) from la_obra_v2.product_components pc join la_obra_v2.products p on p.id = pc.product_id where pc.input_id = v_id
      union all select 3, jsonb_build_object('type','preparation','id',pr.id,'label',pr.name,'detail','Preparación que utiliza el insumo','deletable',true) from la_obra_v2.preparation_inputs pi join la_obra_v2.preparations pr on pr.id = pi.preparation_id where pi.input_id = v_id
      union all select 4, jsonb_build_object('type','waste','id',w.id,'label','Merma del ' || w.waste_date,'detail','Registro de merma','deletable',true) from la_obra_v2.waste_records w where w.input_id = v_id
      union all select 5, jsonb_build_object('type','purchase_item','id',pi.id,'label','Compra del ' || p.purchase_date,'detail','Movimiento histórico de compra','deletable',false) from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id where pi.input_id = v_id
    ) s;
  elsif v_type = 'product' then
    select coalesce(jsonb_agg(x order by n), '[]') into rel from (
      select 1 n, jsonb_build_object('type','recipe','id',r.id,'label','Ingrediente de receta #' || r.id,'detail','Relación con insumo','deletable',true) x from la_obra_v2.recipes r where r.product_id = v_id
      union all select 2, jsonb_build_object('type','component','id',pc.id,'label','Componente #' || pc.id,'detail','Composición del producto','deletable',true) from la_obra_v2.product_components pc where pc.product_id = v_id
      union all select 3, jsonb_build_object('type','waste','id',w.id,'label','Merma del ' || w.waste_date,'detail','Registro de merma','deletable',true) from la_obra_v2.waste_records w where w.product_id = v_id
      union all select 4, jsonb_build_object('type','order_item','id',oi.id,'label','Venta #' || oi.order_id,'detail','Historial de venta protegido','deletable',false) from la_obra_v2.order_items oi where oi.product_id = v_id
    ) s;
  elsif v_type = 'preparation' then
    select coalesce(jsonb_agg(x order by n), '[]') into rel from (
      select 1 n, jsonb_build_object('type','preparation_input','id',pi.id,'label','Ingrediente de preparación #' || pi.id,'detail','Componente de preparación','deletable',true) x from la_obra_v2.preparation_inputs pi where pi.preparation_id = v_id
      union all select 2, jsonb_build_object('type','product','id',p.id,'label',p.name,'detail','Producto que utiliza la preparación','deletable',true) from la_obra_v2.product_components pc join la_obra_v2.products p on p.id = pc.product_id where pc.preparation_id = v_id
      union all select 3, jsonb_build_object('type','waste','id',w.id,'label','Merma del ' || w.waste_date,'detail','Registro de merma','deletable',true) from la_obra_v2.waste_records w where w.preparation_id = v_id
    ) s;
  end if;
  -- Quitar repetidos (mismo tipo e id): se queda el último, como en PHP
  select coalesce(jsonb_agg(x order by first_n), '[]') into rel from (
    select distinct on (x ->> 'type', x ->> 'id') x, min(n) over (partition by x ->> 'type', x ->> 'id') first_n, n
      from jsonb_array_elements(rel) with ordinality a(x, n) order by x ->> 'type', x ->> 'id', n desc) d;
  return la_obra_v2.ok(200, 'Relaciones consultadas', jsonb_build_object('type', v_type, 'id', v_id, 'relations', rel));
end $$;

create or replace function la_obra_v2.ep_inputs__delete_related(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_type text; v_id int; v_table text; v_found boolean;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_type := coalesce(la_obra_v2.jtext(b -> 'type'), '');
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_table := case v_type when 'input' then 'inputs' when 'product' then 'products' when 'preparation' then 'preparations'
    when 'waste' then 'waste_records' when 'recipe' then 'recipes' when 'component' then 'product_components'
    when 'preparation_input' then 'preparation_inputs' end;
  if v_table is null then perform la_obra_v2.fail(422, 'Tipo de registro no permitido'); end if;
  execute format('select exists(select 1 from la_obra_v2.%I where id = $1)', v_table) into v_found using v_id;
  if not v_found then perform la_obra_v2.fail(404, 'El registro ya no existe'); end if;
  begin
    execute format('delete from la_obra_v2.%I where id = $1', v_table) using v_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'Este registro todavía tiene relaciones. Revisa la lista y elimínalas individualmente.');
  end;
  return la_obra_v2.ok(200, 'Registro eliminado correctamente', jsonb_build_object('type', v_type, 'id', v_id));
end $$;

-- ---------- Recetas (tabla recipes, formato anterior) ----------
create or replace function la_obra_v2.recipe_items_check(p_inputs jsonb)
returns void language plpgsql as $$
declare i jsonb; v_iid int; v_st text;
begin
  for i in select * from jsonb_array_elements(p_inputs) loop
    if not la_obra_v2.is_int(i -> 'input_id') or la_obra_v2.num(i -> 'input_id') <= 0 or not la_obra_v2.is_num(i -> 'quantity') or la_obra_v2.num(i -> 'quantity') <= 0 then
      perform la_obra_v2.fail(422, 'Datos de insumo inválidos');
    end if;
    v_iid := la_obra_v2.num(i -> 'input_id')::int;
    select status into v_st from la_obra_v2.inputs where id = v_iid;
    if v_st is null then perform la_obra_v2.fail(404, 'Insumo no encontrado: ' || v_iid); end if;
    if v_st <> 'active' then perform la_obra_v2.fail(422, 'El insumo ' || v_iid || ' está inactivo'); end if;
  end loop;
end $$;

create or replace function la_obra_v2.ep_recipes__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_pid int; v_type text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.num(b -> 'product_id') <= 0 or jsonb_typeof(b -> 'inputs') is distinct from 'array' or jsonb_array_length(b -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Producto e insumos válidos son obligatorios');
  end if;
  v_pid := la_obra_v2.num(b -> 'product_id')::int;
  select type into v_type from la_obra_v2.products where id = v_pid;
  if v_type is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_type <> 'prepared' then perform la_obra_v2.fail(422, 'Solo los productos preparados pueden tener receta'); end if;
  if exists(select 1 from la_obra_v2.recipes where product_id = v_pid) then perform la_obra_v2.fail(409, 'El producto ya tiene una receta registrada'); end if;
  perform la_obra_v2.recipe_items_check(b -> 'inputs');
  insert into la_obra_v2.recipes(product_id, input_id, quantity)
  select v_pid, la_obra_v2.num(i -> 'input_id')::int, round(la_obra_v2.num(i -> 'quantity'), 3) from jsonb_array_elements(b -> 'inputs') i;
  return la_obra_v2.ok(201, 'Receta registrada correctamente');
end $$;

create or replace function la_obra_v2.ep_recipes__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_pid int; v_type text;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(b -> 'product_id') or la_obra_v2.num(b -> 'product_id') <= 0 or jsonb_typeof(b -> 'inputs') is distinct from 'array' or jsonb_array_length(b -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Producto e insumos válidos son obligatorios');
  end if;
  v_pid := la_obra_v2.num(b -> 'product_id')::int;
  select type into v_type from la_obra_v2.products where id = v_pid;
  if v_type is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if v_type <> 'prepared' then perform la_obra_v2.fail(422, 'Solo los productos preparados pueden tener receta'); end if;
  if not exists(select 1 from la_obra_v2.recipes where product_id = v_pid) then perform la_obra_v2.fail(404, 'Receta no encontrada'); end if;
  perform la_obra_v2.recipe_items_check(b -> 'inputs');
  delete from la_obra_v2.recipes where product_id = v_pid;
  insert into la_obra_v2.recipes(product_id, input_id, quantity)
  select v_pid, la_obra_v2.num(i -> 'input_id')::int, round(la_obra_v2.num(i -> 'quantity'), 3) from jsonb_array_elements(b -> 'inputs') i;
  return la_obra_v2.ok(200, 'Receta actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_recipes__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_pid int; p record; v_rows jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t, true);
  if not la_obra_v2.is_int(q -> 'product_id') or la_obra_v2.num(q -> 'product_id') <= 0 then perform la_obra_v2.fail(422, 'El id del producto no es válido'); end if;
  v_pid := la_obra_v2.num(q -> 'product_id')::int;
  select id, name, type into p from la_obra_v2.products where id = v_pid;
  if p.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if p.type <> 'prepared' then perform la_obra_v2.fail(422, 'El producto no es de tipo prepared'); end if;
  select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'quantity', r.quantity::float8, 'unit', i.unit) order by i.name)
    into v_rows from la_obra_v2.recipes r join la_obra_v2.inputs i on i.id = r.input_id where r.product_id = v_pid;
  if v_rows is null then perform la_obra_v2.fail(404, 'El producto no tiene receta registrada'); end if;
  return la_obra_v2.ok(200, 'Receta', jsonb_build_object('recipe', jsonb_build_object('product', jsonb_build_object('id', p.id, 'name', p.name), 'inputs', v_rows)));
end $$;

-- ---------- Preparaciones ----------
create or replace function la_obra_v2.ep_preparations__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  return la_obra_v2.ok(200, 'Preparaciones consultadas', jsonb_build_object('preparations', (
    select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object(
      'yield_quantity', p.yield_quantity::float8,
      'inputs', (select coalesce(jsonb_agg(jsonb_build_object('input_id', pi.input_id, 'quantity', pi.quantity::float8, 'is_estimated', pi.is_estimated,
                   'name', i.name, 'unit', i.unit, 'unit_id', pi.unit_id, 'unit_quantity', pi.unit_quantity::float8, 'unit_name', un.name) order by i.name), '[]')
                   from la_obra_v2.preparation_inputs pi join la_obra_v2.inputs i on i.id = pi.input_id
                   left join la_obra_v2.input_units un on un.id = pi.unit_id where pi.preparation_id = p.id),
      'batch_cost', c -> 'batch_cost', 'unit_cost', c -> 'unit_cost', 'missing_prices', coalesce(c -> 'missing', '[]'))
      order by p.name, p.id), '[]')
    from la_obra_v2.preparations p cross join lateral (select la_obra_v2.preparation_cost(p.id) c) x)));
end $$;

create or replace function la_obra_v2.prep_validate(d jsonb, out o_name text, out o_desc text, out o_yield numeric, out o_unit text)
language plpgsql as $$
declare i jsonb; v_iid int; seen int[] := '{}';
begin
  o_name := la_obra_v2.jstr(d -> 'name'); o_desc := la_obra_v2.jstr(d -> 'description');
  o_unit := la_obra_v2.jtext(d -> 'yield_unit');
  if o_name = '' or char_length(o_name) > 120 or char_length(o_desc) > 255 or not la_obra_v2.is_num(d -> 'yield_quantity')
     or la_obra_v2.num(d -> 'yield_quantity') <= 0 or (d -> 'yield_unit') is null or jsonb_typeof(d -> 'yield_unit') <> 'string'
     or o_unit not in ('portion','piece','g','ml') or jsonb_typeof(d -> 'inputs') is distinct from 'array' or jsonb_array_length(d -> 'inputs') = 0 then
    perform la_obra_v2.fail(422, 'Nombre, rendimiento e ingredientes válidos son obligatorios');
  end if;
  o_yield := round(la_obra_v2.num(d -> 'yield_quantity'), 3);
  for i in select * from jsonb_array_elements(d -> 'inputs') loop
    v_iid := la_obra_v2.positive_id(i -> 'input_id');
    if v_iid = any(seen) or not la_obra_v2.is_num(coalesce(nullif(i -> 'unit_quantity', 'null'::jsonb), i -> 'quantity'))
       or la_obra_v2.num(coalesce(nullif(i -> 'unit_quantity', 'null'::jsonb), i -> 'quantity')) <= 0 then
      perform la_obra_v2.fail(422, 'Insumos duplicados o cantidades inválidas');
    end if;
    seen := seen || v_iid;
    if not exists(select 1 from la_obra_v2.inputs where id = v_iid and status = 'active') then perform la_obra_v2.fail(422, 'Insumo inexistente o inactivo'); end if;
    perform la_obra_v2.item_quantity(v_iid, i);  -- valida la medida (pieza, cucharada…) si viene
  end loop;
end $$;

-- Cada ingrediente se guarda en la unidad principal (quantity) y, si se capturó en otra medida,
-- también la medida y la cantidad tal como se escribió (unit_id, unit_quantity).
create or replace function la_obra_v2.prep_save_inputs(p_id int, d jsonb)
returns void language plpgsql as $$
declare i jsonb; n bigint; v_iid int; v_qty numeric; v_uid int; v_uqty numeric;
begin
  delete from la_obra_v2.preparation_inputs where preparation_id = p_id;
  for i, n in select x.i, x.n from jsonb_array_elements(d -> 'inputs') with ordinality x(i, n) order by x.n loop
    v_iid := la_obra_v2.num(i -> 'input_id')::int;
    select o_qty, o_unit_id, o_unit_qty into v_qty, v_uid, v_uqty from la_obra_v2.item_quantity(v_iid, i);
    insert into la_obra_v2.preparation_inputs(preparation_id, input_id, quantity, is_estimated, unit_id, unit_quantity)
    values (p_id, v_iid, v_qty, la_obra_v2.not_empty(i -> 'is_estimated'), v_uid, v_uqty);
  end loop;
end $$;

create or replace function la_obra_v2.ep_preparations__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v record; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  select * into v from la_obra_v2.prep_validate(b);
  insert into la_obra_v2.preparations(name, description, yield_quantity, yield_unit, yield_estimated)
  values (v.o_name, v.o_desc, v.o_yield, v.o_unit, la_obra_v2.not_empty(b -> 'yield_estimated')) returning id into v_id;
  perform la_obra_v2.prep_save_inputs(v_id, b);
  return la_obra_v2.ok(200, 'Preparación guardada', jsonb_build_object('id', v_id));
end $$;

create or replace function la_obra_v2.ep_preparations__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v record; v_id int;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select * into v from la_obra_v2.prep_validate(b);
  if not exists(select 1 from la_obra_v2.preparations where id = v_id) then perform la_obra_v2.fail(404, 'Preparación no encontrada'); end if;
  update la_obra_v2.preparations set name = v.o_name, description = v.o_desc, yield_quantity = v.o_yield, yield_unit = v.o_unit,
         yield_estimated = la_obra_v2.not_empty(b -> 'yield_estimated'), updated_at = localtimestamp where id = v_id;
  perform la_obra_v2.prep_save_inputs(v_id, b);
  return la_obra_v2.ok(200, 'Preparación guardada', jsonb_build_object('id', v_id));
end $$;

create or replace function la_obra_v2.ep_preparations__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  perform 1 from la_obra_v2.preparations where id = v_id for update;
  if not found then perform la_obra_v2.fail(404, 'La preparación no existe o ya fue eliminada'); end if;
  if exists(select 1 from la_obra_v2.product_components where preparation_id = v_id) then
    perform la_obra_v2.fail(409, 'No se puede eliminar: esta preparación está utilizada en un producto. Retírala de la composición del producto antes de eliminarla.');
  end if;
  begin
    delete from la_obra_v2.preparation_inputs where preparation_id = v_id;
    delete from la_obra_v2.preparations where id = v_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'No se puede eliminar porque la preparación está relacionada con otros registros o con el historial.');
  end;
  return la_obra_v2.ok(200, 'Preparación eliminada correctamente', jsonb_build_object('id', v_id));
end $$;

-- >>>>>>>>>> 07_api_pedidos_ventas.sql
-- =====================================================================
-- La Obra v2 · 07 · orders/* y sales/*
-- =====================================================================
set check_function_bodies = off;

create or replace function la_obra_v2.order_items_json(p_order int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('product_id', oi.product_id, 'name', p.name, 'quantity', oi.quantity,
    'unit_price', oi.unit_price::float8, 'subtotal', oi.subtotal::float8) order by oi.id), '[]')
  from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id where oi.order_id = p_order;
$$;

create or replace function la_obra_v2.order_recalc(p_order int)
returns void language sql as $$
  update la_obra_v2.orders set total = (select coalesce(sum(subtotal), 0) from la_obra_v2.order_items where order_id = p_order) where id = p_order;
$$;

create or replace function la_obra_v2.int_arg(v jsonb)
returns boolean language sql immutable as $$ select la_obra_v2.is_int(v) and la_obra_v2.num(v) > 0; $$;

create or replace function la_obra_v2.ep_orders__active(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Pedidos en curso', jsonb_build_object('orders', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'total', o.total::float8, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name, 'created_at', o.created_at,
      'confirmed_at', o.confirmed_at, 'user_name', u.name, 'items', la_obra_v2.order_items_json(o.id)) order by o.created_at, o.id), '[]')
    from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id
    where o.order_status = 'confirmed' and (o.payment_status = 'pending' or o.delivery_status = 'pending'))));
end $$;

create or replace function la_obra_v2.ep_orders__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_mode text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t);
  if b is null or jsonb_typeof(b) <> 'object' then b := '{}'; end if;
  v_mode := coalesce(la_obra_v2.jtext(b -> 'delivery_mode'), 'local');
  if v_mode not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  insert into la_obra_v2.orders(user_id, order_status, payment_status, delivery_status, delivery_mode, total)
  values (u.id, 'open', 'pending', 'pending', v_mode, 0) returning id into v_id;
  return la_obra_v2.ok(201, 'Pedido creado correctamente', jsonb_build_object('order', jsonb_build_object('id', v_id, 'status', 'open', 'total', 0.0)));
end $$;

create or replace function la_obra_v2.ep_orders__add_item(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_p int; v_q int; v_st text; pr record; v_sub numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'product_id') or not la_obra_v2.int_arg(b -> 'quantity') then
    perform la_obra_v2.fail(422, 'Los datos del producto no son válidos');
  end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_p := la_obra_v2.num(b -> 'product_id'); v_q := la_obra_v2.num(b -> 'quantity');
  select order_status into v_st from la_obra_v2.orders where id = v_o;
  if v_st is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if v_st <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  select id, price, status, is_available into pr from la_obra_v2.products where id = v_p;
  if pr.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  if pr.status <> 'active' or not pr.is_available then perform la_obra_v2.fail(422, 'El producto no está disponible'); end if;
  if exists(select 1 from la_obra_v2.order_items where order_id = v_o and product_id = v_p) then
    perform la_obra_v2.fail(409, 'El producto ya está en el pedido; modifica su cantidad');
  end if;
  v_sub := pr.price * v_q;
  insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal) values (v_o, v_p, v_q, pr.price, v_sub);
  perform la_obra_v2.order_recalc(v_o);
  return la_obra_v2.ok(201, 'Producto agregado al pedido', jsonb_build_object('item', jsonb_build_object('product_id', v_p, 'quantity', v_q,
    'unit_price', pr.price::float8, 'subtotal', v_sub::float8)));
end $$;

create or replace function la_obra_v2.ep_orders__update_item(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_p int; v_q int; v_st text; v_price numeric;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'product_id') or not la_obra_v2.int_arg(b -> 'quantity') then
    perform la_obra_v2.fail(422, 'Datos inválidos');
  end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_p := la_obra_v2.num(b -> 'product_id'); v_q := la_obra_v2.num(b -> 'quantity');
  select order_status into v_st from la_obra_v2.orders where id = v_o;
  if v_st is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if v_st <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  select unit_price into v_price from la_obra_v2.order_items where order_id = v_o and product_id = v_p;
  if v_price is null then perform la_obra_v2.fail(404, 'El producto no está en el pedido'); end if;
  update la_obra_v2.order_items set quantity = v_q, subtotal = v_price * v_q where order_id = v_o and product_id = v_p;
  perform la_obra_v2.order_recalc(v_o);
  return la_obra_v2.ok(200, 'Cantidad actualizada correctamente');
end $$;

create or replace function la_obra_v2.ep_orders__remove_item(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_p int; v_st text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'product_id') then perform la_obra_v2.fail(422, 'Datos inválidos'); end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_p := la_obra_v2.num(b -> 'product_id');
  select order_status into v_st from la_obra_v2.orders where id = v_o;
  if v_st is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if v_st <> 'open' then perform la_obra_v2.fail(409, 'El pedido ya no puede modificarse'); end if;
  if not exists(select 1 from la_obra_v2.order_items where order_id = v_o and product_id = v_p) then perform la_obra_v2.fail(404, 'El producto no está en el pedido'); end if;
  delete from la_obra_v2.order_items where order_id = v_o and product_id = v_p;
  perform la_obra_v2.order_recalc(v_o);
  return la_obra_v2.ok(200, 'Producto eliminado del pedido');
end $$;

create or replace function la_obra_v2.ep_orders__confirm(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; o record; l record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, delivery_mode into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'open' then perform la_obra_v2.fail(409, 'El pedido no está abierto'); end if;
  if not exists(select 1 from la_obra_v2.order_items where order_id = v_id) then perform la_obra_v2.fail(422, 'No se puede confirmar un pedido vacío'); end if;
  for l in select id, product_id from la_obra_v2.order_items where order_id = v_id loop
    update la_obra_v2.order_items set standard_unit_cost = (la_obra_v2.product_cost(l.product_id, coalesce(nullif(o.delivery_mode, ''), 'local')) ->> 'standard_cost')::numeric where id = l.id;
  end loop;
  perform la_obra_v2.order_recalc(v_id);
  update la_obra_v2.orders set order_status = 'confirmed', confirmed_at = localtimestamp where id = v_id;
  return la_obra_v2.ok(200, 'Pedido confirmado correctamente');
end $$;

create or replace function la_obra_v2.ep_orders__deliver(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, delivery_status into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'Solo se puede entregar un pedido confirmado'); end if;
  if o.delivery_status = 'delivered' then perform la_obra_v2.fail(409, 'El pedido ya fue entregado'); end if;
  update la_obra_v2.orders set delivery_status = 'delivered', delivered_at = localtimestamp where id = v_id;
  perform la_obra_v2.inv_consume_order(v_id, u.id);
  return la_obra_v2.ok(200, 'Pedido entregado; inventario descontado');
end $$;

create or replace function la_obra_v2.ep_orders__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, payment_status into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status = 'cancelled' or o.payment_status = 'paid' then perform la_obra_v2.fail(409, 'Solo se puede cancelar un pedido que no se ha cobrado'); end if;
  update la_obra_v2.orders set order_status = 'cancelled', cancelled_at = localtimestamp where id = v_id;
  perform la_obra_v2.inv_reverse_order(v_id, u.id);
  return la_obra_v2.ok(200, 'Pedido cancelado correctamente');
end $$;

create or replace function la_obra_v2.ep_orders__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(q -> 'id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id');
  select jsonb_build_object('id', o.id, 'user_id', o.user_id, 'user_name', u.name, 'order_status', o.order_status, 'payment_status', o.payment_status,
    'delivery_status', o.delivery_status, 'total', o.total::float8, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at,
    'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at, 'items', la_obra_v2.order_items_json(o.id))
    into r from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id where o.id = v_id;
  if r is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  return la_obra_v2.ok(200, 'Pedido', jsonb_build_object('order', r));
end $$;

-- orders/checkout.php: venta completa en un paso (pedido + cobro opcional + entrega opcional)
create or replace function la_obra_v2.ep_orders__checkout(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_mode text; v_customer text; it jsonb; v_pid int; v_q int; v_lines jsonb := '{}'; k text;
        pr record; v_payment jsonb; pm record; v_deliver boolean; v_order int; v_total numeric := 0; v_sub numeric;
        v_cash numeric; v_change numeric; v_cash_j jsonb; v_fee numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_mode := coalesce(la_obra_v2.jtext(b -> 'delivery_mode'), 'local');
  if (b -> 'delivery_mode') is not null and jsonb_typeof(b -> 'delivery_mode') = 'null' then v_mode := 'local'; end if;
  if v_mode not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  v_customer := la_obra_v2.jstr(b -> 'customer_name');
  if char_length(v_customer) > 80 then perform la_obra_v2.fail(422, 'Nombre del cliente demasiado largo'); end if;
  if jsonb_typeof(b -> 'items') is distinct from 'array' or jsonb_array_length(b -> 'items') = 0 then perform la_obra_v2.fail(422, 'Agrega al menos un producto'); end if;
  for it in select * from jsonb_array_elements(b -> 'items') loop
    v_pid := la_obra_v2.positive_id(it -> 'product_id');
    if not la_obra_v2.is_int(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 or la_obra_v2.num(it -> 'quantity') > 999 then
      perform la_obra_v2.fail(422, 'Cantidad inválida');
    end if;
    v_q := la_obra_v2.num(it -> 'quantity');
    v_lines := jsonb_set(v_lines, array[v_pid::text], to_jsonb(coalesce((v_lines ->> v_pid::text)::int, 0) + v_q));
  end loop;
  for k in select key from jsonb_each(v_lines) loop
    select id, name, price, status, is_available into pr from la_obra_v2.products where id = k::int;
    if pr.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
    if pr.status <> 'active' or not pr.is_available then perform la_obra_v2.fail(409, pr.name || ' no está disponible'); end if;
  end loop;
  v_payment := b -> 'payment';
  if v_payment is not null and jsonb_typeof(v_payment) <> 'null' then
    select id, name into pm from la_obra_v2.payment_methods where id = la_obra_v2.positive_id(v_payment -> 'payment_method_id') and status = 'active';
    if pm.id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado o inactivo'); end if;
  else
    v_payment := null;
  end if;
  v_deliver := la_obra_v2.not_empty(b -> 'deliver_now');

  insert into la_obra_v2.orders(user_id, order_status, payment_status, delivery_status, delivery_mode, customer_name, total)
  values (u.id, 'open', 'pending', 'pending', v_mode, nullif(v_customer, ''), 0) returning id into v_order;
  -- En el orden en que llegaron los productos
  for k, v_q in select e.key, e.value::int from jsonb_each_text(v_lines) e
                 order by (select min(n) from jsonb_array_elements(b -> 'items') with ordinality a(x, n) where la_obra_v2.jtext(x -> 'product_id')::int = e.key::int) loop
    select price into pr from la_obra_v2.products where id = k::int;
    v_sub := round(pr.price * v_q, 2);
    v_total := v_total + v_sub;
    insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal, standard_unit_cost)
    values (v_order, k::int, v_q, pr.price, v_sub, (la_obra_v2.product_cost(k::int, v_mode) ->> 'standard_cost')::numeric);
  end loop;
  v_total := round(v_total, 2);
  update la_obra_v2.orders set total = v_total, order_status = 'confirmed', confirmed_at = localtimestamp where id = v_order;
  v_change := null;
  if v_payment is not null then
    v_cash := null;
    if lower(btrim(pm.name)) = 'efectivo' then
      v_cash_j := coalesce(nullif(v_payment -> 'cash_received', 'null'::jsonb), to_jsonb(v_total));
      if not la_obra_v2.is_num(v_cash_j) or la_obra_v2.num(v_cash_j) < v_total then
        perform la_obra_v2.fail(422, 'El efectivo recibido debe cubrir el total ($' || to_char(v_total, 'FM999,999,990.00') || ')');
      end if;
      v_cash := la_obra_v2.num(v_cash_j);
      v_change := round(v_cash - v_total, 2);
    end if;
    v_fee := la_obra_v2.payment_commission(pm.id, v_total);
    insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount, commission_amount)
    values (v_order, pm.id, v_total, round(v_cash, 2), v_change, v_fee);
    update la_obra_v2.orders set payment_status = 'paid' where id = v_order;
  end if;
  if v_deliver then
    update la_obra_v2.orders set delivery_status = 'delivered', delivered_at = localtimestamp where id = v_order;
    perform la_obra_v2.inv_consume_order(v_order, u.id);
  end if;
  return la_obra_v2.ok(201, 'Venta registrada', jsonb_build_object('order', jsonb_build_object('id', v_order, 'total', v_total::float8,
    'change_amount', v_change::float8, 'commission_amount', v_fee::float8, 'payment_status', case when v_payment is not null then 'paid' else 'pending' end,
    'delivery_status', case when v_deliver then 'delivered' else 'pending' end)));
end $$;

create or replace function la_obra_v2.ep_sales__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_ps text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'payment_status')); v_ds text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'delivery_status'));
        v_os text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'order_status')); v_pm int; v_date date;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if v_ps is not null and v_ps not in ('pending','paid') then perform la_obra_v2.fail(422, 'Filtro payment_status inválido'); end if;
  if v_ds is not null and v_ds not in ('pending','delivered') then perform la_obra_v2.fail(422, 'Filtro delivery_status inválido'); end if;
  if v_os is not null and v_os not in ('open','confirmed','cancelled') then perform la_obra_v2.fail(422, 'Filtro order_status inválido'); end if;
  if la_obra_v2.qparam(q, 'payment_method_id') is not null then
    if not la_obra_v2.int_arg(q -> 'payment_method_id') then perform la_obra_v2.fail(422, 'Filtro payment_method_id inválido'); end if;
    v_pm := la_obra_v2.num(q -> 'payment_method_id');
  end if;
  if u.role <> 'employee' and la_obra_v2.qparam(q, 'date') is not null then
    v_date := la_obra_v2.dateval(q -> 'date', 'Filtro date inválido');
  end if;
  return la_obra_v2.ok(200, 'Ventas', jsonb_build_object('scope', case when u.role = 'employee' then 'today_own' else 'all' end, 'sales', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'user_id', o.user_id, 'user_name', us.name, 'delivery_mode', o.delivery_mode,
      'customer_name', o.customer_name, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at,
      'cancelled_at', o.cancelled_at, 'total', o.total::float8, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'payment_method_id', pm.id, 'payment_method', pm.name, 'paid_at', p.paid_at,
      'commission_amount', p.commission_amount::float8,
      'items', la_obra_v2.order_items_json(o.id)) order by o.created_at desc, o.id desc), '[]')
    from la_obra_v2.orders o join la_obra_v2.users us on us.id = o.user_id
    left join la_obra_v2.payments p on p.order_id = o.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where (v_ps is null or o.payment_status = v_ps) and (v_ds is null or o.delivery_status = v_ds) and (v_os is null or o.order_status = v_os)
      and (v_pm is null or p.payment_method_id = v_pm)
      and (u.role <> 'employee' or (o.user_id = u.id and o.created_at::date = current_date))
      and (v_date is null or o.created_at::date = v_date))));
end $$;

create or replace function la_obra_v2.ep_sales__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(q -> 'id') then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id');
  select o2.*, us.name as user_name, p.id as payment_id, p.amount, p.cash_received, p.change_amount, p.paid_at, p.commission_amount, pm.id as pm_id, pm.name as pm_name
    into o from la_obra_v2.orders o2 join la_obra_v2.users us on us.id = o2.user_id
    left join la_obra_v2.payments p on p.order_id = o2.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id where o2.id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Venta o pedido no encontrado'); end if;
  if u.role = 'employee' and (o.user_id <> u.id or o.created_at::date <> current_date) then perform la_obra_v2.fail(403, 'Solo puedes consultar tus pedidos del día'); end if;
  return la_obra_v2.ok(200, 'Venta', jsonb_build_object('sale', jsonb_build_object('id', o.id, 'user', jsonb_build_object('id', o.user_id, 'name', o.user_name),
    'order_status', o.order_status, 'payment_status', o.payment_status, 'delivery_status', o.delivery_status, 'total', o.total::float8,
    'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at,
    'items', la_obra_v2.order_items_json(o.id),
    'payment', case when o.payment_id is null then null else jsonb_build_object('id', o.payment_id, 'payment_method_id', o.pm_id, 'payment_method', o.pm_name,
      'amount', o.amount::float8, 'cash_received', o.cash_received::float8, 'change_amount', o.change_amount::float8, 'paid_at', o.paid_at,
      'commission_amount', o.commission_amount::float8) end)));
end $$;

create or replace function la_obra_v2.ep_sales__payment(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_o int; v_m int; o record; pm record; v_cash numeric; v_change numeric; v_fee numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(b -> 'order_id') or not la_obra_v2.int_arg(b -> 'payment_method_id') then perform la_obra_v2.fail(422, 'Datos de pago inválidos'); end if;
  v_o := la_obra_v2.num(b -> 'order_id'); v_m := la_obra_v2.num(b -> 'payment_method_id');
  select id, total, order_status, payment_status into o from la_obra_v2.orders where id = v_o;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'El pedido debe estar confirmado antes de registrar el pago'); end if;
  if o.payment_status = 'paid' then perform la_obra_v2.fail(409, 'El pedido ya está pagado'); end if;
  select id, name, status into pm from la_obra_v2.payment_methods where id = v_m;
  if pm.id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
  if pm.status <> 'active' then perform la_obra_v2.fail(409, 'El método de pago está inactivo'); end if;
  if lower(btrim(pm.name)) = 'efectivo' then
    if not la_obra_v2.is_num(b -> 'cash_received') or la_obra_v2.num(b -> 'cash_received') < o.total then
      perform la_obra_v2.fail(422, 'El efectivo recibido debe ser igual o mayor al total');
    end if;
    v_cash := la_obra_v2.num(b -> 'cash_received'); v_change := v_cash - o.total;
  end if;
  v_fee := la_obra_v2.payment_commission(v_m, o.total);
  insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount, commission_amount)
  values (v_o, v_m, o.total, round(v_cash, 2), round(v_change, 2), v_fee);
  update la_obra_v2.orders set payment_status = 'paid' where id = v_o;
  return la_obra_v2.ok(200, 'Pago registrado correctamente', jsonb_build_object('payment', jsonb_build_object('order_id', v_o, 'payment_method', pm.name,
    'amount', o.total::float8, 'cash_received', v_cash::float8, 'change_amount', v_change::float8, 'commission_amount', v_fee::float8)));
end $$;

create or replace function la_obra_v2.ep_sales__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth_long(t, true);
  if not la_obra_v2.int_arg(b -> 'order_id') then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(b -> 'order_id');
  select order_status, payment_status into o from la_obra_v2.orders where id = v_id;
  if o.order_status is null then perform la_obra_v2.fail(404, 'Venta no encontrada'); end if;
  if o.order_status = 'cancelled' then perform la_obra_v2.fail(409, 'La venta ya está cancelada'); end if;
  if o.payment_status <> 'paid' then perform la_obra_v2.fail(422, 'El pedido no tiene un pago registrado'); end if;
  update la_obra_v2.orders set order_status = 'cancelled', cancelled_at = localtimestamp where id = v_id;
  perform la_obra_v2.inv_reverse_order(v_id, u.id);
  return la_obra_v2.ok(200, 'Venta cancelada correctamente');
end $$;

-- >>>>>>>>>> 08_api_compras_gastos.sql
-- =====================================================================
-- La Obra v2 · 08 · purchases/* y expenses/*
-- =====================================================================
set check_function_bodies = off;

-- purchase($id) de service_helpers.php
create or replace function la_obra_v2.purchase_json(p_id int, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  if p_lock then perform 1 from la_obra_v2.purchases where id = p_id for update; end if;
  select to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name, 'items', (
      select coalesce(jsonb_agg(jsonb_build_object('id', pi.id, 'input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit,
        'quantity', pi.quantity, 'unit_cost', pi.unit_cost, 'subtotal', pi.subtotal, 'content_per_package', pi.content_per_package,
        'content_unit', pi.content_unit, 'total_base_quantity', pi.total_base_quantity) order by pi.id), '[]')
      from la_obra_v2.purchase_items pi join la_obra_v2.inputs i on i.id = pi.input_id where pi.purchase_id = p.id))
    into r from la_obra_v2.purchases p join la_obra_v2.users u on u.id = p.user_id join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
   where p.id = p_id;
  if r is null then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  return la_obra_v2.fix_dates(r);
end $$;

-- validItems(): devuelve {items:[...limpios], total}
create or replace function la_obra_v2.valid_items(p_items jsonb)
returns jsonb language plpgsql as $$
declare it jsonb; v_id int; seen int[] := '{}'; inp record; v_q numeric; v_content numeric; v_cj jsonb; v_cost numeric; v_sub numeric;
        v_total numeric := 0; clean jsonb := '[]';
begin
  if p_items is null or jsonb_typeof(p_items) not in ('array','object') or p_items in ('[]'::jsonb, '{}'::jsonb) then
    perform la_obra_v2.fail(422, 'Debes enviar al menos un insumo');
  end if;
  if jsonb_typeof(p_items) = 'object' then p_items := (select jsonb_agg(v) from jsonb_each(p_items) e(k, v)); end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it) <> 'object' then perform la_obra_v2.fail(422, 'Insumo inválido'); end if;
    v_id := la_obra_v2.positive_id(it -> 'input_id');
    if v_id = any(seen) then perform la_obra_v2.fail(422, 'No repitas el mismo insumo en una compra'); end if;
    seen := seen || v_id;
    select id, unit, package_quantity into inp from la_obra_v2.inputs where id = v_id and status = 'active';
    if inp.id is null then perform la_obra_v2.fail(404, 'Insumo no encontrado o inactivo'); end if;
    if not la_obra_v2.is_scalar(it -> 'quantity') or not la_obra_v2.is_num(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0
       or round(la_obra_v2.num(it -> 'quantity'), 3) <> la_obra_v2.num(it -> 'quantity') then
      perform la_obra_v2.fail(422, 'Cantidad inválida');
    end if;
    v_q := la_obra_v2.num(it -> 'quantity');
    v_cj := it -> 'content_per_package';
    if v_cj is null or jsonb_typeof(v_cj) = 'null' or (jsonb_typeof(v_cj) = 'string' and v_cj #>> '{}' = '') then
      v_content := inp.package_quantity;
    else
      if not la_obra_v2.is_num(v_cj) or la_obra_v2.num(v_cj) <= 0 then perform la_obra_v2.fail(422, 'Contenido de presentación inválido'); end if;
      v_content := la_obra_v2.num(v_cj);
    end if;
    v_cost := la_obra_v2.money(it -> 'unit_cost', false);
    v_sub := round(v_q * v_cost, 2);
    v_total := v_total + v_sub;
    clean := clean || jsonb_build_object('input_id', v_id, 'quantity', round(v_q, 3), 'unit_cost', v_cost, 'subtotal', v_sub,
      'content_per_package', round(v_content, 3), 'content_unit', inp.unit, 'total_base_quantity', round(v_q * v_content, 3));
  end loop;
  if v_total > 9999999999.99 then perform la_obra_v2.fail(422, 'Total excede el límite'); end if;
  return jsonb_build_object('items', clean, 'total', round(v_total, 2));
end $$;

-- validPurchase(): {purchase_date, supplier, payment_method_id, items, total}
create or replace function la_obra_v2.valid_purchase(d jsonb)
returns jsonb language plpgsql as $$
declare v_date date; v_sup jsonb; v_pm int; vi jsonb;
begin
  v_date := la_obra_v2.dateval(d -> 'purchase_date');
  v_sup := d -> 'supplier';
  if v_sup is not null and jsonb_typeof(v_sup) <> 'null' and (jsonb_typeof(v_sup) <> 'string' or char_length(v_sup #>> '{}') > 150) then
    perform la_obra_v2.fail(422, 'Proveedor inválido');
  end if;
  v_pm := la_obra_v2.positive_id(d -> 'payment_method_id');
  if not exists(select 1 from la_obra_v2.payment_methods where id = v_pm and status = 'active') then perform la_obra_v2.fail(404, 'Método de pago inexistente o inactivo'); end if;
  vi := la_obra_v2.valid_items(d -> 'items');
  return jsonb_build_object('purchase_date', v_date, 'supplier', case when jsonb_typeof(v_sup) = 'string' then v_sup else null end,
    'payment_method_id', v_pm, 'items', vi -> 'items', 'total', vi -> 'total');
end $$;

create or replace function la_obra_v2.valid_buyer(v jsonb)
returns text language plpgsql as $$
declare s text;
begin
  if v is null or jsonb_typeof(v) = 'null' then return null; end if;
  s := la_obra_v2.jstr(v);
  if s = '' then return null; end if;
  if char_length(s) > 100 then perform la_obra_v2.fail(422, 'Nombre del comprador demasiado largo'); end if;
  return s;
end $$;

create or replace function la_obra_v2.insert_purchase_items(p_id int, p_items jsonb)
returns void language sql as $$
  insert into la_obra_v2.purchase_items(purchase_id, input_id, quantity, unit_cost, subtotal, content_per_package, content_unit, total_base_quantity)
  select p_id, (i ->> 'input_id')::int, (i ->> 'quantity')::numeric, (i ->> 'unit_cost')::numeric, (i ->> 'subtotal')::numeric,
         (i ->> 'content_per_package')::numeric, i ->> 'content_unit', (i ->> 'total_base_quantity')::numeric
    from jsonb_array_elements(p_items) with ordinality x(i, n) order by n;
$$;

-- rememberPresentations(): guarda la presentación usada para prellenar la próxima compra
create or replace function la_obra_v2.remember_presentations(p_items jsonb)
returns void language plpgsql as $$
declare i jsonb; v_type text; v_c jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then return; end if;
  for i in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(i) <> 'object' then continue; end if;
    v_type := la_obra_v2.jstr(i -> 'package_type'); v_c := i -> 'content_per_package';
    if v_type = '' or char_length(v_type) > 40 or not la_obra_v2.is_int(i -> 'input_id') or la_obra_v2.num(i -> 'input_id') <= 0
       or not la_obra_v2.is_num(v_c) or la_obra_v2.num(v_c) <= 0 then continue; end if;
    update la_obra_v2.inputs set package_type = v_type, package_quantity = round(la_obra_v2.num(v_c), 3) where id = la_obra_v2.num(i -> 'input_id')::int;
  end loop;
end $$;

create or replace function la_obra_v2.ep_purchases__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_from date; v_to date;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  if la_obra_v2.qparam(q, 'date_from') is not null then v_from := la_obra_v2.dateval(q -> 'date_from'); end if;
  if la_obra_v2.qparam(q, 'date_to') is not null then v_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  return la_obra_v2.ok(200, 'Compras consultadas', jsonb_build_object('purchases', (
    select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('user_name', u.name, 'payment_method', pm.name) order by p.purchase_date desc, p.id desc), '[]')
    from la_obra_v2.purchases p join la_obra_v2.users u on u.id = p.user_id join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where (v_from is null or p.purchase_date >= v_from) and (v_to is null or p.purchase_date <= v_to))));
end $$;

create or replace function la_obra_v2.ep_purchases__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  return la_obra_v2.ok(200, 'Compra consultada', jsonb_build_object('purchase', la_obra_v2.purchase_json(la_obra_v2.positive_id(q -> 'id'))));
end $$;

create or replace function la_obra_v2.ep_purchases__prices(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'input_id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok(200, 'Historial de precios consultado', jsonb_build_object('prices', (
    select coalesce(jsonb_agg(jsonb_build_object('input_id', pi.input_id, 'input_name', i.name, 'unit', i.unit, 'purchase_id', p.id,
      'purchase_date', p.purchase_date, 'quantity', pi.quantity, 'unit_cost', pi.unit_cost) order by p.purchase_date desc, p.id desc, pi.id), '[]')
    from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id join la_obra_v2.inputs i on i.id = pi.input_id
    where pi.input_id = v_id)));
end $$;

create or replace function la_obra_v2.ep_purchases__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; vp jsonb; v_buyer text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  vp := la_obra_v2.valid_purchase(b);
  v_buyer := la_obra_v2.valid_buyer(b -> 'buyer');
  insert into la_obra_v2.purchases(purchase_date, supplier, buyer, payment_method_id, user_id, total)
  values ((vp ->> 'purchase_date')::date, vp ->> 'supplier', v_buyer, (vp ->> 'payment_method_id')::int, u.id, (vp ->> 'total')::numeric)
  returning id into v_id;
  perform la_obra_v2.insert_purchase_items(v_id, vp -> 'items');
  perform la_obra_v2.inv_sync_purchase(v_id, u.id);
  perform la_obra_v2.remember_presentations(b -> 'items');
  return la_obra_v2.ok(201, 'Compra registrada; el inventario se actualizó', jsonb_build_object('purchase', la_obra_v2.purchase_json(v_id)));
end $$;

create or replace function la_obra_v2.ep_purchases__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_old jsonb; merged jsonb; vp jsonb; v_buyer text; v_new jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  if not (b ?| array['purchase_date','supplier','buyer','payment_method_id','items']) then perform la_obra_v2.fail(422, 'No hay cambios para actualizar'); end if;
  v_old := la_obra_v2.purchase_json(v_id, true);
  merged := jsonb_build_object(
    'purchase_date', coalesce(nullif(b -> 'purchase_date', 'null'::jsonb), v_old -> 'purchase_date'),
    'supplier', case when b ? 'supplier' then b -> 'supplier' else v_old -> 'supplier' end,
    'payment_method_id', coalesce(nullif(b -> 'payment_method_id', 'null'::jsonb), v_old -> 'payment_method_id'),
    'items', coalesce(nullif(b -> 'items', 'null'::jsonb), (select coalesce(jsonb_agg(jsonb_build_object('input_id', i -> 'input_id', 'quantity', i -> 'quantity',
              'unit_cost', i -> 'unit_cost', 'content_per_package', i -> 'content_per_package') order by n), '[]')
              from jsonb_array_elements(v_old -> 'items') with ordinality x(i, n))));
  vp := la_obra_v2.valid_purchase(merged);
  v_buyer := case when b ? 'buyer' then la_obra_v2.valid_buyer(b -> 'buyer') else v_old ->> 'buyer' end;
  update la_obra_v2.purchases set purchase_date = (vp ->> 'purchase_date')::date, supplier = vp ->> 'supplier', buyer = v_buyer,
         payment_method_id = (vp ->> 'payment_method_id')::int, total = (vp ->> 'total')::numeric, updated_at = localtimestamp where id = v_id;
  delete from la_obra_v2.purchase_items where purchase_id = v_id;
  perform la_obra_v2.insert_purchase_items(v_id, vp -> 'items');
  perform la_obra_v2.inv_sync_purchase(v_id, u.id);
  if b ? 'items' then perform la_obra_v2.remember_presentations(b -> 'items'); end if;
  v_new := la_obra_v2.purchase_json(v_id);
  insert into la_obra_v2.purchase_history(purchase_id, changed_by, previous_data, new_data, change_reason)
  values (v_id, u.id, v_old::text, v_new::text, case when b ? 'change_reason' and jsonb_typeof(b -> 'change_reason') <> 'null' then la_obra_v2.jstr(b -> 'change_reason') end);
  return la_obra_v2.ok(200, 'Compra actualizada; el inventario se recalculó', jsonb_build_object('purchase', v_new));
end $$;

create or replace function la_obra_v2.ep_purchases__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_ticket text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select ticket_path into v_ticket from la_obra_v2.purchases where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  begin
    delete from la_obra_v2.inventory_movements where reference_type = 'purchase' and reference_id = v_id;
    delete from la_obra_v2.purchase_history where purchase_id = v_id;
    delete from la_obra_v2.purchase_items where purchase_id = v_id;
    delete from la_obra_v2.purchases where id = v_id;
  exception when foreign_key_violation then
    perform la_obra_v2.fail(409, 'La compra tiene registros relacionados y no puede eliminarse');
  end;
  perform la_obra_v2.delete_file(v_ticket, 'tickets');
  return la_obra_v2.ok(200, 'Compra eliminada correctamente');
end $$;

create or replace function la_obra_v2.ep_purchases__upload_ticket(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text; v_path text;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(b -> 'id');
  select ticket_path into v_old from la_obra_v2.purchases where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  v_path := la_obra_v2.save_image(b -> 'image', 'tickets', 'ticket_' || v_id);
  update la_obra_v2.purchases set ticket_path = v_path where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'tickets');
  return la_obra_v2.ok(200, 'Ticket guardado', jsonb_build_object('ticket_path', v_path));
end $$;

create or replace function la_obra_v2.ep_purchases__delete_ticket(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_old text;
begin
  perform la_obra_v2.method(m, 'DELETE');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(la_obra_v2.body(b) -> 'id');
  select ticket_path into v_old from la_obra_v2.purchases where id = v_id;
  if not found then perform la_obra_v2.fail(404, 'Compra no encontrada'); end if;
  update la_obra_v2.purchases set ticket_path = null where id = v_id;
  perform la_obra_v2.delete_file(v_old, 'tickets');
  return la_obra_v2.ok(200, 'Ticket eliminado');
end $$;

-- ---------- Gastos ----------
create or replace function la_obra_v2.expense_json(p_id int, p_lock boolean default false)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  if p_lock then perform 1 from la_obra_v2.expenses where id = p_id for update; end if;
  select to_jsonb(e) || jsonb_build_object('user_name', u.name) into r
    from la_obra_v2.expenses e join la_obra_v2.users u on u.id = e.user_id where e.id = p_id;
  if r is null then perform la_obra_v2.fail(404, 'Gasto no encontrado'); end if;
  return la_obra_v2.fix_dates(r);
end $$;

create or replace function la_obra_v2.expense_access(e jsonb, u la_obra_v2.users)
returns void language plpgsql as $$
begin
  if u.role <> 'admin' and (e ->> 'user_id')::int <> u.id then perform la_obra_v2.fail(403, 'No puedes consultar o modificar gastos de otra persona'); end if;
end $$;

create or replace function la_obra_v2.ep_expenses__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_uid int; v_from date; v_to date; v_status text;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  if u.role <> 'employee' then
    if la_obra_v2.qparam(q, 'user_id') is not null then v_uid := la_obra_v2.positive_id(q -> 'user_id'); end if;
    if la_obra_v2.qparam(q, 'date_from') is not null then v_from := la_obra_v2.dateval(q -> 'date_from'); end if;
    if la_obra_v2.qparam(q, 'date_to') is not null then v_to := la_obra_v2.dateval(q -> 'date_to'); end if;
  end if;
  v_status := la_obra_v2.jtext(la_obra_v2.qparam(q, 'status'));
  if v_status is not null and v_status not in ('active','cancelled') then perform la_obra_v2.fail(422, 'Estado inválido'); end if;
  return la_obra_v2.ok(200, 'Gastos consultados', jsonb_build_object('scope', case when u.role = 'admin' then 'all' else 'today_own' end, 'expenses', (
    select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('user_name', us.name) order by e.created_at desc, e.id desc), '[]')
    from la_obra_v2.expenses e join la_obra_v2.users us on us.id = e.user_id
    where (u.role <> 'employee' or (e.user_id = u.id and e.created_at::date = current_date))
      and (v_uid is null or e.user_id = v_uid) and (v_from is null or e.created_at::date >= v_from) and (v_to is null or e.created_at::date <= v_to)
      and (v_status is null or e.status = v_status))));
end $$;

create or replace function la_obra_v2.ep_expenses__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; e jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  v_id := la_obra_v2.positive_id(q -> 'id');
  e := la_obra_v2.expense_json(v_id);
  perform la_obra_v2.expense_access(e, u);
  if u.role = 'employee' and substr(e ->> 'created_at', 1, 10) <> to_char(current_date, 'YYYY-MM-DD') then
    perform la_obra_v2.fail(403, 'El empleado solo consulta gastos de su jornada actual');
  end if;
  if u.role = 'admin' then
    e := e || jsonb_build_object('history', (select coalesce(jsonb_agg(to_jsonb(h) order by h.changed_at desc, h.id desc), '[]') from la_obra_v2.expense_history h where h.expense_id = v_id));
  end if;
  return la_obra_v2.ok(200, 'Gasto consultado', jsonb_build_object('expense', e));
end $$;

create or replace function la_obra_v2.ep_expenses__history(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'id');
  perform la_obra_v2.expense_json(v_id);
  return la_obra_v2.ok(200, 'Historial consultado', jsonb_build_object('history', (
    select coalesce(jsonb_agg(to_jsonb(h) || jsonb_build_object('changed_by_name', u.name) order by h.changed_at desc, h.id desc), '[]')
    from la_obra_v2.expense_history h join la_obra_v2.users u on u.id = h.changed_by where h.expense_id = v_id)));
end $$;

create or replace function la_obra_v2.ep_expenses__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_amount numeric; v_reason text; v_id int;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_amount := la_obra_v2.money(b -> 'amount');
  v_reason := la_obra_v2.jstr(b -> 'reason');
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo inválido'); end if;
  insert into la_obra_v2.expenses(amount, reason, user_id, status) values (v_amount, v_reason, u.id, 'active') returning id into v_id;
  return la_obra_v2.ok(201, 'Gasto registrado correctamente', jsonb_build_object('expense', la_obra_v2.expense_json(v_id)));
end $$;

create or replace function la_obra_v2.ep_expenses__update(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_why text; v_old jsonb; v_amount numeric; v_reason text; v_new jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_why := la_obra_v2.jstr(b -> 'change_reason');
  if v_why = '' or char_length(v_why) > 255 then perform la_obra_v2.fail(422, 'El motivo de corrección es obligatorio'); end if;
  if not (b ? 'amount') and not (b ? 'reason') then perform la_obra_v2.fail(422, 'Debes enviar monto o motivo del gasto'); end if;
  v_old := la_obra_v2.expense_json(v_id, true);
  perform la_obra_v2.expense_access(v_old, u);
  if v_old ->> 'status' <> 'active' then perform la_obra_v2.fail(409, 'El gasto ya está cancelado'); end if;
  v_amount := case when b ? 'amount' then la_obra_v2.money(b -> 'amount') else (v_old ->> 'amount')::numeric end;
  v_reason := case when b ? 'reason' then la_obra_v2.jstr(b -> 'reason') else v_old ->> 'reason' end;
  if v_reason = '' or char_length(v_reason) > 255 then perform la_obra_v2.fail(422, 'Motivo del gasto inválido'); end if;
  update la_obra_v2.expenses set amount = v_amount, reason = v_reason, updated_at = localtimestamp where id = v_id;
  v_new := la_obra_v2.expense_json(v_id);
  insert into la_obra_v2.expense_history(expense_id, action, previous_data, new_data, change_reason, changed_by)
  values (v_id, 'updated', v_old::text, v_new::text, v_why, u.id);
  return la_obra_v2.ok(200, 'Gasto actualizado correctamente', jsonb_build_object('expense', v_new));
end $$;

create or replace function la_obra_v2.ep_expenses__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_why text; v_old jsonb; v_new jsonb;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'id');
  v_why := la_obra_v2.jstr(b -> 'cancellation_reason');
  if v_why = '' or char_length(v_why) > 255 then perform la_obra_v2.fail(422, 'Motivo de cancelación obligatorio'); end if;
  v_old := la_obra_v2.expense_json(v_id, true);
  perform la_obra_v2.expense_access(v_old, u);
  if v_old ->> 'status' <> 'active' then perform la_obra_v2.fail(409, 'El gasto ya está cancelado'); end if;
  update la_obra_v2.expenses set status = 'cancelled', cancelled_by = u.id, cancelled_at = localtimestamp, cancellation_reason = v_why, updated_at = localtimestamp where id = v_id;
  v_new := la_obra_v2.expense_json(v_id);
  insert into la_obra_v2.expense_history(expense_id, action, previous_data, new_data, change_reason, changed_by)
  values (v_id, 'cancelled', v_old::text, v_new::text, v_why, u.id);
  return la_obra_v2.ok(200, 'Gasto cancelado correctamente', jsonb_build_object('expense', v_new));
end $$;

-- >>>>>>>>>> 09_api_inventario_costos.sql
-- =====================================================================
-- La Obra v2 · 09 · inventory/*, costs/*, dashboard/*
-- =====================================================================
set check_function_bodies = off;

create or replace function la_obra_v2.ep_inventory__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_items jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  v_items := la_obra_v2.inv_list();
  return la_obra_v2.ok(200, 'Inventario consultado', jsonb_build_object('inventory', v_items, 'summary', jsonb_build_object(
    'total_value', (select round(coalesce(sum((x ->> 'stock_value')::numeric), 0), 2) from jsonb_array_elements(v_items) x),
    'low', (select count(*) from jsonb_array_elements(v_items) x where x ->> 'status' = 'active' and x ->> 'level' = 'low'),
    'out', (select count(*) from jsonb_array_elements(v_items) x where x ->> 'status' = 'active' and x ->> 'level' = 'out'))));
end $$;

create or replace function la_obra_v2.ep_inventory__movements(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_input jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t);
  v_id := la_obra_v2.positive_id(q -> 'input_id');
  select jsonb_build_object('id', id, 'name', name, 'unit', unit) into v_input from la_obra_v2.inputs where id = v_id;
  if v_input is null then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  return la_obra_v2.ok(200, 'Movimientos consultados', jsonb_build_object('input', v_input, 'stock', la_obra_v2.inv_stock(v_id)::float8, 'movements', (
    select coalesce(jsonb_agg(x order by rn), '[]') from (
      select jsonb_build_object('id', mv.id, 'movement_type', mv.movement_type, 'quantity', mv.quantity::float8, 'unit_cost', mv.unit_cost::float8,
        'reference_type', mv.reference_type, 'reference_id', mv.reference_id, 'note', mv.note, 'created_at', mv.created_at, 'user_name', u.name) x,
        row_number() over (order by mv.created_at desc, mv.id desc) rn
      from la_obra_v2.inventory_movements mv left join la_obra_v2.users u on u.id = mv.user_id where mv.input_id = v_id
      order by mv.created_at desc, mv.id desc limit 200) s)));
end $$;

create or replace function la_obra_v2.ep_inventory__adjust(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; v_counted numeric; v_note text; v_before numeric; v_diff numeric;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'input_id');
  if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado'); end if;
  if not la_obra_v2.is_num(b -> 'counted_quantity') or la_obra_v2.num(b -> 'counted_quantity') < 0 then perform la_obra_v2.fail(422, 'Indica la cantidad contada'); end if;
  v_counted := la_obra_v2.num(b -> 'counted_quantity');
  v_note := la_obra_v2.jstr(b -> 'note');
  if char_length(v_note) > 255 then perform la_obra_v2.fail(422, 'La nota es demasiado larga'); end if;
  v_before := la_obra_v2.inv_stock(v_id);
  v_diff := round(v_counted - v_before, 3);
  if abs(v_diff) < 0.0005 then
    return la_obra_v2.ok(200, 'Sin diferencias: el inventario ya coincide', jsonb_build_object('stock', v_before::float8, 'difference', 0));
  end if;
  perform la_obra_v2.inv_record(v_id, 'adjustment', v_diff, la_obra_v2.input_cost(v_id), 'adjustment', null, coalesce(nullif(v_note, ''), 'Conteo físico'), u.id);
  return la_obra_v2.ok(200, 'Inventario ajustado', jsonb_build_object('stock', la_obra_v2.inv_stock(v_id)::float8, 'difference', v_diff::float8));
end $$;

-- inventory/count.php · POST {items: [{input_id, counted_quantity, unit_id?}], note?}
-- Captura de existencias: registra lo que hay HOY de varios insumos a la vez, aunque no tengan
-- compras ni costo registrado. Por cada insumo con diferencia se guarda un "Ajuste por conteo";
-- no toca compras, recetas ni costos. Los insumos que se dejan vacíos no se modifican.
create or replace function la_obra_v2.ep_inventory__count(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; it jsonb; v_id int; v_counted numeric; v_note text; v_before numeric; v_diff numeric; v_seen int[] := '{}';
        v_changed int := 0; v_same int := 0; un la_obra_v2.input_units;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t, true);
  b := la_obra_v2.body(b);
  if jsonb_typeof(b -> 'items') is distinct from 'array' or jsonb_array_length(b -> 'items') = 0 then
    perform la_obra_v2.fail(422, 'Escribe la existencia de al menos un insumo');
  end if;
  v_note := la_obra_v2.jstr(b -> 'note');
  if char_length(v_note) > 255 then perform la_obra_v2.fail(422, 'La nota es demasiado larga'); end if;
  for it in select * from jsonb_array_elements(b -> 'items') loop
    v_id := la_obra_v2.positive_id(it -> 'input_id', 'Insumo inválido');
    if v_id = any(v_seen) then perform la_obra_v2.fail(422, 'Hay un insumo repetido en la captura'); end if;
    v_seen := v_seen || v_id;
    if not exists(select 1 from la_obra_v2.inputs where id = v_id) then perform la_obra_v2.fail(404, 'Insumo no encontrado: ' || v_id); end if;
    if not la_obra_v2.is_num(it -> 'counted_quantity') or la_obra_v2.num(it -> 'counted_quantity') < 0 then
      perform la_obra_v2.fail(422, 'Las existencias no pueden ser negativas');
    end if;
    v_counted := la_obra_v2.num(it -> 'counted_quantity');
    if la_obra_v2.not_empty(it -> 'unit_id') then
      select * into un from la_obra_v2.input_units where id = la_obra_v2.positive_id(it -> 'unit_id', 'Medida inválida');
      if un.id is null or un.input_id <> v_id then perform la_obra_v2.fail(422, 'La medida elegida no corresponde al insumo'); end if;
      v_counted := v_counted * un.base_amount / un.unit_amount;
    end if;
    v_before := la_obra_v2.inv_stock(v_id);
    v_diff := round(v_counted - v_before, 3);
    if abs(v_diff) < 0.0005 then v_same := v_same + 1; continue; end if;
    perform la_obra_v2.inv_record(v_id, 'adjustment', v_diff, la_obra_v2.input_cost(v_id), 'adjustment', null,
      coalesce(nullif(v_note, ''), 'Captura de existencias'), u.id);
    v_changed := v_changed + 1;
  end loop;
  return la_obra_v2.ok(200, case when v_changed = 0 then 'Sin cambios: las existencias ya coincidían'
                                 else 'Existencias guardadas: ' || v_changed || ' insumo(s) actualizado(s)' end,
    jsonb_build_object('updated', v_changed, 'unchanged', v_same));
end $$;

create or replace function la_obra_v2.cost_mode(q jsonb)
returns text language plpgsql as $$
declare v text := coalesce(la_obra_v2.jtext(q -> 'delivery_mode'), 'local');
begin
  if v not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  return v;
end $$;

create or replace function la_obra_v2.ep_costs__product(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_id int; v_mode text; r jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_id := la_obra_v2.positive_id(q -> 'product_id');
  v_mode := la_obra_v2.cost_mode(q);
  r := la_obra_v2.product_cost(v_id, v_mode);
  if r is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
  return la_obra_v2.ok(200, 'Costo consultado', jsonb_build_object('cost', r, 'product_cost', r));
end $$;

create or replace function la_obra_v2.ep_costs__detail(m text, q jsonb, b jsonb, t text)
returns jsonb language sql as $$ select la_obra_v2.ep_costs__product(m, q, b, t); $$;

create or replace function la_obra_v2.ep_costs__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_mode text; v_list jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_mode := la_obra_v2.cost_mode(q);
  select coalesce(jsonb_agg(c || jsonb_build_object('category_name', s.category_name, 'image_path', s.image_path,
           'has_recipe', jsonb_array_length(c -> 'components') > 0) order by s.category_name, s.name, s.id), '[]')
    into v_list
    from (select p.id, p.name, p.image_path, cat.name as category_name from la_obra_v2.products p join la_obra_v2.categories cat on cat.id = p.category_id where p.status = 'active') s
    cross join lateral (select la_obra_v2.product_cost(s.id, v_mode) c) x;
  return la_obra_v2.ok(200, 'Costos consultados', jsonb_build_object('products', v_list, 'summary', jsonb_build_object(
    'products', jsonb_array_length(v_list),
    'without_recipe', (select count(*) from jsonb_array_elements(v_list) x where not (x ->> 'has_recipe')::boolean),
    'missing_prices', (select count(*) from jsonb_array_elements(v_list) x where (x ->> 'has_recipe')::boolean and not (x ->> 'complete')::boolean),
    'average_margin', (select round(avg((x ->> 'gross_margin')::numeric), 2) from jsonb_array_elements(v_list) x where jsonb_typeof(x -> 'gross_margin') = 'number'))));
end $$;

create or replace function la_obra_v2.ep_dashboard__summary(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_admin boolean; v_today record; v_yesterday numeric; v_pending record; v_top jsonb; v_data jsonb; v_stock jsonb; v_month date := date_trunc('month', current_date)::date;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  v_admin := u.role = 'admin';
  select count(*) as orders, coalesce(sum(o.total), 0) as sales,
         coalesce(sum((select sum(oi.quantity * coalesce(oi.standard_unit_cost, 0)) from la_obra_v2.order_items oi where oi.order_id = o.id)), 0) as cost
    into v_today from la_obra_v2.orders o
   where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date = current_date and (v_admin or o.user_id = u.id);
  select coalesce(sum(o.total), 0) into v_yesterday from la_obra_v2.orders o
   where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date = current_date - 1 and (v_admin or o.user_id = u.id);
  select count(*) filter (where payment_status = 'pending') as to_charge, count(*) filter (where delivery_status = 'pending') as to_deliver
    into v_pending from la_obra_v2.orders where order_status = 'confirmed' and (payment_status = 'pending' or delivery_status = 'pending');
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'quantity', quantity, 'revenue', revenue::float8) order by quantity desc, name), '[]') into v_top from (
    select p.name, sum(oi.quantity)::int as quantity, sum(oi.subtotal) as revenue
      from la_obra_v2.order_items oi join la_obra_v2.orders o on o.id = oi.order_id join la_obra_v2.products p on p.id = oi.product_id
     where o.order_status = 'confirmed' and o.created_at::date = current_date and (v_admin or o.user_id = u.id)
     group by p.id, p.name order by quantity desc, p.name limit 5) s;
  v_data := jsonb_build_object(
    'today', jsonb_build_object('sales', round(v_today.sales, 2)::float8, 'orders', v_today.orders,
      'average_ticket', case when v_today.orders > 0 then round(v_today.sales / v_today.orders, 2)::float8 else 0 end,
      'yesterday_sales', round(v_yesterday, 2)::float8),
    'pending', jsonb_build_object('to_charge', v_pending.to_charge, 'to_deliver', v_pending.to_deliver),
    'top_products', v_top);
  select coalesce(jsonb_agg(x order by x ->> 'level', x ->> 'name'), '[]') into v_stock
    from jsonb_array_elements(la_obra_v2.inv_list()) x where x ->> 'status' = 'active' and x ->> 'level' <> 'ok';
  v_data := v_data || jsonb_build_object(
    'stock_alerts', (select coalesce(jsonb_agg(jsonb_build_object('id', x -> 'id', 'name', x -> 'name', 'stock', x -> 'stock', 'unit', x -> 'unit',
                       'min_stock', x -> 'min_stock', 'level', x -> 'level') order by n), '[]')
                       from jsonb_array_elements(v_stock) with ordinality a(x, n) where n <= 6),
    'stock_alerts_total', jsonb_array_length(v_stock));
  if v_admin then
    v_data := jsonb_set(v_data, '{today,gross_profit}', to_jsonb(round(v_today.sales - v_today.cost, 2)::float8));
    v_data := v_data || jsonb_build_object('month', jsonb_build_object(
      'purchases', (select coalesce(sum(total), 0)::float8 from la_obra_v2.purchases where purchase_date >= v_month),
      'expenses', (select coalesce(sum(amount), 0)::float8 from la_obra_v2.expenses where status = 'active' and created_at::date >= v_month),
      'sales', (select coalesce(sum(total), 0)::float8 from la_obra_v2.orders where order_status = 'confirmed' and payment_status = 'paid' and created_at::date >= v_month)));
  end if;
  return la_obra_v2.ok(200, 'Resumen consultado', jsonb_build_object('summary', v_data));
end $$;

-- >>>>>>>>>> 09b_api_reportes.sql
-- =====================================================================
-- La Obra v2 · 09b · reports/*
-- =====================================================================
set check_function_bodies = off;

-- Sesión de los reportes (sus propios mensajes en la v1)
create or replace function la_obra_v2.report_auth(p_token text)
returns void language plpgsql as $$
declare u record;
begin
  if p_token is null or btrim(p_token) = '' or btrim(p_token) ~ '\s' then perform la_obra_v2.fail(401, 'Token de autenticación requerido'); end if;
  select us.status, us.role, s.expires_at into u from la_obra_v2.sessions s join la_obra_v2.users us on us.id = s.user_id
   where s.token_hash = la_obra_v2.sha256(btrim(p_token)) limit 1;
  if u.status is null or u.expires_at <= localtimestamp then perform la_obra_v2.fail(401, 'La sesión es inválida o ha expirado'); end if;
  if u.status <> 'active' or u.role is distinct from 'admin' then perform la_obra_v2.fail(403, 'Los reportes están disponibles para el administrador'); end if;
end $$;

-- Rango ?from=&to= de los reportes por fecha de pago
create or replace function la_obra_v2.report_range(q jsonb, out o_from date, out o_to date)
language plpgsql as $$
declare f text; t2 text;
begin
  f := coalesce(la_obra_v2.jtext(q -> 'from'), to_char(date_trunc('month', current_date), 'YYYY-MM-DD'));
  t2 := coalesce(la_obra_v2.jtext(q -> 'to'), to_char(current_date, 'YYYY-MM-DD'));
  if f !~ '^\d{4}-\d{2}-\d{2}$' or t2 !~ '^\d{4}-\d{2}-\d{2}$' then perform la_obra_v2.fail(422, 'Utiliza fechas válidas con formato AAAA-MM-DD'); end if;
  begin o_from := f::date; o_to := t2::date;
  exception when others then perform la_obra_v2.fail(422, 'Utiliza fechas válidas con formato AAAA-MM-DD'); end;
  if to_char(o_from, 'YYYY-MM-DD') <> f or to_char(o_to, 'YYYY-MM-DD') <> t2 then perform la_obra_v2.fail(422, 'Utiliza fechas válidas con formato AAAA-MM-DD'); end if;
  if o_from > o_to then perform la_obra_v2.fail(422, 'La fecha inicial no puede ser posterior a la final'); end if;
  if o_to - o_from > 365 then perform la_obra_v2.fail(422, 'Selecciona un rango de hasta 366 días'); end if;
end $$;

create or replace function la_obra_v2.ep_reports__daily(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('date', d, 'amount', amount::float8, 'orders', orders::float8) order by d), '[]') from (
      select pay.paid_at::date d, sum(pay.amount) amount, count(*) orders
        from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by pay.paid_at::date) s)));
end $$;

create or replace function la_obra_v2.ep_reports__payment_methods(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('method_id', id::float8, 'name', name, 'amount', amount::float8, 'orders', orders::float8,
             'commission', commission::float8) order by amount desc, id), '[]') from (
      select pm.id, pm.name, sum(pay.amount) amount, count(*) orders, coalesce(sum(pay.commission_amount), 0) commission
        from la_obra_v2.payments pay join la_obra_v2.orders o on o.id = pay.order_id join la_obra_v2.payment_methods pm on pm.id = pay.payment_method_id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by pm.id, pm.name) s)));
end $$;

create or replace function la_obra_v2.ep_reports__products(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('product_id', id::float8, 'name', name, 'quantity', quantity::float8, 'amount', amount::float8) order by quantity desc, id), '[]') from (
      select p.id, p.name, sum(oi.quantity) quantity, sum(oi.subtotal) amount
        from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id join la_obra_v2.orders o on o.id = oi.order_id
        join la_obra_v2.payments pay on pay.order_id = o.id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by p.id, p.name) s)));
end $$;

create or replace function la_obra_v2.ep_reports__categories(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.report_auth(t);
  select * into r from la_obra_v2.report_range(q);
  return la_obra_v2.ok(200, 'Reporte', jsonb_build_object('from', r.o_from, 'to', r.o_to, 'data', (
    select coalesce(jsonb_agg(jsonb_build_object('date', d, 'category_id', id::float8, 'category', name, 'amount', amount::float8) order by d, id), '[]') from (
      select pay.paid_at::date d, c.id, c.name, sum(oi.subtotal) amount
        from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id join la_obra_v2.categories c on c.id = p.category_id
        join la_obra_v2.orders o on o.id = oi.order_id join la_obra_v2.payments pay on pay.order_id = o.id
       where o.order_status = 'confirmed' and o.payment_status = 'paid' and pay.paid_at >= r.o_from and pay.paid_at < r.o_to + 1
       group by pay.paid_at::date, c.id, c.name) s)));
end $$;

-- reports/summary.php: reporte y corte de caja del periodo (por fecha del pedido)
create or replace function la_obra_v2.ep_reports__summary(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_from date; v_to date; tt record; cs record; v_purch numeric; v_exp numeric; v_waste numeric; canc record; v_sales numeric; v_cos numeric;
        v_methods jsonb; v_cash_sales numeric := 0; v_cash_purch numeric; v_fees numeric;
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth(t, true);
  v_from := la_obra_v2.dateval(coalesce(q -> 'from', to_jsonb(to_char(current_date, 'YYYY-MM-DD'))));
  v_to := la_obra_v2.dateval(coalesce(q -> 'to', to_jsonb(to_char(current_date, 'YYYY-MM-DD'))));
  if v_from > v_to then perform la_obra_v2.fail(422, 'La fecha inicial no puede ser mayor que la final'); end if;
  if v_to - v_from > 366 then perform la_obra_v2.fail(422, 'El periodo máximo es de un año'); end if;

  create temporary table if not exists lo_paid(id int primary key) on commit drop;
  truncate lo_paid;
  insert into lo_paid select o.id from la_obra_v2.orders o
   where o.order_status = 'confirmed' and o.payment_status = 'paid' and o.created_at::date between v_from and v_to;

  select count(*) orders, coalesce(sum(o.total), 0) sales into tt from la_obra_v2.orders o join lo_paid p on p.id = o.id;
  select coalesce(sum(oi.quantity * oi.standard_unit_cost), 0) cost, count(*) filter (where oi.standard_unit_cost is null) no_cost
    into cs from la_obra_v2.order_items oi join lo_paid p on p.id = oi.order_id;
  select coalesce(sum(total), 0) into v_purch from la_obra_v2.purchases where purchase_date between v_from and v_to;
  select coalesce(sum(amount), 0) into v_exp from la_obra_v2.expenses where status = 'active' and created_at::date between v_from and v_to;
  select coalesce(sum(estimated_total_cost), 0) into v_waste from la_obra_v2.waste_records where waste_date between v_from and v_to;
  select count(*) n, coalesce(sum(total), 0) tot into canc from la_obra_v2.orders o where o.order_status = 'cancelled' and o.created_at::date between v_from and v_to;
  v_sales := tt.sales; v_cos := cs.cost;

  select coalesce(sum(pay.commission_amount), 0) into v_fees from la_obra_v2.payments pay join lo_paid p on p.id = pay.order_id;
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'orders', orders::float8, 'amount', amount::float8, 'commission', commission::float8) order by amount desc, id), '[]') into v_methods from (
    select pm.id, pm.name, count(*) orders, sum(pay.amount) amount, coalesce(sum(pay.commission_amount), 0) commission
      from la_obra_v2.payments pay join lo_paid p on p.id = pay.order_id join la_obra_v2.payment_methods pm on pm.id = pay.payment_method_id
     group by pm.id, pm.name) s;
  select coalesce((select (x ->> 'amount')::numeric from jsonb_array_elements(v_methods) x where lower(btrim(x ->> 'name')) = 'efectivo' limit 1), 0) into v_cash_sales;
  select coalesce(sum(p.total), 0) into v_cash_purch from la_obra_v2.purchases p join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
   where lower(pm.name) = 'efectivo' and p.purchase_date between v_from and v_to;

  return la_obra_v2.ok(200, 'Reporte generado', jsonb_build_object('report', jsonb_build_object(
    'from', v_from, 'to', v_to,
    'totals', jsonb_build_object('sales', round(v_sales, 2)::float8, 'orders', tt.orders,
      'average_ticket', case when tt.orders > 0 then round(v_sales / tt.orders, 2)::float8 else 0 end,
      'cost_of_sales', round(v_cos, 2)::float8, 'gross_profit', round(v_sales - v_cos, 2)::float8,
      'gross_margin', case when v_sales > 0 then round((v_sales - v_cos) / v_sales * 100, 1)::float8 else null end,
      'lines_without_cost', cs.no_cost, 'purchases', round(v_purch, 2)::float8, 'expenses', round(v_exp, 2)::float8,
      'waste', round(v_waste, 2)::float8, 'cancelled_orders', canc.n, 'cancelled_amount', round(canc.tot, 2)::float8,
      -- Comisiones de la terminal (tarjeta): lo que se queda el banco de las ventas cobradas
      'card_fees', round(v_fees, 2)::float8, 'net_sales', round(v_sales - v_fees, 2)::float8,
      'profit_after_fees', round(v_sales - v_cos - v_fees, 2)::float8),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'orders', orders::float8, 'sales', sales::float8) order by day), '[]') from (
        select o.created_at::date as day, count(*) orders, sum(o.total) sales from la_obra_v2.orders o join lo_paid p on p.id = o.id group by o.created_at::date) s),
    'products', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'quantity', quantity::float8, 'revenue', revenue::float8, 'cost', cost::float8) order by revenue desc, id), '[]') from (
        select pr.id, pr.name, sum(oi.quantity) quantity, sum(oi.subtotal) revenue, sum(oi.quantity * coalesce(oi.standard_unit_cost, 0)) cost
          from la_obra_v2.order_items oi join lo_paid p on p.id = oi.order_id join la_obra_v2.products pr on pr.id = oi.product_id group by pr.id, pr.name) s),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'quantity', quantity::float8, 'revenue', revenue::float8) order by revenue desc, id), '[]') from (
        select c.id, c.name, sum(oi.quantity) quantity, sum(oi.subtotal) revenue
          from la_obra_v2.order_items oi join lo_paid p on p.id = oi.order_id join la_obra_v2.products pr on pr.id = oi.product_id
          join la_obra_v2.categories c on c.id = pr.category_id group by c.id, c.name) s),
    'payment_methods', v_methods,
    'cash_cut', jsonb_build_object('cash_sales', round(v_cash_sales, 2)::float8, 'cash_purchases', round(v_cash_purch, 2)::float8,
      'expenses', round(v_exp, 2)::float8, 'expected_cash', round(v_cash_sales - v_cash_purch - v_exp, 2)::float8))));
end $$;

-- >>>>>>>>>> 09c_api_mermas_facturas_asistencia.sql
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

-- >>>>>>>>>> 09d_respaldo.sql
-- =====================================================================
-- La Obra v2 · 09d · Respaldo y restauración (backup/export, backup/import)
-- El plan gratuito de Supabase no da respaldos descargables: el administrador
-- descarga un JSON con todo desde la pantalla "Servidor" y lo puede restaurar.
-- =====================================================================
set check_function_bodies = off;

-- Tablas en orden de dependencias (para insertar; se borran al revés)
create or replace function la_obra_v2.backup_tables()
returns text[] language sql immutable as $$
  select array['users','sessions','categories','payment_methods','inputs','input_units','products','preparations','preparation_inputs',
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

  -- Al restaurar no se aplica el límite de usuarios del plan (se recupera lo que había)
  perform set_config('la_obra_v2.skip_user_limit', 'on', true);
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
  -- Respaldos anteriores a la comisión de terminal: Tarjeta vuelve a quedar con 4 %
  update la_obra_v2.payment_methods set commission_percent = 4.00 where commission_percent is null and lower(name) like '%tarjeta%';
  if jsonb_typeof(bk -> 'files') = 'array' and jsonb_array_length(bk -> 'files') > 0 then
    delete from la_obra_v2.files;
    insert into la_obra_v2.files(path, mime, data, created_at)
    select f ->> 'path', f ->> 'mime', decode(f ->> 'data', 'base64'), coalesce((f ->> 'created_at')::timestamp, localtimestamp)
      from jsonb_array_elements(bk -> 'files') f;
  end if;
  return la_obra_v2.ok(200, 'Respaldo restaurado: ' || v_total || ' registros. Vuelve a iniciar sesión.');
end $$;

-- >>>>>>>>>> 11_caja_fondo_y_corte.sql
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

-- >>>>>>>>>> 12_editar_pedidos.sql
-- =====================================================================
-- La Obra v2 · 12 · Editar pedidos que aún no se entregan
-- Se puede correr solo (Supabase → SQL Editor → New query → pegar → Run) sobre una base ya
-- instalada. No borra ni cambia datos existentes: agrega 2 columnas a orders, 1 tabla nueva
-- (order_edits) y actualiza/crea rutas de la API.
--
--   orders/edit.php   POST { order_id, items: [{product_id, quantity}], delivery_mode?, customer_name?,
--                            payment?: null | { payment_method_id, cash_received?, difference_received? }, reason? }
--                     · Solo pedidos confirmados y NO entregados (lo entregado ya descontó inventario).
--                     · Los productos que ya estaban conservan el precio con el que se vendieron;
--                       los nuevos entran con el precio actual.
--                     · payment = null  → el pedido queda "por cobrar" (se quita el cobro si había).
--                       payment = {...} → se cobra / se corrige el cobro con el nuevo total:
--                         mismo método → solo se cuadra la diferencia (regresar o cobrar de más;
--                         difference_received = con cuánto pagó la diferencia en efectivo);
--                         otro método o antes sin cobrar → cash_received = con cuánto pagó el total.
--                       sin payment     → se conserva el cobro y se ajusta al nuevo total.
--                     · Cada edición queda registrada (quién, cuándo, qué cambió, antes y después).
--   orders/edits.php  GET ?id=N → historial de ediciones de un pedido
--
-- También actualiza orders/active.php, sales/index.php y sales/show.php para que digan si el
-- pedido se editó (edited_at, edit_count) y traigan los datos del cobro.
-- =====================================================================
set check_function_bodies = off;

-- ---------- Tablas ----------
alter table la_obra_v2.orders add column if not exists edited_at timestamp null;
alter table la_obra_v2.orders add column if not exists edit_count int not null default 0;

create table if not exists la_obra_v2.order_edits (
  id          serial primary key,
  order_id    int not null references la_obra_v2.orders(id) on update cascade on delete cascade,
  user_id     int not null references la_obra_v2.users(id) on update cascade on delete restrict,
  edited_at   timestamp not null default localtimestamp,
  summary     text not null,
  reason      varchar(255) null,
  before_data jsonb not null,
  after_data  jsonb not null
);
alter table la_obra_v2.order_edits add column if not exists payment_adjustment jsonb null;
create index if not exists idx_order_edits_order on la_obra_v2.order_edits(order_id);
alter table la_obra_v2.order_edits enable row level security;

-- ---------- Utilidades ----------
create or replace function la_obra_v2.fmt_money(v numeric)
returns text language sql immutable as $$
  select '$' || to_char(coalesce(v, 0), 'FM999,999,990.00');
$$;

-- Foto del pedido para comparar antes / después
create or replace function la_obra_v2.order_snapshot(p_order int)
returns jsonb language sql stable as $$
  select jsonb_build_object('total', o.total::float8, 'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name,
    'payment_status', o.payment_status, 'items', la_obra_v2.order_items_json(o.id),
    'payment', (select jsonb_build_object('payment_method_id', p.payment_method_id, 'payment_method', pm.name, 'amount', p.amount::float8,
                  'cash_received', p.cash_received::float8, 'change_amount', p.change_amount::float8)
                  from la_obra_v2.payments p join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id where p.order_id = o.id))
  from la_obra_v2.orders o where o.id = p_order;
$$;

-- Resumen legible de lo que cambió: "Quitó 1× Hamburguesa doble · Agregó 1× Hamburguesa · Total: $100.00 → $80.00 · Se regresaron $20.00 …"
-- adj = cómo se cuadró el cobro (ver ep_orders__edit)
drop function if exists la_obra_v2.order_edit_summary(jsonb, jsonb);
create or replace function la_obra_v2.order_edit_summary(a jsonb, z jsonb, adj jsonb default null)
returns text language plpgsql immutable as $$
declare parts text[] := '{}'; r record; pz jsonb := z -> 'payment'; v_t text; v_m text;
begin
  for r in
    select coalesce(x.pid, y.pid) as pid, coalesce(y.name, x.name) as name, coalesce(x.qty, 0) as q0, coalesce(y.qty, 0) as q1, x.ord as o0, y.ord as o1
      from (select (e ->> 'product_id')::int as pid, e ->> 'name' as name, (e ->> 'quantity')::int as qty, n as ord
              from jsonb_array_elements(coalesce(a -> 'items', '[]')) with ordinality s(e, n)) x
      full join (select (e ->> 'product_id')::int as pid, e ->> 'name' as name, (e ->> 'quantity')::int as qty, n as ord
              from jsonb_array_elements(coalesce(z -> 'items', '[]')) with ordinality s(e, n)) y on y.pid = x.pid
     order by (x.ord is null), x.ord, y.ord
  loop
    if r.q0 = 0 and r.q1 > 0 then parts := parts || ('Agregó ' || r.q1 || '× ' || r.name);
    elsif r.q1 = 0 and r.q0 > 0 then parts := parts || ('Quitó ' || r.q0 || '× ' || r.name);
    elsif r.q0 <> r.q1 then parts := parts || (r.name || ': ' || r.q0 || ' → ' || r.q1);
    end if;
  end loop;
  if (a ->> 'delivery_mode') is distinct from (z ->> 'delivery_mode') then
    parts := parts || ('Ahora ' || case when z ->> 'delivery_mode' = 'takeaway' then 'para llevar' else 'para comer aquí' end);
  end if;
  if coalesce(a ->> 'customer_name', '') is distinct from coalesce(z ->> 'customer_name', '') then
    parts := parts || ('Cliente: ' || coalesce(nullif(a ->> 'customer_name', ''), '—') || ' → ' || coalesce(nullif(z ->> 'customer_name', ''), '—'));
  end if;
  if (a ->> 'total')::numeric is distinct from (z ->> 'total')::numeric then
    parts := parts || ('Total: ' || la_obra_v2.fmt_money((a ->> 'total')::numeric) || ' → ' || la_obra_v2.fmt_money((z ->> 'total')::numeric));
  end if;

  if adj is not null then
    v_t := adj ->> 'type';
    v_m := adj ->> 'method';
    if v_t = 'refund' then
      parts := parts || ('Se regresaron ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' al cliente (' || v_m || ')');
    elsif v_t = 'charge' then
      parts := parts || ('Cobró ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' más (' || v_m || ')'
        || case when adj ? 'received' then
             case when (adj ->> 'change')::numeric > 0
                  then ': pagó con ' || la_obra_v2.fmt_money((adj ->> 'received')::numeric) || ', cambio ' || la_obra_v2.fmt_money((adj ->> 'change')::numeric)
                  else ': pago exacto' end
           else '' end);
    elsif v_t in ('new', 'method_change') then
      parts := parts || (case when v_t = 'method_change'
                                then 'Cambió el cobro de ' || (adj ->> 'method_before') || ' a ' || v_m || ': se regresaron '
                                     || la_obra_v2.fmt_money((adj ->> 'refund')::numeric) || ' (' || (adj ->> 'method_before') || ') y se cobraron '
                                     || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' (' || v_m || ')'
                                else 'Cobrado con ' || v_m || ' ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) end
        || case when adj ? 'received' then
             case when (adj ->> 'change')::numeric > 0
                  then ': pagó con ' || la_obra_v2.fmt_money((adj ->> 'received')::numeric) || ', cambio ' || la_obra_v2.fmt_money((adj ->> 'change')::numeric)
                  else ': pago exacto' end
           else '' end);
    elsif v_t = 'removed' then
      parts := parts || ('Se quitó el cobro: se regresaron ' || la_obra_v2.fmt_money((adj ->> 'amount')::numeric) || ' al cliente (' || v_m || '); queda por cobrar');
    end if;
  end if;
  if cardinality(parts) = 0 then return null; end if;
  return array_to_string(parts, ' · ');
end $$;

-- ---------- orders/edit.php ----------
create or replace function la_obra_v2.ep_orders__edit(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record; v_mode text; v_customer text; v_reason text; it jsonb; v_pid int; v_q int;
        v_lines jsonb := '{}'; k text; pr record; v_before jsonb; v_after jsonb; v_summary text; v_total numeric;
        v_pay jsonb; v_has_pay boolean; pm record; cur record; v_cash numeric; v_change numeric; v_cash_j jsonb;
        v_adj jsonb; v_diff numeric; v_received numeric; v_is_cash boolean;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t);
  b := la_obra_v2.body(b);
  v_id := la_obra_v2.positive_id(b -> 'order_id', 'El id del pedido no es válido');
  select id, order_status, delivery_status, delivery_mode, customer_name into o from la_obra_v2.orders where id = v_id for update;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  if o.order_status = 'cancelled' then perform la_obra_v2.fail(409, 'El pedido está cancelado'); end if;
  if o.order_status <> 'confirmed' then perform la_obra_v2.fail(409, 'El pedido aún no está confirmado'); end if;
  if o.delivery_status = 'delivered' then perform la_obra_v2.fail(409, 'El pedido ya se entregó; ya no se puede editar'); end if;

  -- Modalidad y cliente (si no vienen, se conservan)
  v_mode := o.delivery_mode;
  if b ? 'delivery_mode' and la_obra_v2.jtext(b -> 'delivery_mode') is not null then v_mode := la_obra_v2.jtext(b -> 'delivery_mode'); end if;
  if v_mode not in ('local','takeaway') then perform la_obra_v2.fail(422, 'Modalidad inválida'); end if;
  v_customer := o.customer_name;
  if b ? 'customer_name' then v_customer := nullif(la_obra_v2.jstr(b -> 'customer_name'), ''); end if;
  if char_length(coalesce(v_customer, '')) > 80 then perform la_obra_v2.fail(422, 'Nombre del cliente demasiado largo'); end if;
  v_reason := nullif(la_obra_v2.jstr(b -> 'reason'), '');
  if char_length(coalesce(v_reason, '')) > 255 then perform la_obra_v2.fail(422, 'El motivo es demasiado largo'); end if;

  -- Productos (se juntan repetidos)
  if jsonb_typeof(b -> 'items') is distinct from 'array' or jsonb_array_length(b -> 'items') = 0 then
    perform la_obra_v2.fail(422, 'El pedido debe tener al menos un producto; si ya no lo quieren, cancélalo');
  end if;
  for it in select * from jsonb_array_elements(b -> 'items') loop
    v_pid := la_obra_v2.positive_id(it -> 'product_id');
    if not la_obra_v2.is_int(it -> 'quantity') or la_obra_v2.num(it -> 'quantity') <= 0 or la_obra_v2.num(it -> 'quantity') > 999 then
      perform la_obra_v2.fail(422, 'Cantidad inválida');
    end if;
    v_q := la_obra_v2.num(it -> 'quantity');
    v_lines := jsonb_set(v_lines, array[v_pid::text], to_jsonb(coalesce((v_lines ->> v_pid::text)::int, 0) + v_q));
  end loop;
  -- Solo se exige que esté disponible lo que se agrega; lo que ya estaba se respeta
  for k in select key from jsonb_each(v_lines) loop
    if not exists(select 1 from la_obra_v2.order_items where order_id = v_id and product_id = k::int) then
      select id, name, price, status, is_available into pr from la_obra_v2.products where id = k::int;
      if pr.id is null then perform la_obra_v2.fail(404, 'Producto no encontrado'); end if;
      if pr.status <> 'active' or not pr.is_available then perform la_obra_v2.fail(409, pr.name || ' no está disponible'); end if;
    end if;
  end loop;

  v_before := la_obra_v2.order_snapshot(v_id);

  -- Quitar, cambiar cantidad y agregar
  delete from la_obra_v2.order_items where order_id = v_id and not (v_lines ? product_id::text);
  for k, v_q in select e.key, e.value::int from jsonb_each_text(v_lines) e loop
    if exists(select 1 from la_obra_v2.order_items where order_id = v_id and product_id = k::int) then
      update la_obra_v2.order_items set quantity = v_q, subtotal = round(unit_price * v_q, 2)
       where order_id = v_id and product_id = k::int and quantity <> v_q;
    else
      select price into pr from la_obra_v2.products where id = k::int;
      insert into la_obra_v2.order_items(order_id, product_id, quantity, unit_price, subtotal, standard_unit_cost)
      values (v_id, k::int, v_q, pr.price, round(pr.price * v_q, 2), (la_obra_v2.product_cost(k::int, v_mode) ->> 'standard_cost')::numeric);
    end if;
  end loop;
  -- Si cambió la modalidad, el costo estándar de cada línea se vuelve a calcular (empaques para llevar, etc.)
  if v_mode is distinct from o.delivery_mode then
    update la_obra_v2.order_items oi set standard_unit_cost = (la_obra_v2.product_cost(oi.product_id, v_mode) ->> 'standard_cost')::numeric
     where oi.order_id = v_id;
  end if;
  select round(coalesce(sum(subtotal), 0), 2) into v_total from la_obra_v2.order_items where order_id = v_id;
  update la_obra_v2.orders set total = v_total, delivery_mode = v_mode, customer_name = v_customer where id = v_id;

  -- Cobro. Se cuadra contra lo que ya se había cobrado:
  --   · mismo método y el total bajó  → se regresa la diferencia al cliente
  --   · mismo método y el total subió → se cobra la diferencia (en efectivo: con cuánto pagó y su cambio)
  --   · otro método                   → se regresa el cobro anterior y se cobra el nuevo total completo
  --   · antes por cobrar              → se cobra el total completo
  --   · payment = null                → se quita el cobro y se regresa lo cobrado
  -- En payments siempre queda amount = nuevo total y, en efectivo, cash_received − change_amount = amount.
  v_has_pay := b ? 'payment';
  v_pay := b -> 'payment';
  select p.id, p.payment_method_id, p.amount, p.cash_received, p.change_amount, pm2.name into cur
    from la_obra_v2.payments p join la_obra_v2.payment_methods pm2 on pm2.id = p.payment_method_id where p.order_id = v_id;
  if v_has_pay and (v_pay is null or jsonb_typeof(v_pay) = 'null') then
    if cur.id is not null then
      v_adj := jsonb_build_object('type', 'removed', 'amount', cur.amount, 'method', cur.name);
      delete from la_obra_v2.payments where order_id = v_id;
    end if;
    update la_obra_v2.orders set payment_status = 'pending' where id = v_id;
  elsif v_has_pay or cur.id is not null then
    if v_has_pay then
      if jsonb_typeof(v_pay) <> 'object' then perform la_obra_v2.fail(422, 'Datos de pago inválidos'); end if;
      select id, name, status into pm from la_obra_v2.payment_methods where id = la_obra_v2.positive_id(v_pay -> 'payment_method_id', 'Elige el método de pago');
      if pm.id is null then perform la_obra_v2.fail(404, 'Método de pago no encontrado'); end if;
      -- Un método que ya se desactivó solo se acepta si es el que ya tenía el cobro
      if pm.status <> 'active' and pm.id is distinct from cur.payment_method_id then perform la_obra_v2.fail(409, 'El método de pago está inactivo'); end if;
    else
      v_pay := '{}'::jsonb;
      select id, name, status into pm from la_obra_v2.payment_methods where id = cur.payment_method_id;
    end if;
    v_is_cash := lower(btrim(pm.name)) = 'efectivo';
    v_cash := null; v_change := null;

    if cur.id is not null and pm.id = cur.payment_method_id then
      -- Mismo método: solo se cuadra la diferencia
      v_diff := v_total - cur.amount;
      if v_diff > 0 then
        v_adj := jsonb_build_object('type', 'charge', 'amount', v_diff, 'method', pm.name);
        if v_is_cash then
          v_cash_j := coalesce(nullif(v_pay -> 'difference_received', 'null'::jsonb), to_jsonb(v_diff));
          if not la_obra_v2.is_num(v_cash_j) or la_obra_v2.num(v_cash_j) < v_diff then
            perform la_obra_v2.fail(422, 'Con lo que pagó no alcanza la diferencia (' || la_obra_v2.fmt_money(v_diff) || ')');
          end if;
          v_received := round(la_obra_v2.num(v_cash_j), 2);
          v_change := round(v_received - v_diff, 2);
          v_cash := v_total + v_change;
          v_adj := v_adj || jsonb_build_object('received', v_received, 'change', v_change);
        end if;
      elsif v_diff < 0 then
        v_adj := jsonb_build_object('type', 'refund', 'amount', -v_diff, 'method', pm.name);
        if v_is_cash then v_cash := v_total; v_change := 0; end if;
      else
        v_cash := cur.cash_received; v_change := cur.change_amount;
      end if;
    else
      -- Cobro nuevo (o con otro método): el nuevo total completo
      v_adj := jsonb_build_object('type', case when cur.id is null then 'new' else 'method_change' end, 'amount', v_total, 'method', pm.name);
      if cur.id is not null then v_adj := v_adj || jsonb_build_object('method_before', cur.name, 'refund', cur.amount); end if;
      if v_is_cash then
        v_cash_j := coalesce(nullif(v_pay -> 'cash_received', 'null'::jsonb), to_jsonb(v_total));
        if not la_obra_v2.is_num(v_cash_j) or la_obra_v2.num(v_cash_j) < v_total then
          perform la_obra_v2.fail(422, 'El efectivo recibido debe cubrir el nuevo total (' || la_obra_v2.fmt_money(v_total) || ')');
        end if;
        v_cash := round(la_obra_v2.num(v_cash_j), 2);
        v_change := round(v_cash - v_total, 2);
        v_adj := v_adj || jsonb_build_object('received', v_cash, 'change', v_change);
      end if;
    end if;

    if cur.id is not null then
      update la_obra_v2.payments set payment_method_id = pm.id, amount = v_total, cash_received = v_cash, change_amount = v_change,
             commission_amount = la_obra_v2.payment_commission(pm.id, v_total)
       where id = cur.id;
    else
      insert into la_obra_v2.payments(order_id, payment_method_id, amount, cash_received, change_amount, commission_amount)
      values (v_id, pm.id, v_total, v_cash, v_change, la_obra_v2.payment_commission(pm.id, v_total));
    end if;
    update la_obra_v2.orders set payment_status = 'paid' where id = v_id;
  end if;

  v_after := la_obra_v2.order_snapshot(v_id);
  v_summary := la_obra_v2.order_edit_summary(v_before, v_after, v_adj);
  if v_summary is null then perform la_obra_v2.fail(422, 'No hiciste ningún cambio'); end if;

  insert into la_obra_v2.order_edits(order_id, user_id, summary, reason, before_data, after_data, payment_adjustment)
  values (v_id, u.id, v_summary, v_reason, v_before, v_after, v_adj);
  update la_obra_v2.orders set edited_at = localtimestamp, edit_count = edit_count + 1 where id = v_id;

  return la_obra_v2.ok(200, 'Pedido actualizado', jsonb_build_object(
    'order', jsonb_build_object('id', v_id, 'total', v_total::float8, 'payment_status', v_after ->> 'payment_status',
      'change_amount', v_change::float8),
    'edit', jsonb_build_object('summary', v_summary, 'payment_adjustment', v_adj)));
end $$;

-- ---------- orders/edits.php ----------
create or replace function la_obra_v2.order_edits_json(p_order int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'edited_at', e.edited_at, 'user_name', us.name, 'summary', e.summary,
    'reason', e.reason, 'total_before', (e.before_data ->> 'total')::float8, 'total_after', (e.after_data ->> 'total')::float8,
    'payment_adjustment', e.payment_adjustment)
    order by e.edited_at desc, e.id desc), '[]'::jsonb)
  from la_obra_v2.order_edits e join la_obra_v2.users us on us.id = e.user_id where e.order_id = p_order;
$$;

create or replace function la_obra_v2.ep_orders__edits(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(q -> 'id') then perform la_obra_v2.fail(422, 'El id del pedido no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id');
  select id, user_id, created_at, delivery_status, order_status into o from la_obra_v2.orders where id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Pedido no encontrado'); end if;
  -- El empleado ve lo mismo que en el historial (sus pedidos del día) y los pedidos en curso
  if u.role = 'employee' and not (o.order_status = 'confirmed' and o.delivery_status = 'pending')
     and (o.user_id <> u.id or o.created_at::date <> current_date) then
    perform la_obra_v2.fail(403, 'Solo puedes consultar tus pedidos del día');
  end if;
  return la_obra_v2.ok(200, 'Ediciones del pedido', jsonb_build_object('edits', la_obra_v2.order_edits_json(v_id)));
end $$;

-- ---------- Rutas existentes con datos de edición y cobro ----------
create or replace function la_obra_v2.ep_orders__active(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
begin
  perform la_obra_v2.method(m, 'GET');
  perform la_obra_v2.auth_long(t);
  return la_obra_v2.ok(200, 'Pedidos en curso', jsonb_build_object('orders', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'total', o.total::float8, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'delivery_mode', o.delivery_mode, 'customer_name', o.customer_name, 'created_at', o.created_at,
      'confirmed_at', o.confirmed_at, 'user_name', u.name, 'edited_at', o.edited_at, 'edit_count', o.edit_count,
      'payment_method_id', p.payment_method_id, 'payment_method', pm.name, 'cash_received', p.cash_received::float8,
      'change_amount', p.change_amount::float8, 'items', la_obra_v2.order_items_json(o.id)) order by o.created_at, o.id), '[]')
    from la_obra_v2.orders o join la_obra_v2.users u on u.id = o.user_id
    left join la_obra_v2.payments p on p.order_id = o.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where o.order_status = 'confirmed' and (o.payment_status = 'pending' or o.delivery_status = 'pending'))));
end $$;

create or replace function la_obra_v2.ep_sales__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_ps text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'payment_status')); v_ds text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'delivery_status'));
        v_os text := la_obra_v2.jtext(la_obra_v2.qparam(q, 'order_status')); v_pm int; v_date date;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if v_ps is not null and v_ps not in ('pending','paid') then perform la_obra_v2.fail(422, 'Filtro payment_status inválido'); end if;
  if v_ds is not null and v_ds not in ('pending','delivered') then perform la_obra_v2.fail(422, 'Filtro delivery_status inválido'); end if;
  if v_os is not null and v_os not in ('open','confirmed','cancelled') then perform la_obra_v2.fail(422, 'Filtro order_status inválido'); end if;
  if la_obra_v2.qparam(q, 'payment_method_id') is not null then
    if not la_obra_v2.int_arg(q -> 'payment_method_id') then perform la_obra_v2.fail(422, 'Filtro payment_method_id inválido'); end if;
    v_pm := la_obra_v2.num(q -> 'payment_method_id');
  end if;
  if u.role <> 'employee' and la_obra_v2.qparam(q, 'date') is not null then
    v_date := la_obra_v2.dateval(q -> 'date', 'Filtro date inválido');
  end if;
  return la_obra_v2.ok(200, 'Ventas', jsonb_build_object('scope', case when u.role = 'employee' then 'today_own' else 'all' end, 'sales', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'user_id', o.user_id, 'user_name', us.name, 'delivery_mode', o.delivery_mode,
      'customer_name', o.customer_name, 'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at,
      'cancelled_at', o.cancelled_at, 'total', o.total::float8, 'order_status', o.order_status, 'payment_status', o.payment_status,
      'delivery_status', o.delivery_status, 'payment_method_id', pm.id, 'payment_method', pm.name, 'paid_at', p.paid_at,
      'commission_amount', p.commission_amount::float8, 'cash_received', p.cash_received::float8, 'change_amount', p.change_amount::float8,
      'edited_at', o.edited_at, 'edit_count', o.edit_count,
      'items', la_obra_v2.order_items_json(o.id)) order by o.created_at desc, o.id desc), '[]')
    from la_obra_v2.orders o join la_obra_v2.users us on us.id = o.user_id
    left join la_obra_v2.payments p on p.order_id = o.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id
    where (v_ps is null or o.payment_status = v_ps) and (v_ds is null or o.delivery_status = v_ds) and (v_os is null or o.order_status = v_os)
      and (v_pm is null or p.payment_method_id = v_pm)
      and (u.role <> 'employee' or (o.user_id = u.id and o.created_at::date = current_date))
      and (v_date is null or o.created_at::date = v_date))));
end $$;

create or replace function la_obra_v2.ep_sales__show(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; o record;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth_long(t);
  if not la_obra_v2.int_arg(q -> 'id') then perform la_obra_v2.fail(422, 'El id no es válido'); end if;
  v_id := la_obra_v2.num(q -> 'id');
  select o2.*, us.name as user_name, p.id as payment_id, p.amount, p.cash_received, p.change_amount, p.paid_at, p.commission_amount, pm.id as pm_id, pm.name as pm_name
    into o from la_obra_v2.orders o2 join la_obra_v2.users us on us.id = o2.user_id
    left join la_obra_v2.payments p on p.order_id = o2.id left join la_obra_v2.payment_methods pm on pm.id = p.payment_method_id where o2.id = v_id;
  if o.id is null then perform la_obra_v2.fail(404, 'Venta o pedido no encontrado'); end if;
  if u.role = 'employee' and (o.user_id <> u.id or o.created_at::date <> current_date) then perform la_obra_v2.fail(403, 'Solo puedes consultar tus pedidos del día'); end if;
  return la_obra_v2.ok(200, 'Venta', jsonb_build_object('sale', jsonb_build_object('id', o.id, 'user', jsonb_build_object('id', o.user_id, 'name', o.user_name),
    'order_status', o.order_status, 'payment_status', o.payment_status, 'delivery_status', o.delivery_status, 'total', o.total::float8,
    'created_at', o.created_at, 'confirmed_at', o.confirmed_at, 'delivered_at', o.delivered_at, 'cancelled_at', o.cancelled_at,
    'edited_at', o.edited_at, 'edit_count', o.edit_count, 'edits', la_obra_v2.order_edits_json(o.id),
    'items', la_obra_v2.order_items_json(o.id),
    'payment', case when o.payment_id is null then null else jsonb_build_object('id', o.payment_id, 'payment_method_id', o.pm_id, 'payment_method', o.pm_name,
      'amount', o.amount::float8, 'cash_received', o.cash_received::float8, 'change_amount', o.change_amount::float8, 'paid_at', o.paid_at,
      'commission_amount', o.commission_amount::float8) end)));
end $$;

-- Que la API de Supabase vea los cambios sin esperar
notify pgrst, 'reload schema';

-- >>>>>>>>>> 13_planes_y_creditos.sql
-- =====================================================================
-- La Obra v2 · 13 · Planes de suscripción (Plan gratuito, Silver, Gold) y créditos
--
-- El Plan gratuito no se contrata ni vence: es el plan del negocio siempre que no tenga
-- vigente uno de paga (o la prueba). Al cancelar o al vencer un plan, el negocio pasa a él.
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
  free_plan    varchar(20) not null default 'gratuito',   -- plan cuando no hay uno de paga vigente
  currency     varchar(3) not null default 'MXN',
  credit_value numeric(10,2) not null default 1.00 check (credit_value > 0),   -- pesos por crédito (para prorrateos)
  bank_info    varchar(255) not null default ''
);
alter table la_obra_v2.billing_settings add column if not exists free_plan varchar(20) not null default 'gratuito';
-- Devolución en créditos del tiempo no usado de un plan (al cambiar de plan o cancelar un anual):
-- refund_credits créditos por cada refund_pesos pesos, en proporción a los días que sobraban.
alter table la_obra_v2.billing_settings add column if not exists refund_pesos numeric(10,2) not null default 500 check (refund_pesos > 0);
alter table la_obra_v2.billing_settings add column if not exists refund_credits int not null default 10 check (refund_credits >= 0);
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
-- Cancelación al final del periodo: el plan sigue vigente hasta ends_at y ya no se renueva
alter table la_obra_v2.subscriptions add column if not exists cancel_requested_at timestamp null;
alter table la_obra_v2.subscriptions add column if not exists cancel_reason varchar(255) null;
-- Al cancelar, el plan termina al acabar el mes en curso: se guarda la fecha original (para Reactivar)
-- y los créditos que se devolvieron por los meses que ya no se usarán (se descuentan si se reactiva).
alter table la_obra_v2.subscriptions add column if not exists cancel_original_ends_at timestamp null;
alter table la_obra_v2.subscriptions add column if not exists cancel_refund_credits int null;

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
  ('gratuito', 'Plan gratuito', 'Para empezar sin costo: vender, cortar caja y registrar gastos', 0, 0, 3, 1),
  ('silver', 'Silver', 'Controla inventario, compras, asistencia y reportes',       599.00,  5990.00, 8,    2),
  ('gold',   'Gold',   'Todo el sistema: recetas y costos, facturación y respaldos', 999.00,  9990.00, null, 3)
on conflict (code) do nothing;

-- Instalaciones anteriores: el plan Bronze se convierte en el Plan gratuito
-- (sus funciones, su límite de usuarios y su historial pasan al gratuito; precio $0).
do $$
begin
  if exists (select 1 from la_obra_v2.plans where code = 'bronze') then
    insert into la_obra_v2.plans(code, name, description, monthly_price, annual_price, max_users, sort, status)
    select 'gratuito', 'Plan gratuito', 'Para empezar sin costo: vender, cortar caja y registrar gastos', 0, 0, max_users, sort, 'active'
      from la_obra_v2.plans where code = 'bronze'
    on conflict (code) do nothing;
    insert into la_obra_v2.plan_features(plan_code, feature_key)
    select 'gratuito', feature_key from la_obra_v2.plan_features where plan_code = 'bronze'
    on conflict do nothing;
    update la_obra_v2.subscriptions set plan_code = 'gratuito' where plan_code = 'bronze';
    delete from la_obra_v2.plans where code = 'bronze';
  end if;
end $$;

insert into la_obra_v2.plan_features(plan_code, feature_key)
select p, f from (values
  ('gratuito','ventas'), ('gratuito','gastos'),
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

-- Plan con el que trabaja el negocio ahora: el vigente o, si no hay, el Plan gratuito
create or replace function la_obra_v2.billing_free_plan()
returns text language sql stable as $$
  select p.code from la_obra_v2.billing_settings s join la_obra_v2.plans p on p.code = s.free_plan and p.status = 'active'
   where s.id = 1;
$$;

create or replace function la_obra_v2.billing_effective_plan(p_business int)
returns text language sql stable as $$
  select coalesce((la_obra_v2.billing_current_sub(p_business)).plan_code, la_obra_v2.billing_free_plan());
$$;

create or replace function la_obra_v2.billing_feature_in_plan(p_business int, p_feature text)
returns boolean language sql stable as $$
  select exists (select 1 from la_obra_v2.plan_features pf
                  where pf.plan_code = la_obra_v2.billing_effective_plan(p_business) and pf.feature_key = p_feature);
$$;

-- ¿El negocio puede usar esta función ahora? (por su plan o por créditos)
create or replace function la_obra_v2.billing_feature_active(p_business int, p_feature text)
returns boolean language sql stable as $$
  select la_obra_v2.billing_feature_in_plan(p_business, p_feature)
      or la_obra_v2.billing_unlock_until(p_business, p_feature) is not null;
$$;

-- Usuarios activos que permite el plan con el que trabaja el negocio (null = sin límite).
-- Sin plan vigente cuenta el Plan gratuito (o, si no existiera, el plan más chico).
create or replace function la_obra_v2.billing_max_users(p_business int)
returns int language plpgsql stable as $$
declare s la_obra_v2.subscriptions; v int;
begin
  s := la_obra_v2.billing_current_sub(p_business);
  if s.id is not null then
    select max_users into v from la_obra_v2.plans where code = s.plan_code;
    return v;
  end if;
  if la_obra_v2.billing_free_plan() is not null then
    select max_users into v from la_obra_v2.plans where code = la_obra_v2.billing_free_plan();
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
      when (la_obra_v2.billing_current_sub(v_biz)).id is null and la_obra_v2.billing_free_plan() is not null then
        'El negocio está en el Plan gratuito, que no incluye "' || f.name || '". ' || case when u.role = 'admin'
          then 'Contrata un plan o desbloquéala con créditos en Plan y créditos.'
          else 'Pide al administrador que la active.' end
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
        select p.name into v_plan from la_obra_v2.plans p where p.code = la_obra_v2.billing_effective_plan(new.business_id);
        perform la_obra_v2.fail(402, 'El ' || coalesce(case when v_plan ilike 'plan %' then v_plan else 'plan ' || v_plan end, 'plan actual') || ' permite hasta ' || v_max ||
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

-- ---------- Devoluciones en créditos ----------
-- Pesos → créditos según la regla (por defecto 10 créditos por cada $500), hacia abajo.
create or replace function la_obra_v2.billing_refund_credits(p_value numeric)
returns int language sql stable as $$
  select greatest(0, floor(coalesce(p_value, 0) * s.refund_credits / s.refund_pesos))::int
    from la_obra_v2.billing_settings s where s.id = 1;
$$;

-- Valor en pesos del tiempo que le queda a un plan pagado desde p_at (0 si es prueba, cortesía o ya pasó).
-- Se calcula sobre el periodo que se pagó (si se canceló, sobre su fecha original).
create or replace function la_obra_v2.billing_leftover_value(x la_obra_v2.subscriptions, p_at timestamp)
returns numeric language sql stable as $$
  select case
    when x.billing_cycle not in ('monthly','annual') or x.price <= 0 or x.ends_at <= p_at then 0
    else x.price * extract(epoch from (x.ends_at - greatest(x.starts_at, p_at)))
                 / extract(epoch from (coalesce(x.cancel_original_ends_at, x.ends_at) - x.starts_at)) end;
$$;

-- Fecha en que termina un plan si se cancela en p_at: al acabar el mes en curso de ese plan
-- (mensual: su fecha de vencimiento; anual: el siguiente corte mensual; nunca después de su vencimiento).
create or replace function la_obra_v2.billing_cancel_cut(x la_obra_v2.subscriptions, p_at timestamp)
returns timestamp language plpgsql stable as $$
declare k int := 1;
begin
  if x.starts_at > p_at then return x.starts_at; end if;
  k := greatest(1, (extract(year from age(p_at, x.starts_at)) * 12 + extract(month from age(p_at, x.starts_at)))::int);
  while x.starts_at + make_interval(months => k) <= p_at loop k := k + 1; end loop;
  return least(x.ends_at, x.starts_at + make_interval(months => k));
end $$;

-- Créditos que se abonarían HOY al cambiar de plan (lo que sobra del plan actual y renovaciones ya pagadas)
create or replace function la_obra_v2.billing_change_refund(p_business int)
returns int language sql stable as $$
  select la_obra_v2.billing_refund_credits(sum(la_obra_v2.billing_leftover_value(s, la_obra_v2.mx_now())))
    from la_obra_v2.subscriptions s
   where s.business_id = p_business and s.status = 'active' and s.ends_at > la_obra_v2.mx_now();
$$;

-- ---------- Aplicar un pago ya aprobado ----------
-- Suscripción: la activa (renovación, primera contratación o cambio de plan con prorrateo).
-- Créditos: los suma al saldo.
create or replace function la_obra_v2.billing_apply_payment(p_payment int)
returns jsonb language plpgsql as $$
declare
  pay la_obra_v2.billing_payments; cur la_obra_v2.subscriptions; q la_obra_v2.subscriptions; pl la_obra_v2.plans; st la_obra_v2.billing_settings;
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
      -- Si estaba cancelado, renovar significa que el negocio sigue: se quita la cancelación
      -- (si se había recortado al cancelar, se queda la fecha recortada: lo nuevo empieza ahí)
      update la_obra_v2.subscriptions set cancel_requested_at = null, cancel_reason = null,
             cancel_original_ends_at = null, cancel_refund_credits = null where id = cur.id;
    else
      -- Plan nuevo o cambio de plan (subir o bajar): empieza ahora y se paga completo.
      -- Lo que sobraba del plan anterior (y de renovaciones ya pagadas) se abona en créditos:
      -- refund_credits por cada refund_pesos (10 por cada $500), en proporción a los días que sobraban.
      v_start := v_now;
      v_refund := 0;
      for q in select * from la_obra_v2.subscriptions
                where business_id = pay.business_id and status = 'active' and ends_at > v_now for update loop
        v_refund := v_refund + la_obra_v2.billing_leftover_value(q, v_now);
        update la_obra_v2.subscriptions set status = 'replaced', closed_at = v_now where id = q.id;
      end loop;
      v_cr := la_obra_v2.billing_refund_credits(v_refund);
      if v_cr > 0 then
        perform la_obra_v2.credit_move(pay.business_id, 'proration', v_cr,
          'Tiempo no usado del plan anterior (' || to_char(v_refund, 'FM999,990.00') || ' pesos) al cambiar a ' || pl.name,
          pay.created_by, pay.created_by_name, null, pay.id);
        v_note := 'Se abonaron ' || v_cr || ' créditos por el tiempo que te sobraba del plan anterior';
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
-- Datos de la tarjeta (modo de prueba). La app valida el número completo (algoritmo de Luhn),
-- el vencimiento y el CVV, y SOLO manda marca, últimos 4 dígitos, vencimiento y titular:
-- el número completo y el CVV nunca llegan a la base de datos ni se guardan.
-- Tarjeta de prueba que siempre se rechaza: termina en 0002 (ej. 4000 0000 0000 0002).
create or replace function la_obra_v2.billing_card(c jsonb)
returns jsonb language plpgsql as $$
declare v_brand text; v_last4 text; v_m int; v_y int; v_holder text;
begin
  if c is null or jsonb_typeof(c) <> 'object' then perform la_obra_v2.fail(422, 'Captura los datos de la tarjeta'); end if;
  v_brand := la_obra_v2.jstr(c -> 'brand');
  v_last4 := la_obra_v2.jstr(c -> 'last4');
  v_holder := left(la_obra_v2.jstr(c -> 'holder'), 100);
  if v_brand not in ('Visa','Mastercard','American Express') then perform la_obra_v2.fail(422, 'Solo se aceptan tarjetas Visa, Mastercard o American Express'); end if;
  if v_last4 !~ '^\d{4}$' then perform la_obra_v2.fail(422, 'El número de tarjeta no es válido'); end if;
  if length(v_holder) < 3 then perform la_obra_v2.fail(422, 'Escribe el nombre como aparece en la tarjeta'); end if;
  if not la_obra_v2.is_int(c -> 'exp_month') or not la_obra_v2.is_int(c -> 'exp_year') then
    perform la_obra_v2.fail(422, 'La fecha de vencimiento no es válida');
  end if;
  v_m := la_obra_v2.jtext(c -> 'exp_month')::int;
  v_y := la_obra_v2.jtext(c -> 'exp_year')::int;
  if v_y < 100 then v_y := 2000 + v_y; end if;
  if v_m not between 1 and 12 or v_y > extract(year from la_obra_v2.mx_now())::int + 20 then
    perform la_obra_v2.fail(422, 'La fecha de vencimiento no es válida');
  end if;
  if make_date(v_y, v_m, 1) + interval '1 month' <= la_obra_v2.mx_now() then
    perform la_obra_v2.fail(422, 'La tarjeta está vencida');
  end if;
  return jsonb_build_object('brand', v_brand, 'last4', v_last4, 'exp', lpad(v_m::text, 2, '0') || '/' || right(v_y::text, 2),
                            'holder', v_holder);
end $$;

-- Registrar un pago con tarjeta y, en modo de prueba, aprobarlo y aplicarlo al momento.
-- Solo se acepta tarjeta (ni transferencia ni efectivo).
create or replace function la_obra_v2.billing_new_payment(u la_obra_v2.users, p_concept text, p_desc text, p_amount numeric,
  p_details jsonb, b jsonb)
returns jsonb language plpgsql as $$
declare st la_obra_v2.billing_settings; v_card jsonb; v_ref text; v_id int; v_res jsonb; v_biz int := la_obra_v2.user_business(u);
begin
  select * into st from la_obra_v2.billing_settings where id = 1;
  if coalesce(nullif(la_obra_v2.jstr(b -> 'method'), ''), 'card_test') <> 'card_test' then
    perform la_obra_v2.fail(422, 'Solo se acepta pago con tarjeta');
  end if;
  v_card := la_obra_v2.billing_card(b -> 'card');
  v_ref := (v_card ->> 'brand') || ' •••• ' || (v_card ->> 'last4');
  if v_card ->> 'last4' = '0002' then
    perform la_obra_v2.fail(402, 'Tarjeta rechazada por el banco (tarjeta de prueba de rechazo). Usa otra tarjeta.',
      jsonb_build_object('card_declined', true));
  end if;
  if exists (select 1 from la_obra_v2.billing_payments where business_id = v_biz and status = 'pending' and concept = p_concept) then
    perform la_obra_v2.fail(409, 'Ya hay un pago pendiente de confirmar para esto. Espera la confirmación o cancélalo.');
  end if;
  insert into la_obra_v2.billing_payments(business_id, concept, description, amount, method, reference, status, details,
    created_by, created_by_name, resolved_at)
  values (v_biz, p_concept, p_desc, p_amount, 'card_test', v_ref,
          case when st.payment_mode = 'simulated' then 'paid' else 'pending' end,
          p_details || jsonb_build_object('card', v_card), u.id, u.name,
          case when st.payment_mode = 'simulated' then la_obra_v2.mx_now() end)
  returning id into v_id;
  if st.payment_mode = 'simulated' then
    v_res := la_obra_v2.billing_apply_payment(v_id);
    return jsonb_build_object('payment_id', v_id, 'status', 'paid', 'card', v_ref, 'note', v_res ->> 'note');
  end if;
  return jsonb_build_object('payment_id', v_id, 'status', 'pending', 'card', v_ref,
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
    'free_plan', la_obra_v2.billing_free_plan(),
    'effective_plan', (select jsonb_build_object('code', p.code, 'name', p.name) from la_obra_v2.plans p
                        where p.code = la_obra_v2.billing_effective_plan(p_business)),
    'subscription', case when cur.id is null then null else jsonb_build_object(
      'id', cur.id, 'plan_code', cur.plan_code, 'plan_name', pl.name, 'cycle', cur.billing_cycle, 'price', cur.price,
      'starts_at', la_obra_v2.fmt_ts(cur.starts_at), 'ends_at', la_obra_v2.fmt_ts(cur.ends_at),
      'paid_until', la_obra_v2.fmt_ts(v_paid),
      'days_left', greatest(0, ceil(extract(epoch from (v_paid - v_now)) / 86400))::int,
      'cancel_requested_at', la_obra_v2.fmt_ts(cur.cancel_requested_at),
      -- Para la pantalla: qué pasaría si se cancela hoy y cuántos créditos daría un cambio de plan
      'cancel_at', la_obra_v2.fmt_ts(case when cur.cancel_requested_at is null then la_obra_v2.billing_cancel_cut(cur, v_now) else cur.ends_at end),
      'cancel_refund', case when cur.cancel_requested_at is null
         then la_obra_v2.billing_refund_credits(la_obra_v2.billing_leftover_value(cur, la_obra_v2.billing_cancel_cut(cur, v_now)))
              + coalesce((select sum(la_obra_v2.billing_refund_credits(la_obra_v2.billing_leftover_value(z, v_now)))::int
                            from la_obra_v2.subscriptions z where z.business_id = p_business and z.status = 'active' and z.starts_at > v_now), 0)
         else coalesce(cur.cancel_refund_credits, 0) end,
      'change_refund', la_obra_v2.billing_change_refund(p_business)) end,
    'refund_rule', jsonb_build_object('pesos', st.refund_pesos, 'credits', st.refund_credits),
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
  if pl.code = la_obra_v2.billing_free_plan() then
    perform la_obra_v2.fail(422, 'El Plan gratuito no se contrata: el negocio pasa a él solo cuando cancelas o termina tu plan. Usa "Cancelar plan".');
  end if;
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

-- billing/cancel · POST {reason?} · cancela CUALQUIER plan vigente (mensual, anual, prueba o cortesía)
--   · El plan se quita al acabar el mes en curso (mensual: en su fecha de vencimiento; anual: en el
--     siguiente corte mensual). Después el negocio pasa al Plan gratuito.
--   · Si era anual, los meses que ya no se usarán se devuelven en créditos (10 por cada $500).
--   · Las renovaciones ya pagadas que aún no empiezan se cancelan y se devuelven con la misma regla.
--   · Se puede deshacer con billing/resume antes de que termine.
create or replace function la_obra_v2.ep_billing__cancel(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_biz int; cur la_obra_v2.subscriptions; x la_obra_v2.subscriptions;
        v_now timestamp := la_obra_v2.mx_now(); v_cut timestamp; v_left numeric; v_cr int := 0; v_qcr int;
        v_qrefund int := 0; v_n int := 0; v_msg text;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t, true, 'Solo un administrador del negocio puede cancelar el plan');
  v_biz := la_obra_v2.user_business(u);
  perform 1 from la_obra_v2.businesses where id = v_biz for update;
  cur := la_obra_v2.billing_current_sub(v_biz);
  if cur.id is null then perform la_obra_v2.fail(409, 'El negocio ya está en el Plan gratuito: no hay un plan que cancelar'); end if;
  if cur.cancel_requested_at is not null then perform la_obra_v2.fail(409, 'El plan ya está cancelado'); end if;
  select * into cur from la_obra_v2.subscriptions where id = cur.id for update;

  -- 1) El plan actual termina al acabar el mes en curso; lo que sobra después se devuelve en créditos
  v_cut := la_obra_v2.billing_cancel_cut(cur, v_now);
  if v_cut < cur.ends_at then
    v_left := la_obra_v2.billing_leftover_value(cur, v_cut);
    v_cr := la_obra_v2.billing_refund_credits(v_left);
  end if;
  update la_obra_v2.subscriptions
     set cancel_requested_at = v_now,
         cancel_reason = nullif(left(la_obra_v2.jstr(coalesce(b, '{}'::jsonb) -> 'reason'), 255), ''),
         cancel_original_ends_at = ends_at,
         cancel_refund_credits = v_cr,
         ends_at = v_cut
   where id = cur.id;
  if v_cr > 0 then
    perform la_obra_v2.credit_move(v_biz, 'refund', v_cr,
      'Cancelación: meses no usados del plan ' || (select name from la_obra_v2.plans where code = cur.plan_code) ||
      ' (' || to_char(v_left, 'FM999,990.00') || ' pesos)', u.id, u.name);
  end if;

  -- 2) Renovaciones futuras ya pagadas: se cancelan y se devuelven en créditos
  for x in select * from la_obra_v2.subscriptions
            where business_id = v_biz and status = 'active' and starts_at > v_now for update loop
    update la_obra_v2.subscriptions set status = 'cancelled', closed_at = v_now where id = x.id;
    v_n := v_n + 1;
    v_qcr := la_obra_v2.billing_refund_credits(la_obra_v2.billing_leftover_value(x, v_now));
    if v_qcr > 0 then
      perform la_obra_v2.credit_move(v_biz, 'refund', v_qcr,
        'Renovación cancelada: ' || (select name from la_obra_v2.plans where code = x.plan_code) || ' desde ' || to_char(x.starts_at, 'DD/MM/YYYY'),
        u.id, u.name);
      v_qrefund := v_qrefund + v_qcr;
    end if;
  end loop;

  v_msg := 'Plan cancelado. Seguirá funcionando hasta el ' || to_char(v_cut, 'DD/MM/YYYY HH24:MI') ||
           case when la_obra_v2.billing_free_plan() is not null then ' y después el negocio pasará al Plan gratuito.'
                else '.' end;
  if v_cr > 0 then
    v_msg := v_msg || ' Por los meses que ya no usarás se devolvieron ' || v_cr || ' créditos.';
  end if;
  if v_n > 0 then
    v_msg := v_msg || case when v_n = 1 then ' Se canceló la renovación que ya estaba pagada'
                           else ' Se cancelaron ' || v_n || ' renovaciones que ya estaban pagadas' end ||
             case when v_qrefund > 0 then ' y se devolvieron ' || v_qrefund || ' créditos.' else '.' end;
  end if;
  return la_obra_v2.ok(200, v_msg, jsonb_build_object('refunded_credits', v_cr + v_qrefund, 'ends_at', la_obra_v2.fmt_ts(v_cut),
    'billing', la_obra_v2.billing_status_json(v_biz, true)));
end $$;

-- billing/resume · POST · deshace la cancelación antes de que el plan termine.
-- Regresa la fecha original y descuenta los créditos que se habían devuelto por los meses recortados
-- (las renovaciones canceladas no regresan: sus créditos se quedan en el saldo).
create or replace function la_obra_v2.ep_billing__resume(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_biz int; cur la_obra_v2.subscriptions; v_bal int; v_end timestamp;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth_long(t, true, 'Solo un administrador del negocio puede reactivar el plan');
  v_biz := la_obra_v2.user_business(u);
  perform 1 from la_obra_v2.businesses where id = v_biz for update;
  cur := la_obra_v2.billing_current_sub(v_biz);
  if cur.id is null then perform la_obra_v2.fail(409, 'El plan ya terminó. Contrata uno nuevo en Planes.'); end if;
  if cur.cancel_requested_at is null then perform la_obra_v2.fail(409, 'El plan no está cancelado'); end if;
  if coalesce(cur.cancel_refund_credits, 0) > 0 then
    select credit_balance into v_bal from la_obra_v2.businesses where id = v_biz;
    if v_bal < cur.cancel_refund_credits then
      perform la_obra_v2.fail(402, 'Para reactivar el plan se descuentan los ' || cur.cancel_refund_credits ||
        ' créditos que se te devolvieron al cancelar, y tienes ' || v_bal || '.');
    end if;
    perform la_obra_v2.credit_move(v_biz, 'adjust', -cur.cancel_refund_credits,
      'Reactivación del plan: se descuentan los créditos devueltos al cancelar', u.id, u.name);
  end if;
  v_end := coalesce(cur.cancel_original_ends_at, cur.ends_at);
  update la_obra_v2.subscriptions
     set cancel_requested_at = null, cancel_reason = null, ends_at = v_end,
         cancel_original_ends_at = null, cancel_refund_credits = null
   where id = cur.id;
  return la_obra_v2.ok(200, 'Plan reactivado hasta el ' || to_char(v_end, 'DD/MM/YYYY') ||
    case when coalesce(cur.cancel_refund_credits, 0) > 0 then '. Se descontaron ' || cur.cancel_refund_credits || ' créditos.' else '.' end,
    jsonb_build_object('billing', la_obra_v2.billing_status_json(v_biz, true)));
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
                      when s.starts_at > v_now then 'scheduled' else 'active' end,
        'cancel_requested_at', la_obra_v2.fmt_ts(s.cancel_requested_at)) order by s.starts_at desc, s.id desc), '[]')
      from (select * from la_obra_v2.subscriptions where business_id = v_biz order by starts_at desc limit 50) s
      join la_obra_v2.plans p on p.code = s.plan_code)));
end $$;

-- =====================================================================
-- Herramientas del PROVEEDOR (tú). Se usan solo desde el SQL Editor de Supabase;
-- la app no las puede llamar. Ejemplos:
--   select la_obra_v2.proveedor_modo_pago('manual');          -- pagos pendientes hasta confirmarlos
--   select * from la_obra_v2.billing_payments where status = 'pending';
--   select la_obra_v2.proveedor_confirmar_pago(5);
--   select la_obra_v2.proveedor_rechazar_pago(6, 'Pago no recibido');
--   select la_obra_v2.proveedor_regalar_creditos(50, 'Compensación');
--   select la_obra_v2.proveedor_asignar_plan('gold', 30);        -- 30 días de Gold sin cobro
--   update la_obra_v2.plans set monthly_price = 349 where code = 'silver';   -- cambiar precios
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

-- >>>>>>>>>> 10_api_publica_y_permisos.sql
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

select 'La Obra v2 instalada: ' || count(*) || ' rutas de la API' as resultado from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'la_obra_v2' and p.proname like 'ep\_%';
