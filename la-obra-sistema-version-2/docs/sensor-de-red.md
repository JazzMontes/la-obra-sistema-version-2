# Sensor de red: estado de conexión (La Obra v2)

## 1. Qué se implementó

En el encabezado de todas las pantallas de La Obra hay ahora un **ícono de conexión** que cambia solo según el estado de la red del dispositivo:

| Ícono | Significa |
|---|---|
| Wi-Fi completo (punto verde) | Conectado por Wi-Fi con buena conexión |
| Barras de señal (punto verde) | Conectado por datos móviles |
| Wi-Fi o barras a medias (amarillo) | Hay internet pero lento (3G/2G, latencia alta o el servidor tarda más de 1.5 s) |
| Wi-Fi tachado (rojo, punto parpadeando) | Sin conexión |

Al tocar el ícono se abre el panel **"Estado de conexión"** con:

- **Estado**: en línea o sin conexión.
- **Tipo de red**: Wi-Fi, datos móviles, cable, etc.
- **Calidad estimada**: 4G, 3G, 2G, slow-2G.
- **Velocidad estimada** (Mb/s) y **latencia estimada** (ms).
- **Ahorro de datos**: si el usuario lo tiene activado.
- **Respuesta del servidor**: una prueba real que mide en milisegundos cuánto tarda en responder Supabase (botón "Probar").
- **Vibración**: el teléfono vibra cuando se pierde la conexión (2 pulsos) o cuando vuelve (1 pulso). Se puede apagar y probar.
- **Historial de eventos**: cada cambio con su hora y la API que lo informó.

Cuando vuelve la conexión, además aparece el aviso "Conexión restablecida" y se mide de nuevo el servidor. La barra "Sin conexión" de arriba también abre el panel.

## 2. APIs utilizadas (Capacitor / Web APIs)

| API | Tipo | Qué entrega | Evento |
|---|---|---|---|
| `navigator.onLine` | Web API | `true` / `false`: si el dispositivo tiene red | `online`, `offline` en `window` |
| `navigator.connection` (Network Information API) | Web API | `type`, `effectiveType`, `downlink`, `rtt`, `saveData` | `change` en `navigator.connection` |
| `navigator.vibrate()` (Vibration API) | Web API | Hace vibrar el teléfono con un patrón en ms | — |
| `fetch()` + `performance.now()` | Web API | Tiempo real de respuesta del servidor | — |
| `Network` (`@capacitor/network`) | Capacitor | `connected`, `connectionType` (`wifi`, `cellular`, `none`, `unknown`) | `networkStatusChange` |
| `Haptics` (`@capacitor/haptics`) | Capacitor | Vibración nativa en el APK | — |

La app usa **Web APIs siempre** (funcionan en GitHub Pages y dentro del APK). Si la app corre como APK **y** están instalados los plugins de Capacitor, los usa además. El código los detecta con `window.Capacitor` y no los importa, así que la app compila aunque no estén instalados.

### Explicación de los eventos

- **`offline` / `online`**: el sistema operativo avisa al navegador que la interfaz de red se desconectó o se conectó (por ejemplo, al activar el modo avión). `navigator.onLine` cambia a `false` o `true` y la app actualiza el ícono, vibra y lo anota en el historial.
- **`change` (Network Information API)**: se dispara cuando cambian las características de la conexión: pasar de Wi-Fi a datos, o que la calidad baje de 4G a 3G. Los datos son **estimaciones del navegador**: `downlink` es la velocidad aproximada de bajada en Mb/s (redondeada a múltiplos de 25 kb/s) y `rtt` es el tiempo de ida y vuelta aproximado en ms (redondeado a múltiplos de 25 ms). El navegador las calcula con el tráfico reciente.
- **`networkStatusChange` (Capacitor)**: el equivalente nativo en Android; entrega `connected` y `connectionType` directamente desde el sistema.
- **Prueba al servidor**: `navigator.onLine = true` solo dice que hay red, no que haya internet (por ejemplo, un Wi-Fi sin salida a internet). Por eso la app hace una petición real a Supabase y mide el tiempo. Cualquier respuesta HTTP cuenta como "el servidor se alcanzó".

### Por qué es útil en La Obra

La Obra registra ventas, pedidos, gastos y fotos en Supabase. Si el teléfono del punto de venta pierde internet, el empleado lo ve al instante (ícono rojo y vibración) y sabe que debe esperar antes de cerrar una venta o un corte de caja. La pantalla de Productos ya guardaba cambios sin red y los sincronizaba después; ahora el estado de la red es visible en toda la app.

## 3. Código

Archivos nuevos:

- `src/app/services/network.ts`: servicio que lee el sensor (Capacitor + Web APIs), calcula la calidad, vibra, prueba el servidor y guarda el historial.
- `src/app/shared/network-button.component.ts`: el ícono del encabezado.

Archivos modificados:

- `src/app/app.component.ts`, `.html` y `.scss`: panel "Estado de conexión"; la barra "Sin conexión" ahora usa el servicio y abre el panel.
- `src/app/shared/icon.component.ts`: íconos `wifi`, `wifiLow`, `signal`, `signalLow` y `vibrate`.
- `src/app/shared/shared.module.ts`: registra el componente del ícono.
- El encabezado (`*.page.html`) de las 21 pantallas con menú: se agregó `<app-network-button>`.

No se modificó nada de la conexión con GitHub Pages, de `environments/` ni de la base de datos de Supabase.

Fragmento principal (lectura del sensor):

