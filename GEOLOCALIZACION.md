# La Obra · Asistencia con geolocalización

Nuevo apartado **Asistencia** (menú › Operación). Cada usuario registra su **llegada** y su **salida** desde el teléfono. La app obtiene la latitud y longitud reales del GPS, las muestra, calcula la distancia al negocio y **solo deja registrar si la persona está dentro del radio** que definió el administrador. El servidor repite el cálculo, así que no basta con alterar la app.

## Qué cubre de lo que pide el profesor

| Entregable | Dónde está |
|---|---|
| Solicitud adecuada de permisos | Al abrir la pantalla **no** se pide nada: solo se consulta el estado (`navigator.permissions`). Si falta, aparece una tarjeta que explica para qué se usa y el permiso se pide hasta que el usuario toca **Permitir ubicación**. El GPS se apaga al salir de la pantalla (no hay rastreo en segundo plano). |
| Obtención de latitud y longitud | `services/geolocation.ts` → `navigator.geolocation.getCurrentPosition` con alta precisión, y `watchPosition` en el modo **Seguir en vivo**. |
| Visualización de coordenadas | Latitud y longitud en decimal y en grados/minutos/segundos, precisión (± m), antigüedad de la lectura, enlace **Ver en el mapa** y un **radar** (SVG) con el negocio al centro, el área permitida y tu punto con su margen de error. |
| Funcionalidad basada en ubicación | **Geocerca**: registro de entrada/salida solo dentro del radio (Haversine en la app y otra vez en la base de datos). El administrador fija el punto del negocio con **Usar mi ubicación actual** y ajusta el radio. Historial con coordenadas y distancia de cada registro. |
| Manejo de errores / permisos rechazados | Permiso rechazado o bloqueado (con instrucciones para reactivarlo y botón Reintentar), GPS apagado/sin señal, tiempo agotado, navegador sin soporte, página `http` no segura, precisión baja (> 150 m), fuera del área, negocio sin ubicación configurada, entrada doble o salida sin entrada. |
| Captura o video desde dispositivo | Lo grabas tú: ver la sección **Guion para el video**. |

## Archivos

- `supabase/09c_api_mermas_facturas_asistencia.sql` → rutas `attendance/location`, `attendance/check`, `attendance/index` (la distancia se vuelve a calcular en la base de datos con Haversine)
- `supabase/01_esquema.sql` → tablas `work_location` y `attendance`
- `src/app/services/geolocation.ts` (permisos, lecturas, errores en español)
- `src/app/pages/attendance/*` (pantalla), ruta en `app-routing.module.ts`, menú en `app.component.ts`, iconos `pin` y `target`

## Para el APK

En `android/app/src/main/AndroidManifest.xml`, antes de `<application`, agrega:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-feature android:name="android.hardware.location.gps" android:required="false" />
```

Después: entra como **administrador** → Asistencia → **Ubicación del negocio** → párate dentro del local → **Usar mi ubicación actual** → Guardar.

> El navegador solo da la ubicación en páginas seguras: GitHub Pages (`https://`), `http://localhost` o la app instalada.

## Guion para el video (2–3 min, grabación de pantalla del teléfono)

1. Abrir Asistencia por primera vez → se ve la tarjeta que explica el permiso.
2. Tocar **Permitir ubicación** → aparece la ventana de Android → elegir **Rechazar** → se ve el error con instrucciones.
3. Ir a Ajustes › Apps › La Obra › Permisos › Ubicación → **Permitir mientras se usa la app** → volver y tocar **Reintentar**.
4. Se muestran latitud, longitud, precisión y el radar; tocar **Ver en el mapa**.
5. Tocar **Seguir en vivo** y caminar unos pasos: cambian las coordenadas y la distancia.
6. Dentro del local: **Registrar mi llegada** → aparece en el historial con coordenadas.
7. Mostrar el caso **fuera del área** (alejarte, o como admin bajar el radio a 20 m y moverte): el registro se rechaza con la distancia.
8. Como admin: ver los registros del equipo.

**Probar sin salir de casa (navegador en la compu):** Chrome › F12 › ⋮ › More tools › **Sensors** › Location: elige una ciudad o escribe coordenadas para simular estar dentro o fuera; con “Location unavailable” pruebas el error de GPS.
