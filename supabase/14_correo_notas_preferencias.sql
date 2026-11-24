-- =====================================================================
-- La Obra v2 · 14 · Correo (Brevo), recuperar contraseña, alta de usuarios por correo,
--                    preferencias por pieza en los pedidos y Notas con recordatorios
--
-- Se puede correr solo (Supabase → SQL Editor → New query → pegar → Run) sobre una base ya
-- instalada. No borra datos: agrega 3 tablas (mail_settings, password_resets, notes),
-- 1 columna (order_items.notes) y crea/actualiza rutas de la API.
--
-- Rutas nuevas
--   auth/forgot-password.php  POST { login }                      → manda un código de 6 dígitos al correo
--   auth/reset-password.php   POST { login, code, new_password }  → cambia la contraseña con el código
--   users/resend-access.php   POST { id }      (admin)            → nueva contraseña temporal por correo
--   notes/index.php           GET  ?status=pending|done           → notas del equipo + personas
--   notes/save.php            POST { id?, title, details?, assigned_to?, remind_at?, repeat? }
--   notes/done.php            PATCH { id, done }
--   notes/delete.php          DELETE { id }
--   notes/reminders.php       GET                                 → recordatorios que le tocan a quien pregunta
-- Rutas que cambian
--   auth/login.php            entra con usuario O correo
--   users/create.php          además de crear la cuenta, le manda por correo su usuario, correo y contraseña
--   orders/checkout.php       items: [{ product_id, quantity, notes?: [{ quantity, note }] }]
--   orders/edit.php           igual; si un producto no trae "notes", conserva las que tenía
--
-- CONFIGURAR EL CORREO (una sola vez, en el SQL Editor):
--   select la_obra_v2.configurar_correo('xkeysib-…tu clave de Brevo…', 'correo-verificado@tudominio.com',
--                                       'La Obra', 'https://jazzmontes.github.io/la-obra-sistema-version-2/');
--   select la_obra_v2.probar_correo('tu-correo@gmail.com');
-- La clave queda en una tabla privada: nunca llega a la app ni a GitHub.
-- =====================================================================
set check_function_bodies = off;

-- La extensión http es la que permite llamar a Brevo desde la base (Database → Extensions → http)
do $$
begin
  create extension if not exists http with schema extensions;
exception when others then
  raise notice 'No se pudo activar la extensión http automáticamente (%). Actívala en Database → Extensions → http.', sqlerrm;
end $$;

-- =====================================================================
-- 1. Correo con Brevo
-- =====================================================================
create table if not exists la_obra_v2.mail_settings (
  id            smallint primary key default 1 check (id = 1),
  brevo_api_key text null,
  sender_email  varchar(150) null,
  sender_name   varchar(80) not null default 'La Obra',
  app_url       varchar(255) null,
  updated_at    timestamp not null default localtimestamp
);
alter table la_obra_v2.mail_settings enable row level security;

create or replace function la_obra_v2.configurar_correo(p_api_key text, p_sender_email text,
  p_sender_name text default 'La Obra', p_app_url text default null)
returns text language plpgsql as $$
begin
  if coalesce(btrim(p_api_key), '') = '' then raise exception 'Falta la clave de Brevo (empieza con xkeysib-)'; end if;
  if not la_obra_v2.valid_email(btrim(coalesce(p_sender_email, ''))) then raise exception 'El correo remitente no es válido'; end if;
  insert into la_obra_v2.mail_settings(id, brevo_api_key, sender_email, sender_name, app_url, updated_at)
  values (1, btrim(p_api_key), btrim(p_sender_email), coalesce(nullif(btrim(p_sender_name), ''), 'La Obra'), nullif(btrim(coalesce(p_app_url, '')), ''), localtimestamp)
  on conflict (id) do update set brevo_api_key = excluded.brevo_api_key, sender_email = excluded.sender_email,
    sender_name = excluded.sender_name, app_url = coalesce(excluded.app_url, la_obra_v2.mail_settings.app_url), updated_at = localtimestamp;
  return 'Correo configurado. Remitente: ' || btrim(p_sender_email) || '. Pruébalo con: select la_obra_v2.probar_correo(''tu-correo@ejemplo.com'');';
end $$;

