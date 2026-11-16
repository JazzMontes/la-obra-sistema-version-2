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

-- ---------- Datos iniciales ----------
insert into la_obra_v2.payment_methods (name, status) values
  ('Efectivo','active'), ('Transferencia','active'), ('Tarjeta','active')
on conflict (name) do nothing;

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
