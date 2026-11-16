// Geolocalización real del dispositivo con la API estándar del navegador (navigator.geolocation).
// Funciona igual en el navegador y en el APK de Capacitor: el WebView de Android pide el permiso
// de ubicación al sistema la primera vez (debe estar declarado en AndroidManifest.xml).
//
// Reglas que sigue este servicio:
//  - Nunca pide el permiso al abrir la pantalla: solo cuando el usuario toca un botón.
//  - Antes de pedirlo consulta el estado (concedido / por preguntar / bloqueado) si el sistema lo permite.
//  - Convierte cada error en un mensaje claro en español con qué hacer para resolverlo.
import { Injectable } from '@angular/core';

export type PermissionStatus = 'granted' | 'prompt' | 'denied' | 'unknown' | 'unsupported' | 'insecure';

export interface GeoReading {
  latitude: number;
  longitude: number;
  accuracy: number; // metros (radio del círculo de incertidumbre)
  altitude: number | null;
  speed: number | null;
  timestamp: number;
}

export type GeoErrorKind = 'denied' | 'unavailable' | 'timeout' | 'unsupported' | 'insecure' | 'unknown';

export class GeoError extends Error {
  constructor(public kind: GeoErrorKind, message: string, public help: string) {
    super(message);
  }
}

const OPTIONS: PositionOptions = { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 };

@Injectable({ providedIn: 'root' })
export class GeolocationService {
  get supported(): boolean {
    return typeof navigator !== 'undefined' && 'geolocation' in navigator;
  }

  // La ubicación solo funciona en "contexto seguro": https, localhost o la app instalada (APK).
  // Si la app se abre por http://192.168.x.x el navegador la bloquea sin preguntar.
  get secure(): boolean {
    return typeof window === 'undefined' || window.isSecureContext !== false;
  }

  // Estado del permiso sin mostrar la ventana del sistema
  async permission(): Promise<PermissionStatus> {
    if (!this.supported) return 'unsupported';
    if (!this.secure) return 'insecure';
    try {
      const p = await (navigator as any).permissions?.query({ name: 'geolocation' as PermissionName });
      return (p?.state as PermissionStatus) ?? 'unknown';
    } catch {
      return 'unknown'; // Algunos WebView no tienen la API de permisos; se sabrá al pedir la ubicación
    }
  }

  // Avisa cuando el usuario cambia el permiso desde la configuración del navegador
  async onPermissionChange(cb: (s: PermissionStatus) => void): Promise<() => void> {
    try {
      const p = await (navigator as any).permissions?.query({ name: 'geolocation' as PermissionName });
      if (!p) return () => {};
      const fn = () => cb(p.state as PermissionStatus);
      p.addEventListener('change', fn);
      return () => p.removeEventListener('change', fn);
    } catch {
      return () => {};
    }
  }

  // Una lectura. Si el permiso está "por preguntar", aquí aparece la ventana del sistema.
  current(): Promise<GeoReading> {
    return new Promise((resolve, reject) => {
      const pre = this.precheck();
      if (pre) return reject(pre);
      navigator.geolocation.getCurrentPosition(
        p => resolve(toReading(p)),
        e => reject(toGeoError(e)),
        OPTIONS
      );
    });
  }

  // Lecturas continuas mientras la pantalla está abierta. Devuelve la función para detenerlas.
  watch(onReading: (r: GeoReading) => void, onError: (e: GeoError) => void): () => void {
    const pre = this.precheck();
    if (pre) {
      onError(pre);
      return () => {};
    }
    const id = navigator.geolocation.watchPosition(p => onReading(toReading(p)), e => onError(toGeoError(e)), OPTIONS);
    return () => navigator.geolocation.clearWatch(id);
  }

  private precheck(): GeoError | null {
    if (!this.supported) {
      return new GeoError('unsupported', 'Este dispositivo o navegador no permite obtener la ubicación.', 'Usa un navegador actualizado (Chrome, Edge, Safari) o la app instalada.');
    }
    if (!this.secure) {
      return new GeoError(
        'insecure',
        'El navegador bloquea la ubicación porque la página no es segura (http).',
        'Abre la app instalada (APK), o entra por https:// o por http://localhost.'
      );
    }
    return null;
  }
}

function toReading(p: GeolocationPosition): GeoReading {
  return {
    latitude: p.coords.latitude,
    longitude: p.coords.longitude,
    accuracy: p.coords.accuracy,
    altitude: p.coords.altitude,
    speed: p.coords.speed,
    timestamp: p.timestamp,
  };
}

function toGeoError(e: GeolocationPositionError): GeoError {
  switch (e.code) {
    case 1:
      return new GeoError(
        'denied',
        'Rechazaste el permiso de ubicación.',
        'Actívalo en Ajustes > Aplicaciones > La Obra > Permisos > Ubicación (en el navegador: el candado junto a la dirección > Ubicación > Permitir) y vuelve a intentar.'
      );
    case 2:
      return new GeoError('unavailable', 'No se pudo determinar tu ubicación.', 'Revisa que el GPS / Ubicación del teléfono esté encendido y que tengas señal o Wi-Fi.');
    case 3:
      return new GeoError('timeout', 'El GPS tardó demasiado en responder.', 'Acércate a una ventana o sal a un lugar abierto e intenta de nuevo.');
    default:
      return new GeoError('unknown', e.message || 'Error desconocido al obtener la ubicación.', 'Intenta de nuevo.');
  }
}

// Distancia en metros entre dos puntos (Haversine). El servidor hace el mismo cálculo.
export function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = 6371000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)));
}

// Desplazamiento aproximado en metros (este, norte) de un punto respecto a otro; para el radar
export function offsetMeters(fromLat: number, fromLng: number, toLat: number, toLng: number): { x: number; y: number } {
  return {
    x: (toLng - fromLng) * 111320 * Math.cos((fromLat * Math.PI) / 180),
    y: (toLat - fromLat) * 110540,
  };
}

// 19.4326077 → 19°25'57.4" N
export function toDms(value: number, isLat: boolean): string {
  const dir = isLat ? (value >= 0 ? 'N' : 'S') : value >= 0 ? 'E' : 'O';
  const v = Math.abs(value);
  const d = Math.floor(v);
  const mFloat = (v - d) * 60;
  const m = Math.floor(mFloat);
  const s = (mFloat - m) * 60;
  return `${d}°${String(m).padStart(2, '0')}'${s.toFixed(1).padStart(4, '0')}" ${dir}`;
}
