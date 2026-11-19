// Sensor de red: estado de la conexión a internet del dispositivo.
//
// Qué se lee y de dónde:
//  - Capacitor Network (@capacitor/network), si la app corre como APK y el plugin está instalado:
//      Network.getStatus()                      → { connected, connectionType: 'wifi' | 'cellular' | 'none' | 'unknown' }
//      Network.addListener('networkStatusChange') → avisa cada vez que cambia la conexión
//  - Web APIs (GitHub Pages y navegador; también dentro del APK):
//      navigator.onLine + eventos 'online' / 'offline' → si hay o no conexión
//      navigator.connection (Network Information API) + evento 'change'
//         type (wifi / cellular, solo Android), effectiveType (4g, 3g, 2g, slow-2g),
//         downlink (Mb/s estimados), rtt (latencia estimada en ms), saveData (ahorro de datos)
//  - Vibración al cambiar la conexión: Capacitor Haptics si existe; si no, navigator.vibrate (Vibration API).
//  - Prueba real: se mide cuánto tarda en responder el servidor de Supabase (fetch + performance.now()).
//
// No se importa ningún paquete de Capacitor: se usa window.Capacitor solo si existe. Así la
// misma app compila y funciona en GitHub Pages aunque el plugin no esté instalado.
import { Injectable } from '@angular/core';
import { RenderService } from './render';
import { UiService } from './ui';
import { supabaseSettings } from './api-config';

export type NetQuality = 'offline' | 'weak' | 'good';
export type NetSource = 'capacitor' | 'web';

export interface NetEvent {
  at: Date;
  kind: 'online' | 'offline' | 'change' | 'test-ok' | 'test-fail' | 'start';
  text: string;
  // De qué API vino el dato (para la explicación de la tarea)
  origin: string;
}

export interface NetTest {
  ok: boolean;
  ms: number | null;
  at: Date;
  detail: string;
}

const VIBRATE_KEY = 'la-obra-net-vibrate';
const MAX_EVENTS = 30;
const TEST_TIMEOUT_MS = 8000;

@Injectable({ providedIn: 'root' })
export class NetworkService {
  online = typeof navigator !== 'undefined' ? navigator.onLine : true;
  // wifi | cellular | ethernet | bluetooth | wimax | other | none | unknown
  type = 'unknown';
  effectiveType = '';
  downlink: number | null = null;
  rtt: number | null = null;
  saveData = false;

  source: NetSource = 'web';
  events: NetEvent[] = [];
  panelOpen = false;
  testing = false;
  lastTest: NetTest | null = null;
  vibrateOnChange = localStorage.getItem(VIBRATE_KEY) !== '0';

  // Qué APIs existen en este dispositivo (se muestra en el panel)
  readonly supports = {
    onLine: typeof navigator !== 'undefined' && 'onLine' in navigator,
    connection: !!this.conn,
    vibrate: typeof navigator !== 'undefined' && typeof (navigator as any).vibrate === 'function',
    capNetwork: !!this.capPlugin('Network'),
    capHaptics: !!this.capPlugin('Haptics'),
  };

  constructor(private render: RenderService, private ui: UiService) {
    this.start();
  }

  // ---------- Lectura del sensor ----------

  private get conn(): any {
    const n: any = typeof navigator !== 'undefined' ? navigator : null;
    return n?.connection || n?.mozConnection || n?.webkitConnection || null;
  }

  // Plugin nativo de Capacitor (solo en el APK y solo si está instalado)
  private capPlugin(name: string): any {
    const cap = (window as any).Capacitor;
    try {
      if (!cap?.isNativePlatform?.()) return null;
      if (cap.isPluginAvailable && !cap.isPluginAvailable(name)) return null;
      return cap.Plugins?.[name] ?? null;
    } catch {
      return null;
    }
  }

