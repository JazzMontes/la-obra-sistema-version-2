// Formatos para mostrar dinero, cantidades y fechas en español de México.
import { Pipe, PipeTransform } from '@angular/core';

const money = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' });

export function formatMoney(value: any): string {
  const n = Number(value);
  return value === null || value === undefined || value === '' || !Number.isFinite(n) ? '—' : money.format(n);
}

export function formatQty(value: any, decimals = 3): string {
  const n = Number(value);
  if (value === null || value === undefined || value === '' || !Number.isFinite(n)) return '—';
  return new Intl.NumberFormat('es-MX', { maximumFractionDigits: decimals }).format(n);
}

// Fechas 'YYYY-MM-DD' o 'YYYY-MM-DD HH:MM:SS' del servidor (hora local)
export function parseServerDate(value: string): Date | null {
  if (!value) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?/.exec(value);
  if (!m) return null;
  return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] ?? 0), +(m[5] ?? 0), +(m[6] ?? 0));
}

export function todayIso(offsetDays = 0): string {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

@Pipe({ name: 'money', standalone: false })
export class MoneyPipe implements PipeTransform {
  transform(value: any): string {
    return formatMoney(value);
  }
}

@Pipe({ name: 'qty', standalone: false })
export class QtyPipe implements PipeTransform {
  transform(value: any, decimals = 3): string {
    return formatQty(value, decimals);
  }
}

@Pipe({ name: 'dateMx', standalone: false })
export class DateMxPipe implements PipeTransform {
  transform(value: any, mode: 'date' | 'datetime' | 'time' | 'short' = 'date'): string {
    const d = parseServerDate(String(value ?? ''));
    if (!d) return '—';
    const opts: Intl.DateTimeFormatOptions =
      mode === 'time' ? { hour: '2-digit', minute: '2-digit' }
      : mode === 'datetime' ? { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }
      : mode === 'short' ? { day: 'numeric', month: 'short' }
      : { day: 'numeric', month: 'short', year: 'numeric' };
    return new Intl.DateTimeFormat('es-MX', opts).format(d);
  }
}
