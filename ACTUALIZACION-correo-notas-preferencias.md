# La Obra v2 · Actualización: correo, notas, preferencias y mapa

## Qué cambió

| Pantalla | Cambio |
|---|---|
| **Inicio de sesión** | Se quitaron los textos "Lo que compras alimenta el inventario…" y "Usar una contraseña guardada en este dispositivo". Ahora se puede entrar con **usuario o correo**. Nuevo enlace **¿Olvidaste tu contraseña?**: llega un código de 6 dígitos al correo (vence en 15 min, 5 intentos, máximo 3 códigos cada 15 min). |
| **Usuarios** | Al crear una cuenta, a la persona **le llega un correo con su usuario, correo y contraseña temporal** (al entrar se le pide crear la suya). La contraseña es opcional: si se deja vacía se genera una. Nuevo botón **Reenviar acceso** (contraseña temporal nueva por correo). Si el correo falla, la pantalla muestra los datos para compartirlos a mano. |
| **Punto de venta** | Ya no aparece "Comer aquí / Para llevar" (todo se registra como entrega en el local). Nueva categoría **Recientes** con lo último que se vendió en ese dispositivo. **Preferencias por pieza**: en cada producto del pedido, *Agregar preferencia* → "Sin tomate" (o se escribe) → ¿para cuántas? Ej.: 3 hamburguesas, 1 sin tomate · 2 hot dogs, los 2 sin cebolla. |
| **Pedidos** | Las preferencias se ven en la tarjeta del pedido, en el detalle y al editar. Ya no se muestra "comer aquí / para llevar". |
| **Costos** | Se quitó el selector comer aquí / para llevar. |
| **Notas y pendientes** (nuevo, menú *Operación*) | Lista de qué va a comprar o hacer cada quien ("pedir el pan", "comprar tomate"), agrupada por persona o para *cualquiera del equipo*. Recordatorio con hora (en 1 hora, hoy 6 p. m., mañana 8 a. m. o fecha y hora) que puede **repetirse cada día o cada semana**. El menú muestra cuántos pendientes te tocan. Está en todos los planes. |
| **Asistencia (mapa)** | Ya no sale "API key required": el mapa usa los mosaicos de calles de Esri (sin clave) y, si fallan, OpenStreetMap. |

## Paso 1 · Actualizar la base en Supabase

Supabase → **SQL Editor** → **New query** → pega **todo** `supabase/14_correo_notas_preferencias.sql` → **Run**.
No borra datos. (También puedes volver a correr `supabase/instalar_todo.sql`, que ya lo incluye.)

## Paso 2 · Activar el envío de correos (Brevo, gratis)

1. Supabase → **Database → Extensions** → busca **http** → actívalo (el script intenta hacerlo solo).
2. En <https://www.brevo.com> crea tu cuenta gratuita.
3. **Senders, domains & dedicated IPs → Senders → Add a sender**: agrega el correo que aparecerá como remitente y verifícalo (te llega un correo de confirmación).
4. **SMTP & API → API keys → Generate a new API key** (empieza con `xkeysib-`).
5. En el SQL Editor (con tus datos):

   ```sql
   select la_obra_v2.configurar_correo(
     'xkeysib-TU-CLAVE',
     'tu-remitente-verificado@gmail.com',
     'La Obra',
     'https://jazzmontes.github.io/la-obra-sistema-version-2/'
   );
   select la_obra_v2.probar_correo('tu-correo@gmail.com');
   ```

   La clave queda en una tabla privada de la base: **no va en el código ni en GitHub**.
   Si el correo de prueba no llega, revisa spam y que el remitente esté verificado en Brevo.

## Paso 3 · Notificaciones

- **Web y teléfono con la app abierta:** en **Notas** toca **Activar** para permitir notificaciones. Cada minuto la app revisa los recordatorios y avisa con un mensaje y una notificación.
- **APK con la app cerrada (opcional):** instala el plugin de notificaciones locales y vuelve a generar el APK:

  ```bash
  npm install @capacitor/local-notifications
  npx cap sync android
  ```

  Con el plugin, la app programa en el teléfono los recordatorios de los próximos 7 días, así que suenan aunque la app esté cerrada. Sin el plugin todo funciona igual, pero solo avisa con la app abierta.

## Paso 4 · Publicar

Reemplaza tu carpeta `src/` y los archivos de `supabase/` por los de este paquete (no se tocó nada de `.github/`, `scripts/` ni la conexión con GitHub Pages) y haz `git push` como siempre.

## Rutas nuevas de la API

`auth/forgot-password`, `auth/reset-password`, `users/resend-access`, `notes/index`, `notes/save`, `notes/done`, `notes/delete`, `notes/reminders`.
Cambian: `auth/login` (usuario o correo), `users/create` (manda el correo), `orders/checkout` y `orders/edit` (aceptan `notes` por producto: `[{ "quantity": 1, "note": "sin tomate" }]`).