  private start() {
    this.readConnection();

    // Web API: eventos online / offline
    window.addEventListener('online', () => this.setOnline(true, 'Evento "online" (navigator.onLine)'));
    window.addEventListener('offline', () => this.setOnline(false, 'Evento "offline" (navigator.onLine)'));

    // Web API: Network Information API
    const c = this.conn;
    if (c?.addEventListener) {
      c.addEventListener('change', () => {
        const before = this.describeLink();
        this.readConnection();
        const after = this.describeLink();
        if (after !== before && this.online) {
          this.log('change', `Cambió la red: ${after}`, 'Evento "change" (navigator.connection)');
        }
        this.render.schedule();
      });
    }

    // Capacitor Network (APK)
    const capNet = this.capPlugin('Network');
    if (capNet) {
      this.source = 'capacitor';
      Promise.resolve(capNet.getStatus())
        .then((s: any) => this.applyCapacitor(s, false))
        .catch(() => (this.source = 'web'));
      try {
        capNet.addListener('networkStatusChange', (s: any) => this.applyCapacitor(s, true));
      } catch {
        // Sin listener nativo se siguen usando los eventos web
      }
    }

    this.log(
      this.online ? 'start' : 'offline',
      this.online ? `Al abrir: ${this.describeLink()}` : 'Al abrir: sin conexión',
      this.source === 'capacitor' ? 'Network.getStatus() (Capacitor)' : 'navigator.onLine'
    );
  }

  private readConnection() {
    const c = this.conn;
    if (!c) return;
    if (c.type) this.type = c.type;
    this.effectiveType = c.effectiveType || '';
    this.downlink = typeof c.downlink === 'number' ? c.downlink : null;
    this.rtt = typeof c.rtt === 'number' ? c.rtt : null;
    this.saveData = !!c.saveData;
  }

  private applyCapacitor(s: any, isEvent: boolean) {
    if (!s) return;
    if (s.connectionType) this.type = s.connectionType;
    this.readConnection();
    if (typeof s.connected === 'boolean') {
      if (isEvent) {
        this.setOnline(s.connected, 'networkStatusChange (Capacitor Network)');
      } else {
        this.online = s.connected;
      }
    }
    this.render.schedule();
  }

  private setOnline(value: boolean, origin: string) {
    this.readConnection();
    // Capacitor y el navegador pueden avisar del mismo cambio: solo cuenta una vez
    if (value === this.online) {
      this.render.schedule();
      return;
    }
    this.online = value;
    if (value) {
      this.log('online', `Conexión restablecida: ${this.describeLink()}`, origin);
      this.ui.success('Conexión restablecida');
      this.vibrate([80]);
      void this.test(true);
    } else {
      // El aviso "Sin conexión" ya lo muestra la barra superior (app.component.html)
      this.log('offline', 'Se perdió la conexión a internet', origin);
      this.vibrate([200, 100, 200]);
    }
    this.render.schedule();
  }

  // ---------- Datos para la pantalla ----------

  get quality(): NetQuality {
    if (!this.online) return 'offline';
    const slow = ['slow-2g', '2g', '3g'].includes(this.effectiveType);
    if (slow || (this.rtt !== null && this.rtt >= 600) || (this.lastTest && !this.lastTest.ok)) return 'weak';
    if (this.lastTest?.ms != null && this.lastTest.ms >= 1500) return 'weak';
    return 'good';
  }

  get icon(): string {
    if (this.quality === 'offline') return 'wifiOff';
    if (this.type === 'cellular') return this.quality === 'weak' ? 'signalLow' : 'signal';
    return this.quality === 'weak' ? 'wifiLow' : 'wifi';
  }

  get title(): string {
    if (this.quality === 'offline') return 'Sin conexión';
    const via = this.typeLabel;
    if (this.quality === 'weak') return via ? `Conexión lenta · ${via}` : 'Conexión lenta';
    return via ? `Conectado · ${via}` : 'Conectado';
  }

  get subtitle(): string {
    if (this.quality === 'offline') return 'Lo que se pueda guardar sin red se sincronizará al volver la conexión.';
    if (this.quality === 'weak') return 'Hay internet, pero lento: las ventas y fotos pueden tardar en guardarse.';
    return 'El dispositivo tiene internet y puede guardar en el servidor.';
  }

