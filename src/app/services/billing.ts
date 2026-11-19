// Plan y créditos del NEGOCIO (no de cada usuario).
//
// El servidor es quien decide: cada ruta de la API revisa si el negocio tiene vigente la
// función a la que pertenece y, si no, responde 402. Este servicio solo guarda una copia del
// estado (billing/status) para que la app sepa qué mostrar con candado en el menú y a qué
// pantallas no entrar, y la vuelve a pedir:
//   · al iniciar sesión,
//   · cada 2 minutos mientras la app está abierta (así un desbloqueo por horas se vuelve a
//     bloquear sin recargar),
//   · cuando el servidor responde 402 (venció algo a media sesión),
//   · después de contratar, comprar créditos o desbloquear.
import { Injectable } from '@angular/core';
import axios from 'axios';
import { ApiService } from './api';

export interface BillingFeature {
  key: string;
  name: string;
  description: string;
  credits_per_hour: number | null;
  credits_per_day: number | null;
  in_plan: boolean;
  unlocked_until: string | null;
  active: boolean;
}

export interface BillingPlan {
  code: string;
  name: string;
  description: string;
  monthly_price: number;
  annual_price: number;
  max_users: number | null;
  features: string[];
}

export interface BillingStatus {
  business: { id: number; name: string };
  now: string;
  credits: number;
  payment_mode: 'simulated' | 'manual';
  currency: string;
  bank_info: string;
  // Plan gratuito: el que tiene el negocio cuando no hay uno de paga vigente (no se contrata ni vence)
  free_plan: string | null;
  effective_plan: { code: string; name: string } | null;
  subscription: null | {
    id: number;
    plan_code: string;
    plan_name: string;
    cycle: 'monthly' | 'annual' | 'trial' | 'gift';
    price: number;
    starts_at: string;
    ends_at: string;
    paid_until: string;
    days_left: number;
    // Cancelado al final del periodo: sigue vigente hasta ends_at y ya no se renueva
    cancel_requested_at: string | null;
  };
  last_plan: null | { plan_code: string; ends_at: string };
  queued: { id: number; plan_code: string; cycle: string; starts_at: string; ends_at: string }[];
  users: { active: number; max: number | null };
  features: BillingFeature[];
  plans: BillingPlan[];
  packages: { id: number; name: string; credits: number; bonus: number; price: number }[];
  pending_payments: { id: number; concept: string; description: string; amount: number; method: string; reference: string | null; created_at: string }[];
}

const KEY = 'billing';
export const BILLING_EVENT = 'la-obra-billing-updated';
const REFRESH_MS = 2 * 60 * 1000;

@Injectable({ providedIn: 'root' })
export class BillingService {
  private timer: any = null;
  private inFlight: Promise<BillingStatus | null> | null = null;

  constructor(private api: ApiService) {
    // Si el servidor bloquea algo (402 por plan o créditos), se actualiza el estado guardado
    axios.interceptors.response.use(
      r => r,
      error => {
        const d = error?.response?.data;
        if (error?.response?.status === 402 && d?.plan_required && !String(error?.config?.url || '').includes('/billing/')) {
          void this.refresh();
        }
        return Promise.reject(error);
      }
    );
    this.timer = setInterval(() => {
      if (localStorage.getItem('token') && document.visibilityState !== 'hidden') void this.refresh();
    }, REFRESH_MS);
  }

  // Estado guardado (puede ser null antes de iniciar sesión)
  get status(): BillingStatus | null {
    try {
      return JSON.parse(localStorage.getItem(KEY) || 'null');
    } catch {
      return null;
    }
  }

  set(status: BillingStatus | null) {
    if (status) localStorage.setItem(KEY, JSON.stringify(status));
    else localStorage.removeItem(KEY);
    window.dispatchEvent(new CustomEvent(BILLING_EVENT));
  }

  clear() {
    this.set(null);
  }

  // Pide el estado al servidor. Si falla (sin red) se queda el último que se conoce.
  refresh(): Promise<BillingStatus | null> {
    if (!localStorage.getItem('token')) return Promise.resolve(null);
    if (this.inFlight) return this.inFlight;
    this.inFlight = this.api
      .get('billing/status.php')
      .then(r => {
        this.set(r.billing);
        return r.billing as BillingStatus;
      })
      .catch(() => this.status)
      .finally(() => (this.inFlight = null));
    return this.inFlight;
  }

  // ¿El negocio puede usar esta función ahora? Sin estado conocido no se bloquea en la app:
  // el servidor de todos modos lo revisa en cada petición.
  isActive(feature: string | undefined | null): boolean {
    if (!feature) return true;
    const s = this.status;
    if (!s) return true;
    const f = s.features.find(x => x.key === feature);
    if (!f) return true;
    if (this.inFreePlan(s, f.key)) return true;
    if (f.in_plan) return this.planStillValid(s);
    return !!f.unlocked_until && !this.passed(f.unlocked_until);
  }

  feature(key: string): BillingFeature | undefined {
    return this.status?.features.find(f => f.key === key);
  }

  // Lo que incluye el Plan gratuito nunca vence
  private inFreePlan(s: BillingStatus, key: string): boolean {
    return !!s.free_plan && !!s.plans?.find(p => p.code === s.free_plan)?.features.includes(key);
  }

  // El plan guardado sigue vigente según el reloj del dispositivo (por si la app quedó abierta)
  private planStillValid(s: BillingStatus): boolean {
    return !!s.subscription && (!this.passed(s.subscription.ends_at) || !this.passed(s.subscription.paid_until));
  }

  private passed(serverDate: string): boolean {
    const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?/.exec(serverDate || '');
    if (!m) return false;
    return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] ?? 0)).getTime() <= Date.now();
  }

  // Llamadas que cambian el plan o los créditos (solo administradores)
  async subscribe(plan_code: string, cycle: 'monthly' | 'annual', method: string, reference: string) {
    const r = await this.api.post('billing/subscribe.php', { plan_code, cycle, method, reference });
    this.set(r.billing);
    return r;
  }

  async buyCredits(package_id: number, method: string, reference: string) {
    const r = await this.api.post('billing/buy-credits.php', { package_id, method, reference });
    this.set(r.billing);
    return r;
  }

  async unlock(feature: string, unit: 'hour' | 'day', quantity: number) {
    const r = await this.api.post('billing/unlock.php', { feature, unit, quantity });
    this.set(r.billing);
    return r;
  }

  // Cancelar el plan al final del periodo (y deshacerlo mientras siga vigente)
  async cancelPlan(reason = '') {
    const r = await this.api.post('billing/cancel.php', { reason });
    this.set(r.billing);
    return r;
  }

  async resumePlan() {
    const r = await this.api.post('billing/resume.php', {});
    this.set(r.billing);
    return r;
  }

  async cancelPayment(id: number) {
    const r = await this.api.post('billing/cancel-payment.php', { id });
    this.set(r.billing);
    return r;
  }

  history() {
    return this.api.get('billing/history.php');
  }
}
