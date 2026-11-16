// Cliente único para la API REST. Agrega la URL del servidor y el token de sesión.
import { Injectable } from '@angular/core';
import axios from 'axios';
import { ApiConfigService } from './api-config';

@Injectable({ providedIn: 'root' })
export class ApiService {
  constructor(private config: ApiConfigService) {}

  get base(): string {
    return this.config.getApiUrl();
  }

  // El servidor siempre debe responder un objeto JSON. Si responde texto (un aviso de PHP,
  // una página de error de Apache), se lanza un error claro con el inicio de esa respuesta.
  private json<T>(path: string, r: { data: any }): T {
    const d = r.data;
    if (d && typeof d === 'object') return d as T;
    const text = String(d ?? '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    throw new Error(
      text
        ? `El servidor respondió algo que no es JSON en ${path}: "${text.slice(0, 180)}"`
        : `El servidor respondió vacío en ${path}. Revisa el registro de errores de Apache.`
    );
  }

  private headers(json = true): Record<string, string> {
    const h: Record<string, string> = { Authorization: `Bearer ${localStorage.getItem('token') ?? ''}` };
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  async get<T = any>(path: string, params?: Record<string, any>): Promise<T> {
    const clean = Object.fromEntries(Object.entries(params ?? {}).filter(([, v]) => v !== null && v !== undefined && v !== ''));
    return this.json<T>(path, await axios.get(`${this.base}/${path}`, { params: clean, headers: this.headers(false) }));
  }

  async post<T = any>(path: string, body: any = {}): Promise<T> {
    return this.json<T>(path, await axios.post(`${this.base}/${path}`, body, { headers: this.headers() }));
  }

  async patch<T = any>(path: string, body: any = {}): Promise<T> {
    return this.json<T>(path, await axios.patch(`${this.base}/${path}`, body, { headers: this.headers() }));
  }

  async put<T = any>(path: string, body: any = {}): Promise<T> {
    return this.json<T>(path, await axios.put(`${this.base}/${path}`, body, { headers: this.headers() }));
  }

  async delete<T = any>(path: string, body: any = {}): Promise<T> {
    return this.json<T>(path, await axios.delete(`${this.base}/${path}`, { data: body, headers: this.headers() }));
  }

  // Subir una imagen (multipart/form-data)
  async upload<T = any>(path: string, fields: Record<string, string | number>, file: Blob, fileName = 'foto.jpg'): Promise<T> {
    const form = new FormData();
    Object.entries(fields).forEach(([k, v]) => form.append(k, String(v)));
    form.append('image', file, fileName);
    return this.json<T>(path, await axios.post(`${this.base}/${path}`, form, { headers: this.headers(false), timeout: 30000 }));
  }

  // Dirección pública de un archivo subido (fotos, tickets)
  fileUrl(path: string | null | undefined): string | null {
    if (!path) return null;
    if (/^(data:|blob:|https?:)/.test(path)) return path;
    try {
      return `${this.base}/${path.replace(/^\/+/, '')}`;
    } catch {
      return null;
    }
  }
}

// Mensaje legible de un error de la API o de la red
export function errorMessage(e: any, fallback = 'No se pudo completar la operación'): string {
  if (e?.response?.data?.message) return e.response.data.message;
  if (e?.code === 'ECONNABORTED' || e?.code === 'ETIMEDOUT') return 'El servidor tardó demasiado en responder';
  if (!e?.response && (e?.code === 'ERR_NETWORK' || e?.message === 'Network Error')) return 'Sin conexión con el servidor';
  return e?.message || fallback;
}