  get typeLabel(): string {
    const map: Record<string, string> = {
      wifi: 'Wi-Fi',
      cellular: 'Datos móviles',
      ethernet: 'Cable (Ethernet)',
      bluetooth: 'Bluetooth',
      wimax: 'WiMAX',
      none: 'Ninguna',
      other: 'Otra',
    };
    return map[this.type] || '';
  }

  describeLink(): string {
    const parts = [this.typeLabel || 'tipo de red no informado'];
    if (this.effectiveType) parts.push(this.effectiveType.toUpperCase());
    if (this.downlink !== null) parts.push(`${this.downlink} Mb/s`);
    return parts.join(' · ');
  }

  get sourceLabel(): string {
    return this.source === 'capacitor' ? 'Capacitor Network + Web APIs' : 'Web APIs (navigator.onLine y Network Information)';
  }

  // ---------- Acciones ----------

  open() {
    this.panelOpen = true;
    this.readConnection();
    if (this.online && !this.lastTest && !this.testing) void this.test(false);
    this.render.schedule();
  }

  close() {
    this.panelOpen = false;
    this.render.schedule();
  }

  setVibrate(on: boolean) {
    this.vibrateOnChange = on;
    localStorage.setItem(VIBRATE_KEY, on ? '1' : '0');
    if (on) this.vibrate([60], true);
    this.render.schedule();
  }

  testVibration() {
    const ok = this.vibrate([120, 80, 120], true);
    if (!ok) this.ui.info('Este dispositivo o navegador no permite vibrar.');
  }

  // Devuelve true si se pudo pedir la vibración
  private vibrate(pattern: number[], force = false): boolean {
    if (!this.vibrateOnChange && !force) return false;
    const haptics = this.capPlugin('Haptics');
    if (haptics?.vibrate) {
      const total = pattern.reduce((a, b) => a + b, 0);
      Promise.resolve(haptics.vibrate({ duration: total })).catch(() => this.webVibrate(pattern));
      return true;
    }
    return this.webVibrate(pattern);
  }

  private webVibrate(pattern: number[]): boolean {
    try {
      const fn = (navigator as any).vibrate;
      return typeof fn === 'function' ? !!fn.call(navigator, pattern) : false;
    } catch {
      return false;
    }
  }

  // Prueba real: tiempo de respuesta del servidor de Supabase. Cualquier respuesta HTTP
  // (aunque sea 401 o 404) significa que el servidor sí se alcanzó.
  async test(silent = false): Promise<NetTest> {
    if (this.testing && this.lastTest) return this.lastTest;
    this.testing = true;
    this.render.schedule();
    const { url, key } = supabaseSettings();
    const target = url ? `${url}/rest/v1/` : `${location.origin}${location.pathname}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), TEST_TIMEOUT_MS);
    const t0 = performance.now();
    let result: NetTest;
    try {
      const res = await fetch(target, {
        method: 'GET',
        cache: 'no-store',
        headers: key ? { apikey: key } : undefined,
        signal: ctrl.signal,
      });
      const ms = Math.round(performance.now() - t0);
      result = { ok: true, ms, at: new Date(), detail: `El servidor respondió en ${ms} ms (HTTP ${res.status})` };
    } catch (e: any) {
      const aborted = e?.name === 'AbortError';
      result = {
        ok: false,
        ms: null,
        at: new Date(),
        detail: aborted ? `El servidor no respondió en ${TEST_TIMEOUT_MS / 1000} s` : 'No se pudo llegar al servidor',
      };
    } finally {
      clearTimeout(timer);
    }
    this.lastTest = result;
    this.testing = false;
    this.log(result.ok ? 'test-ok' : 'test-fail', result.detail, 'fetch() a Supabase + performance.now()');
    if (!silent && !result.ok) this.ui.error(result.detail);
    this.render.schedule();
    return result;
  }

  clearEvents() {
    this.events = [];
    this.render.schedule();
  }

  private log(kind: NetEvent['kind'], text: string, origin: string) {
    this.events = [{ at: new Date(), kind, text, origin }, ...this.events].slice(0, MAX_EVENTS);
  }
}
