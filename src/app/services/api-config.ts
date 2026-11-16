// Conexión con Supabase (PostgreSQL). La dirección y la clave pública están fijas en
// src/environments/environment.ts (desarrollo) y environment.prod.ts (publicada / APK).
//
// Las pantallas siguen pidiendo rutas como "products/index.php": getApiUrl() devuelve una
// dirección "virtual" (https://xxxx.supabase.co/la-obra-api) y services/supabase-bridge.ts
// convierte cada petición en una llamada a la función la_obra_v2_api de Supabase.

import { Injectable } from '@angular/core';
import { environment } from '../../environments/environment';

export const VIRTUAL_PATH = '/la-obra-api';

export interface SupabaseSettings {
  url: string;
  key: string;
  source: 'build' | 'none';
}

function clean(url: string): string {
  return String(url || '').trim().replace(/\/+$/, '').replace(/\/rest\/v1$/, '');
}

// Lectura sin Angular (la usa el puente de axios)
export function supabaseSettings(): SupabaseSettings {
  const url = clean((environment as any).supabaseUrl);
  const key = String((environment as any).supabaseKey || '').trim();
  if (url && key) return { url, key, source: 'build' };
  return { url: '', key: '', source: 'none' };
}

@Injectable({ providedIn: 'root' })
export class ApiConfigService {
  get settings(): SupabaseSettings {
    return supabaseSettings();
  }

  // Dirección base que usan las pantallas
  getApiUrl(): string {
    const s = supabaseSettings();
    if (!s.url || !s.key) throw new Error('Falta configurar Supabase en src/environments (supabaseUrl y supabaseKey).');
    if (!/^https:\/\/[^/]+$/.test(s.url) && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(s.url)) {
      throw new Error('La dirección de Supabase debe ser https://xxxx.supabase.co');
    }
    if (/^sb_secret_/.test(s.key) || /service_role/.test(atobSafe(s.key))) {
      throw new Error('Esa es la clave secreta de Supabase. Usa la clave pública (Publishable / anon).');
    }
    return s.url + VIRTUAL_PATH;
  }

  // Nombre del servidor para mostrarlo en pantalla
  getHost(): string {
    const s = supabaseSettings();
    try {
      return s.url ? new URL(s.url).host : 'sin configurar';
    } catch {
      return s.url;
    }
  }

}

function atobSafe(key: string): string {
  try {
    const part = key.split('.')[1];
    return part ? atob(part.replace(/-/g, '+').replace(/_/g, '/')) : '';
  } catch {
    return '';
  }
}
