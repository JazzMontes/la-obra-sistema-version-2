# La Obra · versión 2 (Supabase + GitHub Pages)

Punto de venta, compras, inventario, costos, mermas, gastos, reportes y **asistencia con GPS** de La Obra, ahora **sin servidor PHP**:

- **Base de datos y API:** Supabase (PostgreSQL), plan gratuito.
- **Web:** GitHub Pages → `https://<tu-usuario>.github.io/<repositorio>/`
- **Android:** el mismo APK de Capacitor, apuntando a Supabase.

Ya no hace falta tener XAMPP encendido ni estar en la misma red Wi-Fi.

---

## 1. Qué cambió

| | Versión 1 | Versión 2 |
|---|---|---|
| Base de datos | MySQL `la_obra_db` (XAMPP) | PostgreSQL en Supabase, esquema privado **`la_obra_v2`** |
| Backend | ~100 archivos PHP en `backend/` | Las mismas rutas como **funciones SQL** dentro de Supabase |
| Fotos | carpeta `backend/uploads/` | tabla `la_obra_v2.files` (misma ruta `uploads/...`) |
| Configuración | `apiUrl` (IP o dominio) | `supabaseUrl` + clave pública |
| Respaldo | phpMyAdmin | botón **Descargar respaldo** en la pantalla *Servidor* |

**Lo que no cambió:** todas las pantallas, reglas del negocio, mensajes de error, permisos de admin/empleado y las rutas internas (`products/index.php`, `orders/checkout.php`…). Las pantallas no se reescribieron: `src/app/services/supabase-bridge.ts` intercepta esas peticiones y las manda a Supabase.

**Usuarios:** al migrar, cada persona entra con **el mismo usuario y contraseña** que en la v1.

### Cómo funciona

```
App (GitHub Pages o APK)
   │  axios.get('.../products/index.php')
   ▼
supabase-bridge.ts ──HTTPS──▶ Supabase ──▶ public.la_obra_v2_api(path, method, query, body, token)
                                                 │
                                                 ▼
                                  la_obra_v2.ep_products__index(...)   (una función por cada PHP)
                                  tablas privadas: users, products, orders, …
```

- La clave pública **solo** puede llamar a `la_obra_v2_api`; las tablas tienen seguridad por fila y ningún permiso. Para todo lo demás se necesita iniciar sesión (usuario y contraseña de La Obra).
- Cada petición es una **transacción**: si algo falla a la mitad (una venta), no queda nada a medias.

---

## Actualización (noviembre 2026)

Para aplicarla en tu Supabase: **SQL Editor → New query → pega `supabase/instalar_todo.sql` → Run**. Solo agrega columnas y una tabla (`input_units`); no borra ni modifica tus datos. Luego `git push` como siempre.

| Mejora | Dónde |
|---|---|
| El navegador ofrece guardar y rellenar usuario y contraseña | Inicio de sesión |
| Foto de perfil de cada usuario | Mi perfil (se ve en el menú y en Usuarios) |
| Mapa de calles con el negocio, el radio y tu ubicación (OpenStreetMap) + "Abrir en Google Maps" | Asistencia |
| Comisión de la terminal (Tarjeta = 4 %, editable) al cobrar y en Reportes | Métodos de pago, Punto de venta, Pedidos, Reportes |
| Buscar insumos y preparaciones escribiendo su nombre | Preparaciones, Productos (receta), Compras, Mermas |
| Otras medidas por insumo (ej. tomate por pieza o por g; mostaza por g o por cucharada) | Insumos → Otras medidas |
| Registrar un insumo nuevo sin salir de la preparación | Preparaciones |
| Se quitó "Siempre / Solo para llevar / Solo comer aquí" de la receta | Productos |
| Capturar lo que hay hoy de varios insumos, sin costos | Inventario → Capturar existencias |

---

## 2. Publicarla, paso a paso

