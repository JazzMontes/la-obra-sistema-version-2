// Fondo de caja: el efectivo con el que se abre la caja al iniciar el día.
//
// Se pide en Punto de venta antes de la primera venta del día y se usa en el Corte de caja.
// Se guarda en el servidor (cash/opening.php, archivo supabase/11_caja_fondo_y_corte.sql).
// Si la base de datos todavía no tiene esa ruta, se guarda en este dispositivo para no detener la venta.
import { Injectable } from '@angular/core';
import { ApiService } from './api';
import { todayIso } from '../shared/format.pipes';

export interface CashFund {
  date: string;
  amount: number;
  user_name?: string | null;
  created_at?: string | null;
  source: 'server' | 'device';
}

const KEY = 'la-obra-fondo:';

@Injectable({ providedIn: 'root' })
export class CashFundService {
  // null = aún no se sabe si el servidor tiene la ruta
  private remote: boolean | null = null;

  constructor(private api: ApiService) {}

  get serverSupported(): boolean | null {
    return this.remote;
  }

  async get(date = todayIso()): Promise<CashFund | null> {
    if (this.remote !== false) {
      try {
        const r: any = await this.api.get('cash/opening.php', { date });
        this.remote = true;
        const o = r?.opening;
        if (o && o.amount !== null && o.amount !== undefined) {
          const fund: CashFund = { date, amount: Number(o.amount), user_name: o.user_name ?? null, created_at: o.created_at ?? null, source: 'server' };
          this.saveLocal(fund);
          return fund;
        }
        return this.local(date);
      } catch (e: any) {
        if (this.isMissingRoute(e)) this.remote = false;
      }
    }
    return this.local(date);
  }

  async set(amount: number, date = todayIso(), userName?: string | null): Promise<CashFund> {
    const value = Math.round(Math.max(0, Number(amount) || 0) * 100) / 100;
    if (this.remote !== false) {
      try {
        await this.api.post('cash/opening.php', { date, amount: value });
        this.remote = true;
        const fund: CashFund = { date, amount: value, user_name: userName ?? null, created_at: new Date().toISOString(), source: 'server' };
        this.saveLocal(fund);
        return fund;
      } catch (e: any) {
        if (!this.isMissingRoute(e)) throw e;
        this.remote = false;
      }
    }
    const fund: CashFund = { date, amount: value, user_name: userName ?? null, created_at: new Date().toISOString(), source: 'device' };
    this.saveLocal(fund);
    return fund;
  }

  // La API responde 404 (o un mensaje de "ruta no encontrada") cuando no conoce la ruta
  private isMissingRoute(e: any): boolean {
    const st = e?.response?.status;
    const msg = String(e?.response?.data?.message || e?.message || '').toLowerCase();
    return st === 404 || /no encontrad|not found|desconocid|no existe/.test(msg);
  }

  private local(date: string): CashFund | null {
    try {
      const raw = localStorage.getItem(KEY + date);
      if (!raw) return null;
      const f = JSON.parse(raw);
      return { ...f, date, amount: Number(f.amount) || 0, source: f.source === 'server' ? 'server' : 'device' };
    } catch {
      return null;
    }
  }

  private saveLocal(f: CashFund) {
    try {
      localStorage.setItem(KEY + f.date, JSON.stringify(f));
      // Se borran fondos de hace más de 40 días
      const limit = todayIso(-40);
      for (let i = localStorage.length - 1; i >= 0; i--) {
        const k = localStorage.key(i) || '';
        if (k.startsWith(KEY) && k.slice(KEY.length) < limit) localStorage.removeItem(k);
      }
    } catch {
      // Sin almacenamiento local: el fondo vale solo mientras la pantalla esté abierta
    }
  }
}