-- Texto seguro dentro de HTML
create or replace function la_obra_v2.html_esc(p text)
returns text language sql immutable as $$
  select replace(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
$$;

-- j•••@gmail.com
create or replace function la_obra_v2.mask_email(e text)
returns text language sql immutable as $$
  select case when position('@' in coalesce(e, '')) > 1
    then left(e, 1) || '•••' || substr(e, position('@' in e)) else '•••' end;
$$;

-- Plantilla sencilla para todos los correos
create or replace function la_obra_v2.mail_html(p_title text, p_body text)
returns text language sql stable as $$
  select '<div style="background:#f4f1ec;padding:24px 12px;font-family:Arial,Helvetica,sans-serif;color:#1f2328">'
      || '<div style="max-width:480px;margin:0 auto;background:#fff;border-radius:14px;padding:28px 26px;border:1px solid #e7e1d8">'
      || '<div style="display:inline-block;background:#1f2328;color:#fff;font-weight:700;border-radius:10px;padding:8px 10px;font-size:14px">LO</div>'
      || '<span style="font-weight:700;font-size:16px;margin-left:8px;vertical-align:middle">La Obra</span>'
      || '<h1 style="font-size:20px;margin:22px 0 10px">' || la_obra_v2.html_esc(p_title) || '</h1>'
      || p_body
      || '</div><p style="text-align:center;font-size:12px;color:#8a8379;margin-top:14px">Este correo se envió automáticamente desde La Obra.</p></div>';
$$;

-- Envía un correo con la API de Brevo. Nunca lanza error: devuelve {sent: true} o {sent: false, error}.
create or replace function la_obra_v2.send_mail(p_to text, p_to_name text, p_subject text, p_html text, p_text text default null)
returns jsonb language plpgsql as $$
declare s la_obra_v2.mail_settings; v_status int; v_content text; v_body jsonb;
begin
  select * into s from la_obra_v2.mail_settings where id = 1;
  if s.id is null or coalesce(s.brevo_api_key, '') = '' or coalesce(s.sender_email, '') = '' then
    return jsonb_build_object('sent', false, 'error', 'El envío de correos no está configurado (falta la clave de Brevo)');
  end if;
  if not exists (select 1 from pg_extension where extname = 'http') then
    return jsonb_build_object('sent', false, 'error', 'Activa la extensión "http" en Supabase (Database → Extensions → http)');
  end if;
  v_body := jsonb_build_object(
    'sender', jsonb_build_object('name', s.sender_name, 'email', s.sender_email),
    'to', jsonb_build_array(jsonb_build_object('email', p_to, 'name', coalesce(nullif(btrim(coalesce(p_to_name, '')), ''), p_to))),
    'subject', p_subject,
    'htmlContent', p_html)
    || case when p_text is not null then jsonb_build_object('textContent', p_text) else '{}'::jsonb end;
  begin
    begin
      execute 'select extensions.http_set_curlopt(''CURLOPT_TIMEOUT_MS'', ''12000'')';
    exception when others then null;
    end;
    execute 'select (h).status, (h).content from (select extensions.http((''POST'', $1,
        array[extensions.http_header(''api-key'', $2), extensions.http_header(''accept'', ''application/json'')],
        ''application/json'', $3)::extensions.http_request) h) x'
      into v_status, v_content using 'https://api.brevo.com/v3/smtp/email', s.brevo_api_key, v_body::text;
  exception when others then
    return jsonb_build_object('sent', false, 'error', 'No se pudo conectar con Brevo: ' || left(sqlerrm, 200));
  end;
  if v_status between 200 and 299 then return jsonb_build_object('sent', true); end if;
  return jsonb_build_object('sent', false, 'error', 'Brevo respondió ' || coalesce(v_status::text, '?') || ': ' || left(coalesce(v_content, ''), 200));
end $$;

create or replace function la_obra_v2.probar_correo(p_to text)
returns text language plpgsql as $$
declare r jsonb;
begin
  r := la_obra_v2.send_mail(p_to, null, 'Prueba de correo · La Obra',
    la_obra_v2.mail_html('¡Funciona!', '<p style="font-size:15px;line-height:1.5">Si estás leyendo esto, La Obra ya puede mandar correos (recuperar contraseña y datos de acceso de usuarios nuevos).</p>'),
    'Si estás leyendo esto, La Obra ya puede mandar correos.');
  if (r ->> 'sent')::boolean then return 'Correo de prueba enviado a ' || p_to || '. Revisa también la carpeta de spam.'; end if;
  return 'No se envió: ' || (r ->> 'error');
end $$;

-- Dirección de la app para los botones de los correos (si se configuró)
create or replace function la_obra_v2.mail_app_button(p_label text)
returns text language sql stable as $$
  select coalesce((select '<p style="margin:22px 0 6px"><a href="' || la_obra_v2.html_esc(app_url) || '" style="background:#1f2328;color:#fff;text-decoration:none;padding:12px 18px;border-radius:10px;font-weight:700;display:inline-block">'
                          || la_obra_v2.html_esc(p_label) || '</a></p>'
                     from la_obra_v2.mail_settings where id = 1 and app_url is not null), '');
$$;

-- Correo con los datos de acceso (cuenta nueva o contraseña restablecida por el administrador)
create or replace function la_obra_v2.mail_access(p_name text, p_username text, p_email text, p_password text, p_new boolean)
returns jsonb language plpgsql as $$
declare v_html text; v_text text;
begin
  v_html := la_obra_v2.mail_html(
    case when p_new then 'Bienvenido(a), ' || p_name else 'Tus nuevos datos de acceso' end,
    '<p style="font-size:15px;line-height:1.5">' || case when p_new
        then 'Se creó tu cuenta en <b>La Obra</b>. Estos son tus datos para entrar:'
        else 'El administrador restableció tu acceso a <b>La Obra</b>. Estos son tus datos:' end || '</p>'
    || '<table style="width:100%;border-collapse:collapse;margin:14px 0;font-size:15px">'
    || '<tr><td style="padding:8px 0;color:#6b645b">Usuario</td><td style="padding:8px 0;text-align:right"><b>' || la_obra_v2.html_esc(p_username) || '</b></td></tr>'
    || '<tr><td style="padding:8px 0;color:#6b645b;border-top:1px solid #eee">Correo</td><td style="padding:8px 0;text-align:right;border-top:1px solid #eee"><b>' || la_obra_v2.html_esc(p_email) || '</b></td></tr>'
    || '<tr><td style="padding:8px 0;color:#6b645b;border-top:1px solid #eee">Contraseña temporal</td><td style="padding:8px 0;text-align:right;border-top:1px solid #eee"><b style="font-family:monospace;font-size:17px;letter-spacing:1px">' || la_obra_v2.html_esc(p_password) || '</b></td></tr>'
    || '</table>'
    || '<p style="font-size:14px;line-height:1.5;color:#4a443d">Puedes entrar con tu usuario o con tu correo. La primera vez se te pedirá crear tu propia contraseña.</p>'
    || la_obra_v2.mail_app_button('Abrir La Obra'));
  v_text := 'Usuario: ' || p_username || E'\nCorreo: ' || p_email || E'\nContraseña temporal: ' || p_password
         || E'\nPuedes entrar con tu usuario o con tu correo. La primera vez se te pedirá crear tu propia contraseña.';
  return la_obra_v2.send_mail(p_email, p_name,
    case when p_new then 'Tu cuenta de La Obra' else 'Tus nuevos datos de acceso a La Obra' end, v_html, v_text);
