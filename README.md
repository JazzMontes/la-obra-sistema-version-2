# La Obra · Sistema versión 2

Punto de venta, compras, inventario, costos, mermas, gastos y reportes para **La Obra**, ahora **en internet**:

- **Web**: GitHub Pages → `https://<tu-usuario>.github.io/la-obra-sistema-version-2/`
- **Android**: APK generado con Capacitor (app nueva: `com.laobra.sistema.v2`)
- **Base de datos y API**: Supabase (PostgreSQL), plan gratuito, sin tarjeta

Es la misma aplicación Ionic + Angular de la versión 1. Lo que cambió es **dónde vive el backend**: ya no depende de una computadora con XAMPP encendida.

> La versión 1 (XAMPP + MySQL `la_obra_db`) **no se toca**: este proyecto usa otro nombre, otra base de datos, otro identificador de app Android y otras claves en el almacenamiento del navegador. Las dos pueden convivir.

---

## Índice

1. [Qué cambió de la versión 1 a la 2](#1-qué-cambió-de-la-versión-1-a-la-2)
2. [Cómo funciona](#2-cómo-funciona)
3. [Paso a paso para publicarla](#3-paso-a-paso-para-publicarla)
4. [Generar el APK de Android](#4-generar-el-apk-de-android)
5. [Respaldos](#5-respaldos)
6. [Límites del plan gratuito](#6-límites-del-plan-gratuito)
7. [Estructura del proyecto](#7-estructura-del-proyecto)
8. [Problemas comunes](#8-problemas-comunes)

---

## 1. Qué cambió de la versión 1 a la 2

| | Versión 1 | Versión 2 |
|---|---|---|
| Nombre del proyecto | `la-obra-sistema` | `la-obra-sistema-version-2` |
| Base de datos | MySQL `la_obra_db` en XAMPP | PostgreSQL en Supabase, esquema **`la_obra_v2`** |
| Backend | ~96 archivos PHP en `backend/` | Las mismas operaciones como funciones SQL dentro de Supabase |
| Acceso | Solo en la misma red Wi-Fi que la computadora | Desde cualquier lugar con internet |
| Fotos (productos, tickets) | Carpeta `backend/uploads/` | Tabla `la_obra_v2.files` (misma ruta `uploads/...`) |
| Configuración de la app | IP de la computadora | Dirección y clave pública de Supabase |
| App Android | appId de la versión 1 | `com.laobra.sistema.v2` · nombre “La Obra v2” |
| Datos del navegador | `token`, `user`, `la_obra_…` | `la_obra_v2_token`, `la_obra_v2_user`, `la_obra_v2_…` |
| Respaldo | Exportar desde phpMyAdmin | Botón **Descargar respaldo** dentro de la app (+ restaurar) |

**Lo que se conserva igual:** todas las pantallas, las reglas del negocio (costos por última compra, recetas y preparaciones, inventario por kárdex, cortes, permisos de admin y empleado, historial de cambios en compras y gastos), los mensajes de error y las rutas internas (`products/index.php`, `orders/checkout.php`, …). Las pantallas no se reescribieron: solo cambió el servicio que hace las peticiones.

**Usuarios y contraseñas:** se migran tal cual. Cada persona entra con el **mismo usuario y la misma contraseña** que usaba en la versión 1 (las contraseñas de PHP son compatibles).

### Sobre la autenticación

La propuesta original menciona el sistema de autenticación de Supabase (Supabase Auth). Esta versión guarda los usuarios, roles y sesiones **en la propia base de PostgreSQL de Supabase** (tablas `users` y `sessions`), igual que lo hacía la versión 1 en MySQL. Se eligió así porque:

- conserva el **inicio de sesión con nombre de usuario** (Supabase Auth trabaja con correo);
- permite que el administrador **cree cuentas con contraseña temporal** y apruebe o desactive empleados sin servidores extra (en Supabase Auth eso requiere funciones de servidor con la clave secreta);
- conserva las **contraseñas actuales** al migrar;
- no requiere configurar correos de confirmación.

La seguridad es equivalente: contraseñas con bcrypt, sesiones de 8 horas con token aleatorio (en la base solo se guarda su hash SHA-256) y ninguna tabla accesible directamente desde internet. Si más adelante quieres usar Supabase Auth, se puede cambiar solo la parte de `auth/*` sin tocar el resto.

---

## 2. Cómo funciona

```
 App web (GitHub Pages) ─┐
                         ├── HTTPS ──▶ Supabase ──▶ public.la_obra_v2_api(ruta, método, datos, token)
 App Android (APK) ──────┘                               │
                                                         ▼
                                       esquema la_obra_v2 (privado)
                                       ├── tablas: users, products, orders, purchases, …
                                       └── funciones ep_*: una por cada archivo PHP
                                           products/index.php → la_obra_v2.ep_products__index
```

- La app llama **siempre** a una sola función pública: `la_obra_v2_api`. Esa función ejecuta el “endpoint” equivalente al archivo PHP de antes.
- El esquema `la_obra_v2` **no está publicado** en la API de Supabase y tiene seguridad por fila activada sin permisos: nadie puede leer ni modificar tablas directamente, ni con la clave pública.
- Cada operación corre en una **transacción**: si algo falla a la mitad (por ejemplo, una venta), no queda nada a medias.
- Los reportes y el corte de caja se **calculan al momento** con todo el historial; no se guardan copias. El PDF se arma en la app cuando lo pides. **No se borra nada cada 32 días.**

---

## 3. Paso a paso para publicarla

### Paso 0 · Respaldar la versión 1

Antes de empezar:

1. En **phpMyAdmin** → base `la_obra_db` → **Exportar** → Rápido → SQL → Continuar. Guarda el archivo.
2. Copia la carpeta `C:\xampp\htdocs\la-obra-sistema\` completa (incluye `backend/uploads/` con las fotos) a una USB o a Drive.

### Paso 1 · Crear el proyecto en Supabase (gratis, sin tarjeta)

1. Entra a <https://supabase.com> → **Start your project** → inicia sesión con tu cuenta de GitHub.
2. **New project**:
   - **Name:** `la-obra-sistema-version-2`
   - **Database password:** genera una y **guárdala** (la necesitas solo para respaldos avanzados).
   - **Region:** la más cercana (por ejemplo *East US* o *West US*).
   - Plan: **Free**.
3. Espera 1–2 minutos a que se cree.

### Paso 2 · Instalar la base de datos y la API

1. En el proyecto: menú izquierdo → **SQL Editor** → **New query**.
2. Abre el archivo [`supabase/instalar_todo.sql`](supabase/instalar_todo.sql), copia **todo** su contenido, pégalo y presiona **Run**.
3. Debe terminar con *Success. No rows returned*. (Se puede volver a correr sin perder datos.)
4. *(Opcional, solo para la factura de prueba con Profact)*: **Database → Extensions** → busca **http** → actívala.

### Paso 3 · Pasar tus datos de la versión 1 (o crear el administrador)

**Opción A — migrar todo lo que ya tienes (recomendado):**

1. Copia [`herramientas/exportar_mysql_a_supabase.php`](herramientas/exportar_mysql_a_supabase.php) a la carpeta del backend de la versión 1, junto a `health.php`:
   `C:\xampp\htdocs\la-obra-sistema\backend\exportar_mysql_a_supabase.php`
2. Con Apache y MySQL encendidos, abre en esa computadora:
   `http://localhost/la-obra-sistema/backend/exportar_mysql_a_supabase.php`
3. Verás cuántos registros hay en cada tabla. Descarga **1 · Datos** y, si tienes fotos, **2 · Fotos**.
   *La herramienta solo lee la base de la versión 1; no cambia nada.*
4. En Supabase → **SQL Editor** → **New query**: pega el archivo de **datos** → **Run**. Después, en otra consulta, el de **fotos** → **Run**.
   Si el archivo de fotos es muy grande para el editor, divídelo en partes (cada línea `insert` es una foto) y córrelas por separado.
5. **No subas estos dos archivos a GitHub** (tienen información real del negocio; el `.gitignore` ya los excluye).

**Opción B — empezar desde cero:** en el SQL Editor ejecuta (con tus datos):

```sql
select la_obra_v2.crear_admin_inicial('Jazmin Montes', 'admin', 'tu-correo@ejemplo.com', 'UnaContraseñaSegura123');
```

### Paso 4 · Copiar la dirección y la clave pública

En Supabase → **Project Settings → API Keys** (o botón **Connect**):

- **Project URL**: `https://xxxxxxxxxxxx.supabase.co`
- **Clave pública**: la **Publishable key** (`sb_publishable_…`) o, en proyectos antiguos, la **anon public** (`eyJ…`).

> ⚠️ Nunca uses la clave **secret / service_role** en la app ni en GitHub.
> La clave pública sí puede ir en la app: por diseño solo permite llamar a `la_obra_v2_api`, que pide usuario y contraseña para todo lo demás.

### Paso 5 · Crear el repositorio en GitHub

1. En GitHub → **New repository**:
   - **Repository name:** `la-obra-sistema-version-2`
   - **Public** (GitHub Pages es gratis en repositorios públicos; el código no contiene datos del negocio).
   - Sin README (este proyecto ya trae uno).
2. En tu computadora, dentro de la carpeta de este proyecto:

   ```bash
   git remote add origin https://github.com/<tu-usuario>/la-obra-sistema-version-2.git
   git branch -M main
   git push -u origin main
   ```

   (Si descargaste el ZIP sin historial de git, corre antes: `git init && git add . && git commit -m "La Obra v2"`.)

### Paso 6 · Configurar y publicar en GitHub Pages

1. En el repositorio → **Settings → Secrets and variables → Actions → pestaña Variables → New repository variable**:
   - `SUPABASE_URL` = tu Project URL
   - `SUPABASE_KEY` = tu clave pública
2. **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. Pestaña **Actions** → **Publicar en GitHub Pages** → **Run workflow** (también corre solo con cada `git push`).
4. Cuando termine (≈3 min), la app queda en:
   **`https://<tu-usuario>.github.io/la-obra-sistema-version-2/`**

> Alternativa sin variables: escribe la URL y la clave en `src/environments/environment.prod.ts` y `environment.ts`, y súbelos.
> Además, en la pantalla de inicio de sesión → **Configura la conexión** se pueden escribir a mano en cada dispositivo.

### Paso 7 · Probar

1. Abre la dirección de GitHub Pages en la computadora y en el teléfono.
2. Inicia sesión. Haz una venta de prueba desde la web y verifica que aparece en el teléfono (y al revés).
3. En **Conexión y respaldo** → **Probar conexión** debe decir *Conectado · API disponible*.

---

## 4. Generar el APK de Android

Requisitos: Node.js 22, Android Studio (con un SDK de Android instalado).

```bash
npm install
# Si no usaste las variables de GitHub, configura Supabase para el APK:
#   (Windows PowerShell)  $env:SUPABASE_URL="https://xxxx.supabase.co"; $env:SUPABASE_KEY="sb_publishable_xxx"; node scripts/configurar-supabase.mjs
#   (macOS / Linux)       SUPABASE_URL=https://xxxx.supabase.co SUPABASE_KEY=sb_publishable_xxx node scripts/configurar-supabase.mjs
npx ng build
npx cap add android        # solo la primera vez: crea la carpeta android/ con el appId nuevo
npx cap sync android
npx cap open android
```

En Android Studio: **Build → Build App Bundle(s) / APK(s) → Build APK(s)**. El archivo queda en
`android/app/build/outputs/apk/debug/app-debug.apk`.

- Es una **app nueva** (`com.laobra.sistema.v2`, “La Obra v2”): se instala **junto** a la versión 1, no la reemplaza.
- No copies la carpeta `android/` de la versión 1: deja que `npx cap add android` cree una nueva.
- Cada vez que cambies el código: `npx ng build && npx cap sync android` y vuelve a generar el APK.

---

## 5. Respaldos

El plan gratuito de Supabase **no incluye respaldos automáticos descargables**, así que la app trae su propio respaldo:

- **Descargar:** menú → **Conexión y respaldo** → **Descargar respaldo** (solo administrador). Genera un archivo `.json` con toda la información y, si quieres, las fotos. Hazlo **una vez por semana** desde la **computadora** (en el APK la descarga depende del teléfono) y guárdalo en Drive o en una USB.
- **Restaurar:** misma pantalla → elige el archivo → **Restaurar**. Reemplaza toda la información actual por la del archivo (pide confirmación). Después hay que volver a iniciar sesión.
- **Respaldo avanzado (opcional):** con PostgreSQL instalado en tu computadora,
  `pg_dump "<cadena de conexión de Supabase → Connect → Session pooler>" -n la_obra_v2 -f respaldo.sql`.

> Los archivos de respaldo contienen información real (usuarios, ventas). **No los subas a GitHub.**

---

## 6. Límites del plan gratuito

Para 1 a 5 usuarios, 3–4 días por semana, el plan gratuito sobra. Aun así, conviene conocer sus límites (pueden cambiar; revisa supabase.com/pricing):

| Servicio | Límite gratuito | Qué significa para La Obra |
|---|---|---|
| Supabase · base de datos | 500 MB por proyecto | Años de ventas. Las fotos llegan comprimidas (≈100–200 KB). Revisa el uso en **Project Settings → Usage**. |
| Supabase · transferencia | 5 GB al mes | Suficiente para el uso diario de pocos usuarios. |
| Supabase · proyectos | 2 proyectos gratuitos activos | Este usa uno. |
| Supabase · inactividad | **Se pausa tras 7 días sin uso** | Con 3–4 días por semana de uso no debería pasar. Además, el flujo **Mantener Supabase activo** de GitHub lo “toca” cada 3 días. Si aun así se pausa: supabase.com → proyecto → **Restore project** (los datos no se pierden). |
| GitHub Pages | Repositorio público, 1 GB de sitio, 100 GB/mes | La app pesa unos pocos MB. |
| GitHub Actions | Gratis en repositorios públicos | GitHub desactiva los flujos programados tras 60 días sin cambios en el repo; si te avisa, vuelve a activarlo en **Actions**. |

Antes de usarla con información real, revisa que el respaldo semanal se descargue bien y que la restauración funcione (puedes probarla en un segundo proyecto de Supabase).

---

## 7. Estructura del proyecto

```
la-obra-sistema-version-2/
├── src/                          App Ionic + Angular (las mismas pantallas de la v1)
│   ├── app/services/api.ts           ← NUEVO: envía cada petición a Supabase (la_obra_v2_api)
│   ├── app/services/api-config.ts    ← NUEVO: dirección y clave de Supabase
│   ├── app/services/storage-keys.ts  ← NUEVO: nombres la_obra_v2_* en el dispositivo
│   ├── app/services/auth.ts, products.ts, product-sync.ts   (adaptados a api.ts)
│   ├── app/pages/login/              (conexión con Supabase en lugar de IP)
│   ├── app/pages/data-origins/       → pantalla “Conexión y respaldo”
│   └── environments/                 URL y clave pública de Supabase
├── supabase/
│   ├── instalar_todo.sql             ← lo único que hay que correr en Supabase
│   ├── 01_esquema.sql                tablas (conversión de schema.sql + migraciones de MySQL)
│   ├── 02_nucleo.sql                 validaciones, sesión, costos, inventario (antes config/*.php)
│   ├── 03 … 09_api_*.sql             un endpoint por cada archivo PHP
│   └── 10_api_publica_y_permisos.sql función pública, permisos y datos iniciales
├── herramientas/
│   └── exportar_mysql_a_supabase.php migra datos y fotos desde XAMPP (solo lectura)
├── scripts/configurar-supabase.mjs   escribe la URL y la clave en environments/
├── .github/workflows/
│   ├── publicar-pages.yml            compila y publica en GitHub Pages
│   └── mantener-activo.yml           evita que Supabase pause el proyecto
├── capacitor.config.ts               appId com.laobra.sistema.v2
└── package.json, angular.json, ionic.config.json, tsconfig*.json
```

### Equivalencia de endpoints

Cada archivo `backend/<carpeta>/<archivo>.php` de la versión 1 es ahora la función
`la_obra_v2.ep_<carpeta>__<archivo>` (los guiones pasan a guion bajo). Ejemplos:

| Versión 1 (PHP) | Versión 2 (función SQL) |
|---|---|
| `auth/login.php` | `ep_auth__login` |
| `orders/checkout.php` | `ep_orders__checkout` |
| `products/save-components.php` | `ep_products__save_components` |
| `reports/summary.php` | `ep_reports__summary` |
| `files/image.php` | `ep_files__image` |
| *(nuevo)* | `ep_backup__export`, `ep_backup__import` |

Los 96 endpoints de la versión 1 están portados. Las subidas de fotos ya no usan `multipart/form-data`: la app envía la foto comprimida como *data URL* y la base valida que realmente sea JPG, PNG o WEBP (máximo 3 MB).

### Desarrollo local

```bash
npm install
npx ng serve        # http://localhost:4200  (usa src/environments/environment.ts)
```

---

## 8. Problemas comunes

| Mensaje | Solución |
|---|---|
| *La base de datos de Supabase no tiene instalada la API de La Obra v2* | Corre `supabase/instalar_todo.sql` en el SQL Editor (Paso 2). |
| *La clave de Supabase no es válida* | Revisa la clave pública en **Conexión y respaldo** o en las variables del repositorio. |
| *No hay respuesta de Supabase* | Revisa el internet. Si el proyecto dice **Paused** en supabase.com, presiona **Restore project**. |
| *Usuario o contraseña incorrectos* tras migrar | Revisa que corriste el archivo de datos; los usuarios conservan su contraseña de la v1. |
| La página de GitHub Pages sale en blanco | Revisa que **Settings → Pages → Source** sea **GitHub Actions** y que el flujo terminó en verde. |
| Factura de prueba: *Activa la extensión "http"* | Supabase → **Database → Extensions → http** → activar. |
| **Validar estudiante** no responde | Esa pantalla llama al servicio de Control Escolar en `http://192.168.1.158`, que solo existe en la red local y no tiene HTTPS. Desde GitHub Pages o el APK v2 el navegador bloquea esa conexión. Funcionará cuando ese servicio esté publicado con HTTPS (cambia la dirección en `src/app/services/control-escolar.ts`). |

---

Hecho para el proyecto escolar **La Obra** · versión 2 (Supabase + GitHub Pages).
