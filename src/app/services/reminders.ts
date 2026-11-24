// Recordatorios de la pantalla Notas ("pedir el pan", "comprar tomate"…).
//
// Mientras la app está abierta, cada minuto (y al volver a la app) pregunta al servidor qué
// recordatorios le tocan a quien inició sesión (los suyos y los de "cualquiera del equipo"):
//   · los que ya llegaron a su hora se avisan con un mensaje en pantalla y una notificación;
//   · en el APK, si está instalado @capacitor/local-notifications, los de los próximos 7 días se
//     programan en el teléfono, así que suenan aunque la app esté cerrada.
// Cada recordatorio se avisa una sola vez por dispositivo (se recuerda "id@fecha").
import { Injectable } from '@angular/core';
import { Router } from '@angular/router';
import { ApiService } from './api';
import { UiService } from './ui';
import { RenderService } from './render';
import { parseServerDate } from '../shared/format.pipes';

export const REMINDERS_EVENT = 'la-obra-reminders';
const SEEN_KEY = 'la_obra_reminders_seen';
const SCHEDULED_KEY = 'la_obra_reminders_scheduled';
const NATIVE_BASE = 700000;   // ids de notificación del teléfono: 700000 + id de la nota

export type NotifyPermission = 'granted' | 'denied' | 'default' | 'unsupported';

function readJson<T>(key: string, fallback: T): T {
  try {
    const v = JSON.parse(localStorage.getItem(key) || 'null');
    return v ?? fallback;
  } catch {
    return fallback;
  }
}

function writeJson(key: string, v: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(v));
  } catch {
    // Almacenamiento no disponible
  }
}

@Injectable({ providedIn: 'root' })
export class RemindersService {
  // Pendientes que le tocan a quien inició sesión (para el número del menú)
  mine = 0;
  permission: NotifyPermission = 'unsupported';

  private timer: any = null;
  private running = false;
  private checking = false;
  private listenerReady = false;