```ts
// Web API: hay o no conexión
window.addEventListener('online',  () => this.setOnline(true,  'Evento "online"'));
window.addEventListener('offline', () => this.setOnline(false, 'Evento "offline"'));

// Web API: Network Information
const c = (navigator as any).connection;
c?.addEventListener('change', () => {
  this.type = c.type;                   // wifi | cellular | ...
  this.effectiveType = c.effectiveType; // 4g | 3g | 2g | slow-2g
  this.downlink = c.downlink;           // Mb/s estimados
  this.rtt = c.rtt;                     // ms estimados
});

// Capacitor (APK), si el plugin está instalado
const Network = (window as any).Capacitor?.Plugins?.Network;
Network?.addListener('networkStatusChange', s => this.applyCapacitor(s, true));
```

### (Opcional) Activar los plugins de Capacitor en el APK

```bash
npm install @capacitor/network @capacitor/haptics
npx cap sync android
```

No hay que cambiar código: la app los detecta sola. `@capacitor/haptics` agrega el permiso `VIBRATE` al APK. Sin ese plugin, para que `navigator.vibrate` funcione dentro del APK hay que tener en `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.VIBRATE" />
```

## 4. Prompt utilizado para investigar la API

> Estoy haciendo una app Ionic + Angular (sin zone.js) que se publica en GitHub Pages y también se compila como APK de Android con Capacitor. Tengo que implementar un sensor o capacidad física con Capacitor o Web APIs. Elegí el estado de la red. Investiga:
> 1. Qué datos da `navigator.onLine` y qué eventos dispara; qué limitaciones tiene (¿detecta un Wi-Fi sin internet?).
> 2. La Network Information API (`navigator.connection`): qué significan `type`, `effectiveType`, `downlink`, `rtt` y `saveData`, cuándo se dispara `change` y en qué navegadores existe (Chrome Android, WebView, Safari iOS, Firefox).
> 3. El plugin `@capacitor/network`: métodos, evento `networkStatusChange` y qué devuelve.
> 4. Cómo vibrar el teléfono al cambiar la conexión con `navigator.vibrate` y con `@capacitor/haptics`, y qué permisos necesita en Android.
> 5. Cómo medir si de verdad hay salida a internet midiendo el tiempo de respuesta de mi servidor de Supabase.
>
> Quiero que funcione en web aunque el plugin de Capacitor no esté instalado, sin romper la compilación. Dame el diseño y el código para un ícono de wifi en el encabezado que cambie según el estado y que abra un panel con todos los datos y un historial de eventos.

## 5. Validación de la solución

### Revisión del código

- [x] El servicio `network.ts` pasa la revisión de tipos de TypeScript en modo estricto.
- [x] No se importa `@capacitor/network` ni `@capacitor/haptics`: si no están instalados, `ng build` no falla y la app usa Web APIs.
- [x] Si Capacitor y el navegador avisan del mismo cambio, se registra una sola vez.
- [x] La prueba al servidor tiene un límite de 8 s (`AbortController`) para que no se quede "Midiendo…".
- [ ] `ng build` y `npx cap sync android` sin errores (hacerlo en la computadora del proyecto).

### Pruebas en dispositivo (para el video)

| # | Prueba | Resultado esperado | ✔ |
|---|---|---|---|
| 1 | Abrir la app con Wi-Fi | Ícono de Wi-Fi verde; el panel dice "Conectado · Wi-Fi", 4G, Mb/s y ms | |
| 2 | Tocar "Probar" | Aparece el tiempo del servidor en ms y una línea verde en el historial | |
| 3 | Activar modo avión | El ícono cambia a Wi-Fi tachado rojo, aparece la barra "Sin conexión", el teléfono vibra 2 veces y el historial dice "Se perdió la conexión" | |
| 4 | Quitar modo avión | Vuelve el ícono, aviso "Conexión restablecida", 1 vibración y nueva prueba al servidor | |
| 5 | Apagar Wi-Fi con datos móviles encendidos | El ícono cambia a barras de señal y el tipo dice "Datos móviles" | |
| 6 | Chrome DevTools → Network → "Slow 3G" (en computadora) | Ícono amarillo "Conexión lenta" | |
| 7 | Apagar "Vibrar cuando cambie la conexión" y repetir la prueba 3 | Cambia el ícono pero no vibra | |

### Compatibilidad encontrada al investigar

| Dato | Chrome Android / APK | Chrome escritorio | Safari iPhone | Firefox |
|---|---|---|---|---|
| `navigator.onLine` + eventos | Sí | Sí | Sí | Sí |
| `connection.effectiveType`, `downlink`, `rtt` | Sí | Sí | No | No |
| `connection.type` (Wi-Fi / datos) | Sí | No | No | No |
| `navigator.vibrate` | Sí (en el APK necesita el permiso `VIBRATE`) | No hace nada | No | Sí en Android |
| Capacitor Network / Haptics | Sí (si se instalan) | — | — | — |

Cuando un dato no existe en el dispositivo, el panel muestra "No disponible" en lugar de fallar. Ese es el comportamiento esperado.

**Limitación conocida:** `navigator.onLine = true` no garantiza que haya internet. Solo indica que hay una red conectada. Por eso se agregó la prueba real contra Supabase, que es la que confirma que el servidor responde.

## 6. Guion sugerido para el video

1. Mostrar el ícono en una pantalla (por ejemplo, Punto de venta) y abrir el panel.
2. Tocar "Probar" y "Probar vibración".
3. Bajar la barra del teléfono y activar el modo avión: ver el ícono rojo, la vibración y el historial.
4. Quitar el modo avión: "Conexión restablecida".
5. Cambiar de Wi-Fi a datos móviles y mostrar el cambio de ícono y de tipo de red.
