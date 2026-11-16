// Puente entre la app y Supabase.
//
// Las pantallas y servicios siguen haciendo peticiones como en la versión con PHP:
//   axios.get(`${api}/products/index.php`, { params, headers: { Authorization: 'Bearer <token>' } })
// Este puente detecta las que van a la dirección virtual de la API y, en lugar de mandarlas
// a un servidor PHP, llama a la función de PostgreSQL public.la_obra_v2_api en Supabase:
//   POST https://xxxx.supabase.co/rest/v1/rpc/la_obra_v2_api
//   { path, method, query, body, token }
// La respuesta se entrega con el mismo código HTTP y el mismo JSON que daba el PHP, así que
// el manejo de errores, los avisos y la ventana de diagnóstico funcionan igual.
// Las fotos (FormData con un archivo "image") se envían como data URL.

import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from 'axios';
import { VIRTUAL_PATH, supabaseSettings } from './api-config';

let installed = false;

export function installSupabaseBridge() {
  if (installed) return;
  installed = true;
  axios.interceptors.request.use(config => {
    const s = supabaseSettings();
    const url = String(config.url || '');
    if (s.url && url.startsWith(s.url + VIRTUAL_PATH + '/')) {
      config.adapter = supabaseAdapter as any;
    }
    return config;
  });
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(new Error('No se pudo leer la imagen'));
    r.readAsDataURL(blob);
  });
}

async function readBody(data: any): Promise<any> {
  if (data === undefined || data === null || data === '') return null;
  if (typeof FormData !== 'undefined' && data instanceof FormData) {
    const out: Record<string, any> = {};
    for (const [k, v] of (data as any).entries()) {
      out[k] = typeof v === 'string' ? v : await blobToDataUrl(v as Blob);
    }
    return out;
  }
  if (typeof data === 'string') {
    try {
      return JSON.parse(data);
    } catch {
      return null;
    }
  }
  return data;
}

function headerValue(config: InternalAxiosRequestConfig, name: string): string {
  const h: any = config.headers || {};
  const v = typeof h.get === 'function' ? h.get(name) : undefined;
  if (v) return String(v);
  for (const k of Object.keys(h)) if (k.toLowerCase() === name.toLowerCase()) return String(h[k]);
  return '';
}

async function supabaseAdapter(config: InternalAxiosRequestConfig): Promise<AxiosResponse> {
  const s = supabaseSettings();
  const full = new URL(String(config.url));
  const base = new URL(s.url + VIRTUAL_PATH);
  const path = full.pathname.slice(base.pathname.length).replace(/^\/+/, '');

  // Parámetros de la URL, siempre como texto (igual que $_GET en PHP)
  const query: Record<string, string> = {};
  full.searchParams.forEach((v, k) => (query[k] = v));
  for (const [k, v] of Object.entries(config.params || {})) {
    if (v !== undefined && v !== null) query[k] = String(v);
  }

  const auth = headerValue(config, 'Authorization');
  const m = /^Bearer\s+(\S+)$/i.exec(auth.trim());
  const token = m && m[1] !== 'null' && m[1] !== 'undefined' ? m[1] : null;
  const body = await readBody(config.data);
  const method = String(config.method || 'get').toUpperCase();

  const headers: Record<string, string> = { 'Content-Type': 'application/json', Accept: 'application/json', apikey: s.key };
  // Las claves antiguas (anon, JWT "eyJ...") también van en Authorization; las nuevas (sb_publishable_) solo en apikey
  if (s.key.startsWith('eyJ')) headers['Authorization'] = `Bearer ${s.key}`;

  const controller = new AbortController();
  // Los respaldos pueden tardar (fotos incluidas)
  const timeoutMs = /^backup\//.test(path) ? Math.max(config.timeout || 0, 180000) : config.timeout || 20000;
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res: Response;
  try {
    res = await fetch(`${s.url}/rest/v1/rpc/la_obra_v2_api`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ path, method, query, body, token }),
      signal: controller.signal,
    });
  } catch (e: any) {
    clearTimeout(timer);
    const aborted = e?.name === 'AbortError';
    throw new AxiosError(
      aborted ? `timeout of ${timeoutMs}ms exceeded` : 'Network Error',
      aborted ? 'ECONNABORTED' : 'ERR_NETWORK',
      config
    );
  }
  clearTimeout(timer);

  let raw: any = null;
  try {
    raw = await res.json();
  } catch {
    raw = null;
  }

  let status: number;
  let data: any;
  if (res.ok && raw && typeof raw === 'object' && 'status' in raw && 'body' in raw) {
    status = Number(raw.status) || 200;
    data = raw.body;
  } else {
    // Error de Supabase (no de la app): clave, función no instalada, proyecto pausado…
    status = res.status === 404 ? 503 : res.status || 502;
    const code = raw?.code || '';
    let message = raw?.message || raw?.msg || `Supabase respondió ${res.status}`;
    if (code === 'PGRST202' || /la_obra_v2_api/.test(message)) {
      message = 'La base de datos de Supabase no tiene instalada la API de La Obra v2. Corre supabase/instalar_todo.sql en el SQL Editor.';
    } else if (res.status === 401 || /api key|apikey|JWT/i.test(message)) {
      message = 'La clave de Supabase no es válida. Revisa la clave pública en "Detalles del servidor".';
    } else if (res.status === 540 || res.status === 503) {
      message = 'El proyecto de Supabase está pausado o en mantenimiento. Entra a supabase.com y presiona "Restore project".';
    }
    data = { success: false, message, supabase: raw };
  }

  const response: AxiosResponse = {
    data,
    status,
    statusText: String(status),
    headers: {},
    config,
    request: {},
  };
  const validate = config.validateStatus ?? ((st: number) => st >= 200 && st < 300);
  if (validate(status)) return response;
  throw new AxiosError(
    data?.message || `Request failed with status code ${status}`,
    status >= 500 ? AxiosError.ERR_BAD_RESPONSE : AxiosError.ERR_BAD_REQUEST,
    config,
    {},
    response
  );
}