  constructor(private api: ApiService, private ui: UiService, private render: RenderService, private router: Router) {
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && this.running) void this.check();
    });
    void this.readPermission();
  }

  // Plugin de notificaciones del teléfono (solo en el APK y si está instalado)
  private get native(): any {
    const cap = (window as any).Capacitor;
    if (!cap?.isNativePlatform?.()) return null;
    if (cap.isPluginAvailable && !cap.isPluginAvailable('LocalNotifications')) return null;
    return cap.Plugins?.LocalNotifications ?? null;
  }

  get nativeAvailable(): boolean {
    return !!this.native;
  }

  start() {
    if (this.running) return;
    this.running = true;
    void this.check();
    this.timer = setInterval(() => void this.check(), 60_000);
    this.listenNativeTaps();
  }

  // cancel: al cerrar sesión a propósito, el teléfono ya no debe avisar los recordatorios de esa cuenta.
  // (Al abrir la app se pasa por el inicio de sesión: ahí no se cancelan, para que sigan sonando.)
  async stop(cancel = false) {
    this.running = false;
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.mine = 0;
    if (cancel) await this.cancelNative();
  }

  async readPermission(): Promise<NotifyPermission> {
    const ln = this.native;
    try {
      if (ln) {
        const r = await ln.checkPermissions();
        this.permission = r?.display === 'granted' ? 'granted' : r?.display === 'denied' ? 'denied' : 'default';
      } else if (typeof Notification !== 'undefined') {
        this.permission = Notification.permission as NotifyPermission;
      } else {
        this.permission = 'unsupported';
      }
    } catch {
      this.permission = 'unsupported';
    }
    this.render.schedule();
    return this.permission;
  }

  // Lo pide la pantalla Notas con un botón (los navegadores solo lo permiten tras un toque)
  async enableNotifications(): Promise<NotifyPermission> {
    const ln = this.native;
    try {
      if (ln) {
        const r = await ln.requestPermissions();
        this.permission = r?.display === 'granted' ? 'granted' : 'denied';
      } else if (typeof Notification !== 'undefined') {
        this.permission = (await Notification.requestPermission()) as NotifyPermission;
      }
    } catch {
      this.permission = 'denied';
    }
    if (this.permission === 'granted') {
      this.ui.success('Listo: este dispositivo te avisará de tus recordatorios');
      void this.check();
    }
    this.render.schedule();
    return this.permission;
  }

  // Pregunta al servidor y avisa lo que ya llegó a su hora
  async check() {
    if (this.checking || !localStorage.getItem('token')) return;
    this.checking = true;
    try {
      const r: any = await this.api.get('notes/reminders.php');
      this.mine = Number(r.mine) || 0;
      const list: any[] = Array.isArray(r.reminders) ? r.reminders : [];
      // Diferencia entre la hora del servidor (México) y la del dispositivo
      const server = parseServerDate(r.server_time);
      const offset = server ? server.getTime() - Date.now() : 0;
      const now = Date.now() + offset;

      const seen: string[] = readJson(SEEN_KEY, []);
      const fresh: string[] = [];
      for (const n of list) {
        const at = parseServerDate(n.remind_at)?.getTime();
        if (!at || at > now) continue;
        const key = `${n.id}@${n.remind_at}`;
        if (seen.includes(key)) continue;
        fresh.push(key);
        // Solo los de las últimas 12 horas: al entrar por la mañana no salen avisos de hace días
        if (now - at <= 12 * 3600_000) this.announce(n);
      }
      if (fresh.length) writeJson(SEEN_KEY, [...fresh, ...seen].slice(0, 300));
      await this.scheduleNative(list.filter(n => (parseServerDate(n.remind_at)?.getTime() ?? 0) > now), offset);
      window.dispatchEvent(new CustomEvent(REMINDERS_EVENT));
    } catch {
      // Sin conexión o sesión vencida: se vuelve a intentar en el siguiente minuto
    } finally {
      this.checking = false;
      this.render.schedule();
    }
  }

  private text(n: any): string {
    return n.title + (n.details ? ` · ${n.details}` : '');
  }

  private announce(n: any) {
    this.ui.toast(`Recordatorio: ${this.text(n)}`, 'info', 9000);
    if ('vibrate' in navigator) {
      try {
        navigator.vibrate([180, 80, 180]);
      } catch {
        // Sin vibración
      }
    }
    const ln = this.native;
    if (ln) {
      // Si ya estaba programada en el teléfono, el sistema ya avisó a su hora
      if (readJson<number[]>(SCHEDULED_KEY, []).includes(NATIVE_BASE + Number(n.id))) return;
      // Si no (se creó con una hora que ya pasó), notificación inmediata del sistema
      void ln.schedule({
        notifications: [{ id: NATIVE_BASE + 100000 + Number(n.id), title: 'Recordatorio · La Obra', body: this.text(n), extra: { noteId: n.id }, schedule: { at: new Date(Date.now() + 1000) } }],
      }).catch(() => undefined);
      return;
    }
    if (this.permission !== 'granted' || typeof Notification === 'undefined') return;
    const options: NotificationOptions = { body: this.text(n), tag: `note-${n.id}`, icon: 'assets/icon/favicon.png' };
    try {
      const notif = new Notification('Recordatorio · La Obra', options);
      notif.onclick = () => {
        window.focus();
        void this.router.navigateByUrl('/notes');
        notif.close();
      };
    } catch {
      // Chrome en Android solo deja notificar desde un service worker
      navigator.serviceWorker?.getRegistration?.()
        .then(reg => reg?.showNotification('Recordatorio · La Obra', options))
        .catch(() => undefined);
    }
  }

  // Programa en el teléfono los recordatorios de los próximos días (suenan con la app cerrada)
  private async scheduleNative(upcoming: any[], offset: number) {
    const ln = this.native;
    if (!ln || this.permission !== 'granted') return;
    try {
      await this.cancelNative();
      const notifications = upcoming.slice(0, 50).map(n => ({
        id: NATIVE_BASE + Number(n.id),
        title: 'Recordatorio · La Obra',
        body: this.text(n),
        extra: { noteId: n.id },
        schedule: { at: new Date((parseServerDate(n.remind_at)?.getTime() ?? Date.now()) - offset), allowWhileIdle: true },
      }));
      if (notifications.length) await ln.schedule({ notifications });
      writeJson(SCHEDULED_KEY, notifications.map(x => x.id));
    } catch {
      // Si el plugin falla, quedan los avisos dentro de la app
    }
  }

  private async cancelNative() {
    const ln = this.native;
    const ids: number[] = readJson(SCHEDULED_KEY, []);
    if (!ln || !ids.length) return;
    try {
      await ln.cancel({ notifications: ids.map(id => ({ id })) });
    } catch {
      // Ya no estaban programadas
    }
    writeJson(SCHEDULED_KEY, []);
  }

  // Al tocar la notificación del teléfono se abre la pantalla Notas
  private listenNativeTaps() {
    const ln = this.native;
    if (!ln || this.listenerReady) return;
    this.listenerReady = true;
    try {
      ln.addListener('localNotificationActionPerformed', () => void this.router.navigateByUrl('/notes'));
    } catch {
      // Sin soporte
    }
  }
}