### Paso 0 · Respaldar la versión 1
phpMyAdmin → `la_obra_db` → **Exportar**. Copia también `C:\xampp\htdocs\la-obra-sistema\backend\uploads\`.

### Paso 1 · Crear el proyecto en Supabase (gratis)
1. <https://supabase.com> → **Start your project** → entra con tu cuenta de GitHub.
2. **New project** → nombre `la-obra`, genera y guarda la contraseña de la base, región cercana (East US / West US), plan **Free**.

### Paso 2 · Instalar la base de datos y la API
1. Menú izquierdo → **SQL Editor** → **New query**.
2. Abre [`supabase/instalar_todo.sql`](supabase/instalar_todo.sql), copia **todo**, pégalo y presiona **Run**.
3. Al final debe decir *La Obra v2 instalada: 101 rutas de la API*. Se puede volver a correr sin perder datos.
4. *(Opcional, solo para la factura de prueba)* **Database → Extensions → http** → activar.

### Paso 3 · Pasar tus datos (o crear el administrador)

**A) Migrar lo que ya tienes en XAMPP (recomendado):**
1. Copia [`herramientas/exportar_mysql_a_supabase.php`](herramientas/exportar_mysql_a_supabase.php) a `C:\xampp\htdocs\la-obra-sistema\backend\`.
2. Con Apache y MySQL encendidos abre `http://localhost/la-obra-sistema/backend/exportar_mysql_a_supabase.php`.
3. Descarga **1 · Datos** y, si aparece, **2 · Fotos**.
4. Supabase → SQL Editor → New query → pega el de datos → **Run**. Luego el de fotos → **Run** (si es muy grande, córrelo por partes: cada línea es una foto).
5. **No subas esos archivos a GitHub.**

**B) Empezar desde cero:**
```sql
select la_obra_v2.crear_admin_inicial('Jazmin Montes', 'admin', 'tu-correo@ejemplo.com', 'UnaContraseñaSegura123');
```

### Paso 4 · Copiar la dirección y la clave pública
Supabase → **Project Settings → API Keys** (o el botón **Connect**):
- **Project URL:** `https://xxxxxxxx.supabase.co`
- **Publishable key:** `sb_publishable_…` (en proyectos antiguos, la *anon public* `eyJ…`)

> ⚠️ Nunca uses la **secret / service_role** en la app ni en GitHub. La pública sí puede ir en la app.

### Paso 5 · Juntar este paquete con tu proyecto Ionic
En la carpeta de tu proyecto (donde están `package.json`, `angular.json`, `capacitor.config.ts`):
1. Reemplaza tu carpeta **`src/`** por la de este paquete.
2. Copia también `supabase/`, `herramientas/`, `scripts/` y `.github/`.
3. Agrega a tu `.gitignore` las líneas de `.gitignore.agregar`.
4. Abre `src/environments/environment.ts` y `environment.prod.ts` y pega tu `supabaseUrl` y `supabaseKey`.
5. Prueba en tu computadora: `npm install` y `npx ng serve`.

### Paso 6 · Subir a GitHub y publicar en GitHub Pages
1. GitHub → **New repository** (público, sin README) → súbelo:
   ```bash
   git init && git add . && git commit -m "La Obra v2"
   git branch -M main
   git remote add origin https://github.com/<tu-usuario>/<repositorio>.git
   git push -u origin main
   ```
2. Repositorio → **Settings → Secrets and variables → Actions → Variables → New repository variable**:
   - `SUPABASE_URL` = tu Project URL
   - `SUPABASE_KEY` = tu clave pública
3. **Settings → Pages → Source: GitHub Actions**.
4. Pestaña **Actions** → **Publicar en GitHub Pages** → **Run workflow** (también corre solo en cada `git push`).
5. En ≈3 minutos queda en `https://<tu-usuario>.github.io/<repositorio>/`.

> Si ya pegaste los datos en `src/environments`, las variables son opcionales.