end $$;

-- Contraseña temporal fácil de dictar: 4 letras + 4 números (sin letras que se confunden)
create or replace function la_obra_v2.temp_password()
returns text language plpgsql volatile as $$
declare letters text := 'abcdefghjkmnpqrstuvwxyz'; v text := ''; bytes bytea := extensions.gen_random_bytes(8); i int;
begin
  for i in 0..3 loop v := v || substr(letters, (get_byte(bytes, i) % length(letters)) + 1, 1); end loop;
  v := upper(left(v, 1)) || substr(v, 2);
  for i in 4..7 loop v := v || (get_byte(bytes, i) % 10)::text; end loop;
  return v;
end $$;

-- =====================================================================
-- 2. Iniciar sesión con usuario o correo
-- =====================================================================
create or replace function la_obra_v2.find_login(p_login text)
returns la_obra_v2.users language sql stable as $$
  select u.* from la_obra_v2.users u
   where u.username = btrim(p_login) or lower(u.email) = lower(btrim(p_login))
   order by (u.username = btrim(p_login)) desc, u.id limit 1;
$$;

create or replace function la_obra_v2.ep_auth__login(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_user text; v_pass text; u la_obra_v2.users; v_token text;
begin
  perform la_obra_v2.method(m, 'POST');
  v_user := la_obra_v2.jstr(b -> 'username');
  v_pass := coalesce(la_obra_v2.jtext(b -> 'password'), '');
  if v_user = '' or v_pass = '' then perform la_obra_v2.fail(422, 'Usuario y contraseña son obligatorios'); end if;
  u := la_obra_v2.find_login(v_user);
  if u.id is null or not la_obra_v2.check_password(v_pass, u.password_hash) then
    perform la_obra_v2.fail(401, 'Usuario o contraseña incorrectos');
  end if;
  if u.status <> 'active' then perform la_obra_v2.fail(403, 'La cuenta no tiene acceso al sistema'); end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into la_obra_v2.sessions(user_id, token_hash, expires_at)
  values (u.id, la_obra_v2.sha256(v_token), localtimestamp + interval '8 hours');
  delete from la_obra_v2.sessions where expires_at < localtimestamp - interval '1 day';
  return la_obra_v2.ok(200, 'Inicio de sesión correcto', jsonb_build_object('token', v_token,
    'user', jsonb_build_object('id', u.id, 'name', u.name, 'username', u.username, 'email', u.email,
                               'role', u.role, 'must_change_password', u.must_change_password, 'avatar_path', u.avatar_path)));
end $$;

-- =====================================================================
-- 3. Recuperar contraseña con un código por correo
-- =====================================================================
create table if not exists la_obra_v2.password_resets (
  id         serial primary key,
  user_id    int not null references la_obra_v2.users(id) on update cascade on delete cascade,
  code_hash  text not null,
  expires_at timestamp not null,
  attempts   int not null default 0,
  used_at    timestamp null,
  created_at timestamp not null default localtimestamp
);
create index if not exists idx_password_resets_user on la_obra_v2.password_resets(user_id);
alter table la_obra_v2.password_resets enable row level security;

-- auth/forgot-password.php · POST { login: usuario o correo }
create or replace function la_obra_v2.ep_auth__forgot_password(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_login text; u la_obra_v2.users; v_code text; v_mail jsonb; v_recent int; v_rand bytea;
begin
  perform la_obra_v2.method(m, 'POST');
  b := la_obra_v2.body(b);
  v_login := la_obra_v2.jstr(b -> 'login');
  if v_login = '' then perform la_obra_v2.fail(422, 'Escribe tu usuario o tu correo'); end if;
  u := la_obra_v2.find_login(v_login);
  -- No se dice si la cuenta existe: el mensaje es el mismo
  if u.id is null or u.status <> 'active' then
    return la_obra_v2.ok(200, 'Si la cuenta existe y está activa, enviamos un código a su correo. Revisa también la carpeta de spam.',
      jsonb_build_object('email_hint', null));
  end if;
  select count(*) into v_recent from la_obra_v2.password_resets where user_id = u.id and created_at > localtimestamp - interval '15 minutes';
  if v_recent >= 3 then
    perform la_obra_v2.fail(429, 'Ya se enviaron 3 códigos en los últimos 15 minutos. Usa el último que te llegó o espera un poco.');
  end if;
  v_rand := extensions.gen_random_bytes(4);
  v_code := lpad(((get_byte(v_rand, 0)::bigint * 16777216 + get_byte(v_rand, 1) * 65536 + get_byte(v_rand, 2) * 256 + get_byte(v_rand, 3)) % 1000000)::text, 6, '0');
  update la_obra_v2.password_resets set used_at = localtimestamp where user_id = u.id and used_at is null;
  insert into la_obra_v2.password_resets(user_id, code_hash, expires_at)
  values (u.id, la_obra_v2.sha256(u.id || ':' || v_code), localtimestamp + interval '15 minutes');
  v_mail := la_obra_v2.send_mail(u.email, u.name, 'Tu código para recuperar la contraseña · La Obra',
    la_obra_v2.mail_html('Recuperar contraseña',
      '<p style="font-size:15px;line-height:1.5">Hola ' || la_obra_v2.html_esc(u.name) || ', pediste cambiar tu contraseña de <b>La Obra</b> (usuario <b>' || la_obra_v2.html_esc(u.username) || '</b>). Escribe este código en la app:</p>'
      || '<div style="font-family:monospace;font-size:34px;font-weight:700;letter-spacing:8px;text-align:center;background:#f4f1ec;border-radius:12px;padding:16px 0;margin:18px 0">' || v_code || '</div>'
      || '<p style="font-size:14px;color:#4a443d;line-height:1.5">Vence en 15 minutos. Si no fuiste tú, ignora este correo: tu contraseña no cambia.</p>'),
    'Tu código para recuperar la contraseña de La Obra es ' || v_code || '. Vence en 15 minutos.');
  if not coalesce((v_mail ->> 'sent')::boolean, false) then
    perform la_obra_v2.fail(503, 'No se pudo enviar el correo. Pide al administrador que revise la configuración del correo. (' || (v_mail ->> 'error') || ')');
  end if;
  return la_obra_v2.ok(200, 'Te enviamos un código de 6 dígitos a ' || la_obra_v2.mask_email(u.email) || '. Vence en 15 minutos.',
    jsonb_build_object('email_hint', la_obra_v2.mask_email(u.email)));
end $$;

-- auth/reset-password.php · POST { login, code, new_password }
-- Los intentos fallidos se guardan (por eso devuelve el error con ok() en lugar de fail(), que desharía el conteo).
create or replace function la_obra_v2.ep_auth__reset_password(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_login text; v_code text; v_new text; u la_obra_v2.users; r la_obra_v2.password_resets;
begin
  perform la_obra_v2.method(m, 'POST');
  b := la_obra_v2.body(b);
  v_login := la_obra_v2.jstr(b -> 'login');
  v_code := regexp_replace(la_obra_v2.jstr(b -> 'code'), '\D', '', 'g');
  v_new := coalesce(la_obra_v2.jtext(b -> 'new_password'), '');
  if v_login = '' or v_code = '' then perform la_obra_v2.fail(422, 'Escribe tu usuario o correo y el código que te llegó'); end if;
  if octet_length(v_new) < 8 then perform la_obra_v2.fail(422, 'La nueva contraseña debe tener al menos 8 caracteres'); end if;
  u := la_obra_v2.find_login(v_login);
  if u.id is null or u.status <> 'active' then perform la_obra_v2.fail(400, 'El código no es válido o ya venció. Pide uno nuevo.'); end if;
  select * into r from la_obra_v2.password_resets
   where user_id = u.id and used_at is null and expires_at > localtimestamp order by id desc limit 1 for update;
  if r.id is null then perform la_obra_v2.fail(400, 'El código no es válido o ya venció. Pide uno nuevo.'); end if;
  if r.attempts >= 5 then
    update la_obra_v2.password_resets set used_at = localtimestamp where id = r.id;
    return la_obra_v2.ok(429, 'Demasiados intentos con ese código. Pide uno nuevo.');
  end if;
  if r.code_hash <> la_obra_v2.sha256(u.id || ':' || v_code) then
    update la_obra_v2.password_resets set attempts = attempts + 1 where id = r.id;
    return la_obra_v2.ok(400, 'El código no es correcto. ' || case when 4 - r.attempts > 0
      then 'Te quedan ' || (4 - r.attempts) || ' intento(s).' else 'Pide un código nuevo.' end);
  end if;
  update la_obra_v2.users set password_hash = la_obra_v2.hash_password(v_new), must_change_password = false, updated_at = localtimestamp where id = u.id;
  update la_obra_v2.password_resets set used_at = localtimestamp where user_id = u.id and used_at is null;
  delete from la_obra_v2.sessions where user_id = u.id;
  return la_obra_v2.ok(200, 'Listo, tu contraseña se cambió. Ya puedes iniciar sesión.', jsonb_build_object('username', u.username));
end $$;

-- =====================================================================
-- 4. Alta de usuarios: el administrador la crea y la persona recibe sus datos por correo
-- =====================================================================
-- users/create.php · POST { name, username, email, role, password? }
create or replace function la_obra_v2.ep_users__create(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare v_name text; v_username text; v_email text; v_role text; v_tmp text; v_id int; v_mail jsonb; v_sent boolean;
begin
  perform la_obra_v2.method(m, 'POST');
  perform la_obra_v2.auth_long(t, true);
  v_name := la_obra_v2.jstr(b -> 'name'); v_username := la_obra_v2.jstr(b -> 'username');
  v_email := lower(la_obra_v2.jstr(b -> 'email')); v_role := la_obra_v2.jstr(b -> 'role');
  if v_name = '' or v_username = '' or v_email = '' or v_role = '' then perform la_obra_v2.fail(422, 'Todos los campos son obligatorios'); end if;
  if v_username ~ '\s' then perform la_obra_v2.fail(422, 'El usuario no puede llevar espacios'); end if;
  if not la_obra_v2.valid_email(v_email) then perform la_obra_v2.fail(422, 'El correo electrónico no es válido'); end if;
  if v_role not in ('admin','employee') then perform la_obra_v2.fail(422, 'El rol no es válido'); end if;
  if exists(select 1 from la_obra_v2.users where lower(username) = lower(v_username) or lower(email) = v_email) then
    perform la_obra_v2.fail(409, 'El nombre de usuario o correo ya está registrado');
  end if;
  v_tmp := coalesce(la_obra_v2.jtext(b -> 'password'), '');
  if v_tmp = '' then v_tmp := la_obra_v2.temp_password();
  elsif octet_length(v_tmp) < 8 then perform la_obra_v2.fail(422, 'La contraseña debe tener al menos 8 caracteres (o déjala vacía para generar una)');
  end if;
  insert into la_obra_v2.users(name, username, email, password_hash, status, role, must_change_password)
  values (v_name, v_username, v_email, la_obra_v2.hash_password(v_tmp), 'active', v_role, true) returning id into v_id;
  v_mail := la_obra_v2.mail_access(v_name, v_username, v_email, v_tmp, true);
  v_sent := coalesce((v_mail ->> 'sent')::boolean, false);
  return la_obra_v2.ok(201, case when v_sent then 'Usuario creado. Le enviamos sus datos de acceso a ' || v_email
                                 else 'Usuario creado, pero no se pudo enviar el correo: compártele los datos tú.' end,
    jsonb_build_object(
      'user', jsonb_build_object('id', v_id, 'name', v_name, 'username', v_username, 'email', v_email, 'role', v_role, 'status', 'active', 'must_change_password', true),
      'temporary_password', v_tmp, 'email_sent', v_sent, 'email_error', v_mail ->> 'error'));
end $$;

-- users/resend-access.php · POST { id } · nueva contraseña temporal y se la manda por correo
create or replace function la_obra_v2.ep_users__resend_access(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare me la_obra_v2.users; u la_obra_v2.users; v_tmp text; v_mail jsonb; v_sent boolean;
begin
  perform la_obra_v2.method(m, 'POST');
  me := la_obra_v2.auth_long(t, true, 'Solo un administrador puede reenviar accesos');
  b := la_obra_v2.body(b);
  select * into u from la_obra_v2.users where id = la_obra_v2.positive_id(b -> 'id', 'El id del usuario no es válido') for update;
  if u.id is null then perform la_obra_v2.fail(404, 'Usuario no encontrado'); end if;
  if u.id = me.id then perform la_obra_v2.fail(422, 'Para tu propia cuenta usa Mi perfil → Cambiar contraseña'); end if;
  if u.status <> 'active' then perform la_obra_v2.fail(409, 'Activa la cuenta antes de reenviar el acceso'); end if;
  v_tmp := la_obra_v2.temp_password();
  update la_obra_v2.users set password_hash = la_obra_v2.hash_password(v_tmp), must_change_password = true, updated_at = localtimestamp where id = u.id;
  delete from la_obra_v2.sessions where user_id = u.id;
  v_mail := la_obra_v2.mail_access(u.name, u.username, u.email, v_tmp, false);
  v_sent := coalesce((v_mail ->> 'sent')::boolean, false);
  return la_obra_v2.ok(200, case when v_sent then 'Le enviamos una contraseña temporal nueva a ' || u.email
                                 else 'Se generó una contraseña temporal nueva, pero no se pudo enviar el correo: compártesela tú.' end,
    jsonb_build_object('user', jsonb_build_object('id', u.id, 'name', u.name, 'username', u.username, 'email', u.email),
      'temporary_password', v_tmp, 'email_sent', v_sent, 'email_error', v_mail ->> 'error'));
end $$;

-- =====================================================================
-- 5. Preferencias por pieza en los pedidos: "3 hamburguesas, 1 sin tomate"
--    order_items.notes = [{"quantity": 1, "note": "sin tomate"}, …] (la suma nunca pasa de la cantidad)
-- =====================================================================
alter table la_obra_v2.order_items add column if not exists notes jsonb null;

-- "1 sin tomate · 2 sin cebolla"
create or replace function la_obra_v2.notes_text(p jsonb)
returns text language sql immutable as $$
  select coalesce(string_agg((x ->> 'quantity') || ' ' || (x ->> 'note'), ' · ' order by n), '')
    from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) with ordinality a(x, n);
$$;

-- Guarda las preferencias que vienen en items[]. Un producto sin la llave "notes" conserva las que ya tenía.
-- Junta las repetidas ("sin tomate" + "Sin tomate") y las recorta a la cantidad del producto.
create or replace function la_obra_v2.order_apply_notes(p_order int, p_items jsonb)
returns void language plpgsql as $$
declare r record; it jsonb; n jsonb; v_list jsonb; v_has boolean; v_note text; v_q int; v_left int; v_out jsonb; e record; v_count int;
begin
  for r in select id, product_id, quantity, notes from la_obra_v2.order_items where order_id = p_order loop
    v_has := false;
    v_list := '[]'::jsonb;
    if jsonb_typeof(p_items) = 'array' then
      for it in select x from jsonb_array_elements(p_items) a(x) loop
        if jsonb_typeof(it) = 'object' and it ? 'notes' and coalesce(la_obra_v2.jtext(it -> 'product_id'), '') ~ '^\s*\d{1,9}\s*$'
           and btrim(la_obra_v2.jtext(it -> 'product_id'))::int = r.product_id then
          v_has := true;
          if jsonb_typeof(it -> 'notes') = 'array' then
            for n in select x from jsonb_array_elements(it -> 'notes') a(x) loop
              continue when jsonb_typeof(n) <> 'object';
              v_note := left(btrim(regexp_replace(coalesce(n ->> 'note', ''), '\s+', ' ', 'g')), 120);
              v_q := case when coalesce(la_obra_v2.jtext(n -> 'quantity'), '') ~ '^\s*\d{1,4}\s*$' then btrim(la_obra_v2.jtext(n -> 'quantity'))::int else 1 end;
              if v_note <> '' and v_q > 0 then v_list := v_list || jsonb_build_array(jsonb_build_object('quantity', v_q, 'note', v_note)); end if;
            end loop;
          end if;
        end if;
      end loop;
    end if;
    if not v_has then v_list := coalesce(r.notes, '[]'::jsonb); end if;

    v_out := '[]'::jsonb; v_left := r.quantity; v_count := 0;
    for e in
      select (array_agg(x ->> 'note' order by ord))[1] as note, sum((x ->> 'quantity')::int) as q, min(ord) as o
        from jsonb_array_elements(v_list) with ordinality a(x, ord)
       group by lower(x ->> 'note') order by min(ord)
    loop
      exit when v_left <= 0 or v_count >= 12;
      v_q := least(e.q, v_left);
      v_left := v_left - v_q;
      v_count := v_count + 1;
      v_out := v_out || jsonb_build_array(jsonb_build_object('quantity', v_q, 'note', e.note));
    end loop;
    update la_obra_v2.order_items set notes = nullif(v_out, '[]'::jsonb)
     where id = r.id and notes is distinct from nullif(v_out, '[]'::jsonb);
  end loop;
end $$;

-- =====================================================================
-- 6. Notas del equipo: qué compra cada quien, pendientes y recordatorios
-- =====================================================================
create table if not exists la_obra_v2.notes (
  id          serial primary key,
  title       varchar(200) not null,
  details     varchar(1000) null,
  assigned_to int null references la_obra_v2.users(id) on update cascade on delete set null,   -- null = cualquiera del equipo
  remind_at   timestamp null,
  repeat      text not null default 'none' check (repeat in ('none','daily','weekly')),
  status      text not null default 'pending' check (status in ('pending','done')),
  done_by     int null references la_obra_v2.users(id) on update cascade on delete set null,
  done_at     timestamp null,
  created_by  int null references la_obra_v2.users(id) on update cascade on delete set null,
  created_at  timestamp not null default localtimestamp,
  updated_at  timestamp not null default localtimestamp
);
create index if not exists idx_notes_status on la_obra_v2.notes(status, remind_at);
create index if not exists idx_notes_assigned on la_obra_v2.notes(assigned_to);
alter table la_obra_v2.notes enable row level security;

create or replace function la_obra_v2.note_json(p_id int)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', n.id, 'title', n.title, 'details', n.details,
    'assigned_to', n.assigned_to, 'assigned_name', ua.name,
    'remind_at', la_obra_v2.fmt_ts(n.remind_at), 'repeat', n.repeat, 'status', n.status,
    'done_by', n.done_by, 'done_by_name', ud.name, 'done_at', la_obra_v2.fmt_ts(n.done_at),
    'created_by', n.created_by, 'created_by_name', uc.name, 'created_at', la_obra_v2.fmt_ts(n.created_at),
    'overdue', n.status = 'pending' and n.remind_at is not null and n.remind_at <= localtimestamp)
  from la_obra_v2.notes n
  left join la_obra_v2.users ua on ua.id = n.assigned_to
  left join la_obra_v2.users ud on ud.id = n.done_by
  left join la_obra_v2.users uc on uc.id = n.created_by
  where n.id = p_id;
$$;

-- Fecha y hora de un recordatorio: 'YYYY-MM-DD HH:MM' (o con segundos, o con T)
create or replace function la_obra_v2.note_time(v jsonb)
returns timestamp language plpgsql as $$
declare s text := la_obra_v2.jstr(v); ts timestamp;
begin
  if s = '' then return null; end if;
  if s !~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?' then perform la_obra_v2.fail(422, 'La fecha del recordatorio no es válida'); end if;
  begin ts := replace(left(s, 19), 'T', ' ')::timestamp(0); exception when others then perform la_obra_v2.fail(422, 'La fecha del recordatorio no es válida'); end;
  return ts;
end $$;

-- notes/index.php · GET ?status=pending|done
create or replace function la_obra_v2.ep_notes__index(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_status text := coalesce(nullif(la_obra_v2.jstr(q -> 'status'), ''), 'pending'); v_notes jsonb;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  if v_status not in ('pending','done') then perform la_obra_v2.fail(422, 'El estado no es válido'); end if;
  if v_status = 'pending' then
    select coalesce(jsonb_agg(la_obra_v2.note_json(n.id) order by (n.remind_at is null), n.remind_at, n.created_at, n.id), '[]')
      into v_notes from la_obra_v2.notes n where n.status = 'pending';
  else
    select coalesce(jsonb_agg(la_obra_v2.note_json(x.id) order by x.done_at desc, x.id desc), '[]') into v_notes
      from (select id, done_at from la_obra_v2.notes where status = 'done' order by done_at desc nulls last, id desc limit 100) x;
  end if;
  return la_obra_v2.ok(200, 'Notas', jsonb_build_object(
    'notes', v_notes,
    'me', u.id,
    'people', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]')
                 from la_obra_v2.users where status = 'active' and role is not null),
    'counts', jsonb_build_object(
      'pending', (select count(*) from la_obra_v2.notes where status = 'pending'),
      'mine', (select count(*) from la_obra_v2.notes where status = 'pending' and (assigned_to = u.id
                 or (assigned_to is null and remind_at is not null and remind_at <= localtimestamp))))));
end $$;

-- notes/save.php · POST { id?, title, details?, assigned_to?, remind_at?, repeat? }
create or replace function la_obra_v2.ep_notes__save(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; v_id int; n la_obra_v2.notes; v_title text; v_details text; v_to int; v_at timestamp; v_rep text;
begin
  perform la_obra_v2.method(m, 'POST');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  v_title := la_obra_v2.jstr(b -> 'title');
  v_details := nullif(la_obra_v2.jstr(b -> 'details'), '');
  if v_title = '' then perform la_obra_v2.fail(422, 'Escribe qué hay que comprar o hacer'); end if;
  if char_length(v_title) > 200 then perform la_obra_v2.fail(422, 'El texto es demasiado largo (máximo 200 caracteres)'); end if;
  if char_length(coalesce(v_details, '')) > 1000 then perform la_obra_v2.fail(422, 'Los detalles son demasiado largos'); end if;
  v_to := null;
  if la_obra_v2.jtext(b -> 'assigned_to') is not null and la_obra_v2.jstr(b -> 'assigned_to') <> '' then
    v_to := la_obra_v2.positive_id(b -> 'assigned_to', 'La persona elegida no es válida');
    if not exists(select 1 from la_obra_v2.users where id = v_to and status = 'active') then
      perform la_obra_v2.fail(422, 'La persona elegida no tiene una cuenta activa');
    end if;
  end if;
  v_at := la_obra_v2.note_time(b -> 'remind_at');
  v_rep := coalesce(nullif(la_obra_v2.jstr(b -> 'repeat'), ''), 'none');
  if v_rep not in ('none','daily','weekly') then perform la_obra_v2.fail(422, 'La repetición no es válida'); end if;
  if v_rep <> 'none' and v_at is null then perform la_obra_v2.fail(422, 'Para repetir el recordatorio elige la fecha y hora'); end if;

  if la_obra_v2.jtext(b -> 'id') is not null and la_obra_v2.jstr(b -> 'id') <> '' then
    v_id := la_obra_v2.positive_id(b -> 'id', 'La nota no es válida');
    select * into n from la_obra_v2.notes where id = v_id for update;
    if n.id is null then perform la_obra_v2.fail(404, 'La nota ya no existe'); end if;
    if u.role <> 'admin' and n.created_by is distinct from u.id and n.assigned_to is distinct from u.id and n.assigned_to is not null then
      perform la_obra_v2.fail(403, 'Solo quien la creó, a quien se le asignó o un administrador pueden editarla');
    end if;
    update la_obra_v2.notes set title = v_title, details = v_details, assigned_to = v_to, remind_at = v_at, repeat = v_rep,
           updated_at = localtimestamp where id = v_id;
    return la_obra_v2.ok(200, 'Nota actualizada', jsonb_build_object('note', la_obra_v2.note_json(v_id)));
  end if;
  insert into la_obra_v2.notes(title, details, assigned_to, remind_at, repeat, created_by)
  values (v_title, v_details, v_to, v_at, v_rep, u.id) returning id into v_id;
  return la_obra_v2.ok(201, 'Nota agregada', jsonb_build_object('note', la_obra_v2.note_json(v_id)));
end $$;

-- notes/done.php · PATCH { id, done }
-- Si se repite (diario/semanal), "hecho" la deja pendiente para la siguiente vez.
create or replace function la_obra_v2.ep_notes__done(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; n la_obra_v2.notes; v_done boolean; v_next timestamp; v_step interval;
begin
  perform la_obra_v2.method(m, 'PATCH');
  u := la_obra_v2.auth(t);
  b := la_obra_v2.body(b);
  select * into n from la_obra_v2.notes where id = la_obra_v2.positive_id(b -> 'id', 'La nota no es válida') for update;
  if n.id is null then perform la_obra_v2.fail(404, 'La nota ya no existe'); end if;
  v_done := coalesce(la_obra_v2.jtext(b -> 'done'), 'true') not in ('false', '0');
  if not v_done then
    update la_obra_v2.notes set status = 'pending', done_by = null, done_at = null, updated_at = localtimestamp where id = n.id;
    return la_obra_v2.ok(200, 'Se regresó a pendientes', jsonb_build_object('note', la_obra_v2.note_json(n.id)));
  end if;
  if n.repeat <> 'none' and n.remind_at is not null then
    v_step := case when n.repeat = 'daily' then interval '1 day' else interval '7 days' end;
    v_next := n.remind_at + v_step;
    while v_next <= localtimestamp loop v_next := v_next + v_step; end loop;
    update la_obra_v2.notes set remind_at = v_next, done_by = u.id, done_at = localtimestamp, updated_at = localtimestamp where id = n.id;
    return la_obra_v2.ok(200, 'Listo. Se volverá a recordar el ' || to_char(v_next, 'DD/MM') || ' a las ' || to_char(v_next, 'HH24:MI'),
      jsonb_build_object('note', la_obra_v2.note_json(n.id)));
  end if;
  update la_obra_v2.notes set status = 'done', done_by = u.id, done_at = localtimestamp, updated_at = localtimestamp where id = n.id;
  return la_obra_v2.ok(200, 'Marcada como hecha', jsonb_build_object('note', la_obra_v2.note_json(n.id)));
end $$;

-- notes/delete.php · DELETE { id }
create or replace function la_obra_v2.ep_notes__delete(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users; n la_obra_v2.notes;
begin
  perform la_obra_v2.method(m, 'DELETE');
  u := la_obra_v2.auth(t);
  select * into n from la_obra_v2.notes where id = la_obra_v2.positive_id(coalesce(la_obra_v2.body(b) -> 'id', q -> 'id'), 'La nota no es válida');
  if n.id is null then perform la_obra_v2.fail(404, 'La nota ya no existe'); end if;
  if u.role <> 'admin' and n.created_by is distinct from u.id then
    perform la_obra_v2.fail(403, 'Solo quien la creó o un administrador pueden borrarla');
  end if;
  delete from la_obra_v2.notes where id = n.id;
  return la_obra_v2.ok(200, 'Nota eliminada');
end $$;

-- notes/reminders.php · GET · recordatorios pendientes que le tocan a quien pregunta (suyos o de todos)
-- hasta 7 días adelante, para avisar en la app y programar notificaciones del teléfono.
create or replace function la_obra_v2.ep_notes__reminders(m text, q jsonb, b jsonb, t text)
returns jsonb language plpgsql as $$
declare u la_obra_v2.users;
begin
  perform la_obra_v2.method(m, 'GET');
  u := la_obra_v2.auth(t);
  return la_obra_v2.ok(200, 'Recordatorios', jsonb_build_object(
    'server_time', la_obra_v2.fmt_ts(localtimestamp::timestamp(0)),
    'reminders', (select coalesce(jsonb_agg(la_obra_v2.note_json(n.id) order by n.remind_at, n.id), '[]')
                    from la_obra_v2.notes n
                   where n.status = 'pending' and n.remind_at is not null and n.remind_at <= localtimestamp + interval '7 days'
                     and (n.assigned_to = u.id or n.assigned_to is null)),
    'mine', (select count(*) from la_obra_v2.notes where status = 'pending' and (assigned_to = u.id
               or (assigned_to is null and remind_at is not null and remind_at <= localtimestamp)))));
end $$;

-- Las notas también van en el respaldo
create or replace function la_obra_v2.backup_tables()
returns text[] language sql immutable as $$
  select array['users','sessions','categories','payment_methods','inputs','input_units','products','preparations','preparation_inputs',
               'recipes','product_components','orders','order_items','payments','purchases','purchase_items','purchase_history',
               'expenses','expense_history','waste_records','inventory_movements','order_test_invoices','work_location','attendance',
               'notes'];
$$;
-- =====================================================================
-- 7. Funciones de pedidos que cambian (copias de 07 y 12 con las preferencias por pieza)
-- =====================================================================

-- (de 07_api_pedidos_ventas.sql)
create or replace function la_obra_v2.order_items_json(p_order int)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('product_id', oi.product_id, 'name', p.name, 'quantity', oi.quantity,
    'unit_price', oi.unit_price::float8, 'subtotal', oi.subtotal::float8,
    'notes', coalesce(oi.notes, '[]'::jsonb)) order by oi.id), '[]')
  from la_obra_v2.order_items oi join la_obra_v2.products p on p.id = oi.product_id where oi.order_id = p_order;
$$;

-- (de 07_api_pedidos_ventas.sql)
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
  -- Preferencias por pieza ("1 sin tomate"): ver 14_correo_notas_preferencias.sql
  perform la_obra_v2.order_apply_notes(v_order, b -> 'items');
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

-- (de 12_editar_pedidos.sql)
create or replace function la_obra_v2.order_edit_summary(a jsonb, z jsonb, adj jsonb default null)
returns text language plpgsql immutable as $$
declare parts text[] := '{}'; r record; pz jsonb := z -> 'payment'; v_t text; v_m text;
begin
  for r in
    select coalesce(x.pid, y.pid) as pid, coalesce(y.name, x.name) as name, coalesce(x.qty, 0) as q0, coalesce(y.qty, 0) as q1, x.ord as o0, y.ord as o1,
           coalesce(x.notes, '[]'::jsonb) as n0, coalesce(y.notes, '[]'::jsonb) as n1
      from (select (e ->> 'product_id')::int as pid, e ->> 'name' as name, (e ->> 'quantity')::int as qty, n as ord, e -> 'notes' as notes
              from jsonb_array_elements(coalesce(a -> 'items', '[]')) with ordinality s(e, n)) x
      full join (select (e ->> 'product_id')::int as pid, e ->> 'name' as name, (e ->> 'quantity')::int as qty, n as ord, e -> 'notes' as notes
              from jsonb_array_elements(coalesce(z -> 'items', '[]')) with ordinality s(e, n)) y on y.pid = x.pid
     order by (x.ord is null), x.ord, y.ord
  loop
    if r.q0 = 0 and r.q1 > 0 then parts := parts || ('Agregó ' || r.q1 || '× ' || r.name);
    elsif r.q1 = 0 and r.q0 > 0 then parts := parts || ('Quitó ' || r.q0 || '× ' || r.name);
    elsif r.q0 <> r.q1 then parts := parts || (r.name || ': ' || r.q0 || ' → ' || r.q1);
    end if;
    -- Preferencias por pieza ("1 sin tomate")
    if r.q1 > 0 and r.n0 is distinct from r.n1 then
      parts := parts || ('Preferencias de ' || r.name || ': ' || coalesce(nullif(la_obra_v2.notes_text(r.n1), ''), 'ninguna'));
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

-- (de 12_editar_pedidos.sql)
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
  -- Preferencias por pieza: se cambian solo si vienen; si no, se conservan (recortadas a la nueva cantidad)
  perform la_obra_v2.order_apply_notes(v_id, b -> 'items');
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

-- =====================================================================
-- 8. Permisos: las tablas nuevas tampoco se pueden leer con la clave pública
-- =====================================================================
revoke all on all tables in schema la_obra_v2 from public;
revoke all on all functions in schema la_obra_v2 from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all tables in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all functions in schema la_obra_v2 from anon, authenticated';
    execute 'revoke all on all sequences in schema la_obra_v2 from anon, authenticated';
  end if;
end $$;
notify pgrst, 'reload schema';
