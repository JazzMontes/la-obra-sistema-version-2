// Guarda la conexión con Supabase y construye la dirección de la API.
// Versión 1: IP de la computadora con XAMPP. Versión 2: proyecto de Supabase en internet.
// Por defecto usa los datos de src/environments; se pueden cambiar desde la pantalla "Conexión".

import { Injectable } from '@angular/core';
import { environment } from '../../environments/environment';
import { CONNECTION_KEY } from './storage-keys';

export interface DataOrigin {
  supabaseUrl: string;
  supabaseKey: string;
}

@Injectable({ providedIn: 'root' })
export class ApiConfigService {

  // Nombre de la función pública en Supabase (archivo supabase/10_api_publica_y_permisos.sql)
  readonly rpcName = 'la_obra_v2_api';

  private readonly defaults: DataOrigin = {
    supabaseUrl: environment.supabaseUrl,
    supabaseKey: environment.supabaseKey,
  };

  // Leer configuración guardada (o la del archivo environment)
  getOrigin(): DataOrigin {
    try {
      const saved = JSON.parse(localStorage.getItem(CONNECTION_KEY) || '{}');
      return {
        supabaseUrl: saved.supabaseUrl || this.defaults.supabaseUrl,
        supabaseKey: saved.supabaseKey || this.defaults.supabaseKey,
      };
    } catch {
      return { ...this.defaults };
    }
  }

  // ¿Ya hay datos reales de Supabase (no los de ejemplo)?
  isConfigured(): boolean {
    const o = this.getOrigin();
    return this.isValidUrl(o.supabaseUrl) && !!o.supabaseKey && !/TU-CLAVE/.test(o.supabaseKey);
  }

  // ¿La conexión viene del archivo environment o se cambió en este dispositivo?
  isCustom(): boolean {
    return !!localStorage.getItem(CONNECTION_KEY);
  }

  // Guardar la configuración en este dispositivo
  setOrigin(o: Partial<DataOrigin>): void {
    const next = { ...this.getOrigin(), ...o };
    next.supabaseUrl = String(next.supabaseUrl || '').trim().replace(/\/+$/, '').replace(/\/rest\/v1.*$/, '');
    next.supabaseKey = String(next.supabaseKey || '').trim();
    if (!this.isValidUrl(next.supabaseUrl)) {
      throw new Error('Escribe la dirección del proyecto, por ejemplo https://abcd1234.supabase.co');
    }
    if (!next.supabaseKey) throw new Error('Pega la clave pública (publishable o anon) del proyecto');
    if (/service_role|sb_secret_/i.test(next.supabaseKey) || this.isServiceRoleJwt(next.supabaseKey)) {
      throw new Error('Esa es la clave secreta (service_role). Usa la clave pública: publishable o anon.');
    }
    localStorage.setItem(CONNECTION_KEY, JSON.stringify(next));
  }

  // Volver a los datos del archivo environment
  reset(): void {
    localStorage.removeItem(CONNECTION_KEY);
  }

  isValidUrl(url: string): boolean {
    return /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?$/i.test(String(url || '').trim()) && !/TU-PROYECTO/i.test(url);
  }

  private isServiceRoleJwt(key: string): boolean {
    try {
      const payload = JSON.parse(atob(key.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
      return payload?.role === 'service_role';
    } catch {
      return false;
    }
  }

  // Dirección del proyecto (para mostrarla en pantalla)
  getServerLabel(): string {
    const url = this.getOrigin().supabaseUrl;
    try {
      return new URL(url).hostname.split('.')[0];
    } catch {
      return '';
    }
  }

  // Dirección de la función de la API
  getApiUrl(): string {
    if (!this.isConfigured()) {
      throw new Error('Configura la conexión con Supabase (pantalla Conexión)');
    }
    return `${this.getOrigin().supabaseUrl}/rest/v1/rpc/${this.rpcName}`;
  }

  // Encabezados que pide Supabase. La clave "publishable" solo va en apikey;
  // la clave "anon" (formato JWT) también va como Authorization.
  getHeaders(): Record<string, string> {
    const key = this.getOrigin().supabaseKey;
    const h: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
    if (key.startsWith('eyJ')) h['Authorization'] = `Bearer ${key}`;
    return h;
  }

  // Mostrar configuración en JSON (la clave se recorta)
  getJson(): string {
    const o = this.getOrigin();
    const k = o.supabaseKey || '';
    return JSON.stringify(
      { supabaseUrl: o.supabaseUrl, supabaseKey: k.length > 16 ? `${k.slice(0, 12)}…${k.slice(-4)}` : k, rpc: this.rpcName },
      null,
      2
    );
  }
}