### Paso 7 · Probar
Inicia sesión en la web y en el teléfono, haz una venta en uno y revisa que aparezca en el otro. En **Servidor → Probar conexión** debe decir *Conectado · API disponible*.

---

## 3. APK de Android

```bash
# (si no usaste variables) escribe la conexión en src/environments:
#   PowerShell:  $env:SUPABASE_URL="https://xxxx.supabase.co"; $env:SUPABASE_KEY="sb_publishable_xxx"; node scripts/configurar-supabase.mjs
npx ng build
npx cap sync android
npx cap open android      # Build → Build APK(s)
```
Para la asistencia con GPS, el `AndroidManifest.xml` necesita los permisos de ubicación (ver `GEOLOCALIZACION.md`).

---

## 4. Respaldos
El plan gratuito no da respaldos descargables. Como administrador: **Servidor → Descargar respaldo (con fotos)** una vez por semana, desde la computadora, y guárdalo en Drive o USB. **Restaurar…** reemplaza todo por el contenido del archivo (pide confirmación).

---

## 5. Límites del plan gratuito (revisa supabase.com/pricing, pueden cambiar)

| | Límite | Para La Obra |
|---|---|---|
| Base de datos | 500 MB | Años de ventas; las fotos van comprimidas |
| Inactividad | **se pausa tras 7 días sin uso** | El flujo *Mantener Supabase activo* la llama cada 3 días. Si se pausa: supabase.com → **Restore project** (no se pierden datos) |
| GitHub Pages | repositorio público | El código no contiene datos del negocio |

---

## 6. Archivos

```
supabase/
  instalar_todo.sql                 ← lo único que hay que correr (une los demás)
  01_esquema.sql                    tablas (de schema.sql + todas las migraciones de MySQL)
  02_nucleo.sql                     validaciones, sesión, costos, inventario (antes config/*.php)
  03 … 09d_*.sql                    una función por cada archivo PHP (+ respaldo)
  10_api_publica_y_permisos.sql     función pública y permisos
herramientas/exportar_mysql_a_supabase.php   pasa datos y fotos desde XAMPP (solo lectura)
scripts/configurar-supabase.mjs              escribe URL y clave en src/environments
.github/workflows/publicar-pages.yml         compila y publica en GitHub Pages
.github/workflows/mantener-activo.yml        evita que Supabase se pause
src/app/services/supabase-bridge.ts          NUEVO: manda las peticiones a Supabase
src/app/services/api-config.ts               dirección y clave de Supabase
src/app/pages/data-origins/                  pantalla "Servidor" (conexión y respaldo)
```

Cada `backend/<carpeta>/<archivo>.php` es ahora `la_obra_v2.ep_<carpeta>__<archivo>` (guiones → guion bajo). Ejemplo: `orders/checkout.php` → `ep_orders__checkout`.

---

## 7. Problemas comunes

| Mensaje | Solución |
|---|---|
| *Falta configurar Supabase* | Pega `supabaseUrl` y `supabaseKey` en `src/environments/environment.ts` y `environment.prod.ts`. |
| *La base de datos de Supabase no tiene instalada la API* | Corre `supabase/instalar_todo.sql` (Paso 2). |
| *La clave de Supabase no es válida* | En `src/environments` usa la **Publishable key** (o *anon public*), no la secret. |
| *El proyecto de Supabase está pausado* | supabase.com → proyecto → **Restore project**. |
| Página en blanco en GitHub Pages | **Settings → Pages → Source** debe ser *GitHub Actions* y el flujo debe terminar en verde. |
| Factura: *Activa la extensión "http"* | Supabase → **Database → Extensions → http**. |
| **Validar estudiante** no responde | Ese servicio vive en `http://192.168.1.158` (red local, sin HTTPS); desde GitHub Pages el navegador lo bloquea hasta que se publique con HTTPS. |
