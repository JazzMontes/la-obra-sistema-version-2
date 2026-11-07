// Cliente único para la API. Versión 2: en lugar de llamar a archivos PHP en XAMPP,
// cada petición se envía a la función de Supabase "la_obra_v2_api", que ejecuta
// el mismo "endpoint" (products/index.php, orders/checkout.php, …) dentro de PostgreSQL.
// Por eso las pantallas siguen usando exactamente las mismas rutas que antes.
import { Injectable } from '@angular/core';
import axios, { type AxiosError } from 'axios';
import { ApiConfigService } from './api-config';
import { TOKEN_KEY } from './storage-keys';

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

@Injectable({ providedIn: 'root' })
export class ApiService {
  constructor(private config: ApiConfigService) {}

  get base(): string {
    return this.config.getApiUrl();
  }

  // Separa "users/update.php?id=5" en ruta y parámetros
  private split(path: string): { route: string; query: Record<string, any> } {
    const [route, qs] = String(path || '').replace(/^\/+/, '').split('?');
    const query: Record<string, any> = {};
    if (qs) new URLSearchParams(qs).forEach((v, k) => (query[k] = v));
    return { route, query };
  }

  private clean(params?: Record<string, any>): Record<string, any> {
    return Object.fromEntries(
      Object.entries(params ?? {}).filter(([, v]) => v !== null && v !== undefined && v !== '')
    );
  }

  // Petición genérica. Devuelve el JSON que antes devolvía el archivo PHP.
  async request<T = any>(method: Method, path: string, params?: Record<string, any>, body?: any, timeout?: number): Promise<T> {
    const { route, query } = this.split(path);
    // El "#/ruta" no viaja al servidor; sirve para identificar la petición en el diagnóstico.
    const url = `${this.base}#/${route}`;
    try {
      const r = await axios.post(
        url,
        {
          p_path: route,
          p_method: method,
          p_query: { ...query, ...this.clean(params) },
          p_body: body ?? {},
          p_token: localStorage.getItem(TOKEN_KEY),
        },
        { headers: this.config.getHeaders(), ...(timeout ? { timeout } : {}) }
      );
      const d = r.data;
      if (d && typeof d === 'object') return d as T;
      throw new Error(`Supabase respondió vacío en ${route}`);
    } catch (e: any) {
      throw normalizeError(e, route);
    }
  }

  get<T = any>(path: string, params?: Record<string, any>): Promise<T> {
    return this.request<T>('GET', path, params);
  }

  post<T = any>(path: string, body: any = {}): Promise<T> {
    return this.request<T>('POST', path, undefined, body);
  }

  patch<T = any>(path: string, body: any = {}): Promise<T> {
    return this.request<T>('PATCH', path, undefined, body);
  }

  put<T = any>(path: string, body: any = {}): Promise<T> {
    return this.request<T>('PUT', path, undefined, body);
  }

  delete<T = any>(path: string, body: any = {}): Promise<T> {
    return this.request<T>('DELETE', path, undefined, body);
  }

  // Subir una imagen. Antes era multipart/form-data; ahora la foto viaja como data URL
  // (ya viene comprimida desde el teléfono) y se guarda en la base de datos.
  async upload<T = any>(path: string, fields: Record<string, string | number>, file: Blob | string, _fileName = 'foto.jpg'): Promise<T> {
    const image = typeof file === 'string' ? file : await blobToDataUrl(file);
    return this.request<T>('POST', path, undefined, { ...fields, image }, 30000);
  }

  // Ruta de un archivo subido (fotos, tickets). La directiva [apiSrc] la pide a files/image.php
  fileUrl(path: string | null | undefined): string | null {
    if (!path) return null;
    return path;
  }
}

export function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error('No se pudo leer la imagen'));
    reader.readAsDataURL(blob);
  });
}

// Convierte las respuestas de error de Supabase al formato que usaba PHP:
// e.response.data = { success: false, message, ...datos extra }
function normalizeError(e: any, route: string): any {
  const err = e as AxiosError<any>;
  const data = err?.response?.data;
  if (data && typeof data === 'object') {
    let extra: Record<string, any> = {};
    if (typeof data.details === 'string' && data.details.startsWith('{')) {
      try { extra = JSON.parse(data.details); } catch { /* sin datos extra */ }
    }
    let message = data.message;
    const code = String(data.code || '');
    if (code === 'PGRST202' || /Could not find the function/i.test(message || '')) {
      message = 'La base de datos de Supabase no tiene instalada la API de La Obra v2. Corre supabase/instalar_todo.sql en el SQL Editor.';
    } else if (/Invalid API key|No API key/i.test(message || '') || (err.response?.status === 401 && !code.startsWith('PT'))) {
      message = 'La clave de Supabase no es válida. Revísala en la pantalla Conexión.';
    } else if (code === '57014') {
      message = 'La consulta tardó demasiado en Supabase. Intenta de nuevo o usa un periodo más corto.';
    } else if (!code.startsWith('PT') && code && err.response?.status && err.response.status >= 500) {
      message = `Error en la base de datos (${code}) en ${route}: ${message}`;
    }
    (err.response as any).data = { ...extra, ...data, success: false, message };
  }
  return err;
}

// Mensaje legible de un error de la API o de la red
export function errorMessage(e: any, fallback = 'No se pudo completar la operación'): string {
  if (e?.response?.data?.message) return e.response.data.message;
  if (e?.code === 'ECONNABORTED' || e?.code === 'ETIMEDOUT') return 'Supabase tardó demasiado en responder';
  if (!e?.response && (e?.code === 'ERR_NETWORK' || e?.message === 'Network Error')) return 'Sin conexión a internet o con Supabase';
  return e?.message || fallback;
}
