// Dinero: cuánto hay en efectivo, en el banco y en cada apartado, y quién nos debe.
// Todo movimiento lleva fecha y motivo. Si algo no cuadra con la realidad, "Ajustar saldo"
// registra la diferencia (no se pelea con el sistema).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

type MoveType = 'in' | 'out' | 'transfer';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-money',
  templateUrl: 'money.page.html',
  styleUrls: ['money.page.scss'],
  standalone: false,
})
export class MoneyPage {
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  tab: 'accounts' | 'debts' = 'accounts';
  loading = true;
  accounts: any[] = [];
  debts: any[] = [];
  today: any = null;

  // Detalle de una cuenta
  detail: any = null;
  history: any[] = [];
  historyLoading = false;

  // Movimiento
  moveOpen = false;
  move: any = {};
  // Ajustar saldo
  adjustOpen = false;
  adjust: any = {};
  // Nos deben
  debtOpen = false;
  debt: any = {};
  collecting: any = null;
  collect: any = {};

  saving = false;
  formError = '';

  // Ventana pequeña para pedir un motivo (en lugar de la ventana del navegador)
  ask: { title: string; text: string; value: string; resolve: (v: string | null) => void } | null = null;
  askReason(title: string, text: string, value = ''): Promise<string | null> {
    return new Promise(resolve => (this.ask = { title, text, value, resolve }));
  }
  closeAsk(ok: boolean) {
    const a = this.ask;
    if (!a) return;
    this.ask = null;
    a.resolve(ok && a.value.trim() ? a.value.trim() : null);
  }

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const r = await this.api.get('money/summary');
      this.accounts = r.accounts;
      this.debts = r.debts;
      this.today = r.today;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo cargar el dinero'));
    } finally {
      this.loading = false;
    }
  }

  get active(): any[] {
    return this.memo.get('active', [this.accounts], () => this.accounts.filter(a => a.status === 'active'));
  }
  get main(): any[] {
    return this.memo.get('main', [this.accounts], () => this.active.filter(a => !a.is_reserve));
  }
  get reserves(): any[] {
    return this.memo.get('reserves', [this.accounts], () => this.active.filter(a => a.is_reserve));
  }
  get mainTotal(): number {
    return this.main.reduce((s, a) => s + Number(a.balance || 0), 0);
  }
  get reservesTotal(): number {
    return this.reserves.reduce((s, a) => s + Number(a.balance || 0), 0);
  }
  get openDebts(): any[] {
    return this.memo.get('openDebts', [this.debts], () => this.debts.filter(d => d.status === 'open'));
  }
  get closedDebts(): any[] {
    return this.memo.get('closedDebts', [this.debts], () => this.debts.filter(d => d.status !== 'open'));
  }
  get owedTotal(): number {
    return this.openDebts.reduce((s, d) => s + Number(d.amount) - Number(d.paid), 0);
  }

  kindLabel(a: any): string {
    if (a.kind === 'cash') return 'Efectivo';
    if (a.kind === 'bank') return 'Banco o tarjeta';
    if (a.kind === 'fixed') return `Gasto fijo · ${this.fmt(a.value)} al día`;
    return `Apartado · ${+Number(a.value).toFixed(2)} %`;
  }

  icon(a: any): string {
    return a.kind === 'cash' ? 'cash' : a.kind === 'bank' ? 'card' : a.kind === 'fixed' ? 'receipt' : 'piggy';
  }

  private fmt(v: any): string {
    return new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(Number(v) || 0);
  }

  private nowLocal(): string {
    const d = new Date();
    const p = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  // ---------- Detalle ----------
  async openDetail(a: any) {
    this.detail = a;
    this.history = [];
    this.historyLoading = true;
    try {
      const r = await this.api.get('money/account', { id: a.id });
      this.detail = r.account;
      this.history = r.history;
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.historyLoading = false;
    }
  }

  historyIcon(h: any): string {
    if (h.type === 'sales') return 'pos';
    if (h.type === 'expense') return 'expenses';
    if (h.type === 'purchase') return 'purchases';
    if (h.kind === 'transfer' || h.kind === 'reserve') return 'swap';
    if (h.kind === 'adjust') return 'adjust';
    if (h.kind === 'errand') return 'bag';
    if (h.kind === 'debt' || h.kind === 'debt_payment') return 'hand';
    return Number(h.amount) >= 0 ? 'arrowDown' : 'arrowUp';
  }

  async cancelMovement(h: any) {
    const reason = await this.askReason('Anular movimiento', `${h.reason} · ${this.fmt(h.amount)}. Queda registrado como anulado.`, 'Se registró mal');
    if (!reason) return;
    try {
      await this.api.post('money/movement-cancel', { id: h.id, reason });
      this.ui.success('Movimiento anulado');
      await this.load();
      if (this.detail) await this.openDetail(this.detail);
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  // ---------- Movimiento ----------
  openMove(type: MoveType = 'in', account?: any) {
    const first = account?.id ?? this.main[0]?.id ?? null;
    const other = this.active.find(a => a.id !== first)?.id ?? null;
    this.move = { type, account_id: first, to_account_id: other, amount: null, reason: '', moved_at: this.nowLocal() };
    this.formError = '';
    this.moveOpen = true;
  }

  get moveSuggestions(): string[] {
    if (this.move.type === 'transfer') return ['Cambiamos efectivo por transferencia', 'Depósito al banco', 'Retiro del cajero', 'Pasar a un apartado'];
    if (this.move.type === 'in') return ['Me transfirieron', 'Saldo inicial', 'Préstamo que nos hicieron', 'Otro ingreso'];
    return ['Pago de sueldo', 'Retiro personal', 'Pago a proveedor', 'Otro'];
  }

  async saveMove() {
    if (this.saving) return;
    const m = this.move;
    this.formError = '';
    if (!(Number(m.amount) > 0)) return void (this.formError = 'Escribe el monto');
    if (!String(m.reason || '').trim()) return void (this.formError = 'Escribe el motivo');
    if (m.type === 'transfer' && m.account_id === m.to_account_id) return void (this.formError = 'Elige dos cuentas distintas');
    this.saving = true;
    try {
      await this.api.post('money/movement', {
        type: m.type,
        account_id: m.account_id,
        to_account_id: m.type === 'transfer' ? m.to_account_id : null,
        amount: Math.round(Number(m.amount) * 100) / 100,
        reason: String(m.reason).trim(),
        moved_at: m.moved_at,
      });
      this.moveOpen = false;
      this.ui.success('Movimiento registrado');
      await this.load();
      if (this.detail) await this.openDetail(this.detail);
    } catch (e) {
      this.formError = errorMessage(e);
    } finally {
      this.saving = false;
    }
  }

  // ---------- Ajustar saldo ----------
  openAdjust(a: any) {
    this.adjust = { account: a, real: Number(a.balance), reason: '' };
    this.formError = '';
    this.adjustOpen = true;
  }

  get adjustDiff(): number {
    return Math.round((Number(this.adjust.real || 0) - Number(this.adjust.account?.balance || 0)) * 100) / 100;
  }

  async saveAdjust() {
    if (this.saving) return;
    this.formError = '';
    if (this.adjust.real === null || this.adjust.real === '' || !Number.isFinite(Number(this.adjust.real))) {
      return void (this.formError = 'Escribe cuánto hay de verdad');
    }
    if (!String(this.adjust.reason || '').trim()) return void (this.formError = 'Escribe el motivo');
    this.saving = true;
    try {
      await this.api.post('money/adjust', { account_id: this.adjust.account.id, real_balance: Number(this.adjust.real), reason: this.adjust.reason.trim() });
      this.adjustOpen = false;
      this.ui.success('Saldo ajustado');
      await this.load();
      if (this.detail) await this.openDetail(this.detail);
    } catch (e) {
      this.formError = errorMessage(e);
    } finally {
      this.saving = false;
    }
  }

  // ---------- Nos deben ----------
  openDebt() {
    this.debt = { person: '', amount: null, reason: '', lent: false, account_id: this.main[0]?.id ?? null };
    this.formError = '';
    this.debtOpen = true;
  }

  async saveDebt() {
    if (this.saving) return;
    const d = this.debt;
    this.formError = '';
    if (!String(d.person || '').trim()) return void (this.formError = '¿Quién debe?');
    if (!(Number(d.amount) > 0)) return void (this.formError = 'Escribe cuánto debe');
    if (!String(d.reason || '').trim()) return void (this.formError = '¿Por qué debe?');
    this.saving = true;
    try {
      await this.api.post('money/debt-save', {
        person: d.person.trim(),
        amount: Math.round(Number(d.amount) * 100) / 100,
        reason: d.reason.trim(),
        account_id: d.lent ? d.account_id : null,
      });
      this.debtOpen = false;
      this.ui.success('Anotado');
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e);
    } finally {
      this.saving = false;
    }
  }

  openCollect(d: any) {
    this.collecting = d;
    this.collect = { amount: Number(d.amount) - Number(d.paid), account_id: this.main[0]?.id ?? null };
    this.formError = '';
  }

  async saveCollect() {
    if (this.saving) return;
    this.formError = '';
    if (!(Number(this.collect.amount) > 0)) return void (this.formError = 'Escribe cuánto pagó');
    this.saving = true;
    try {
      const r = await this.api.post('money/debt-collect', {
        id: this.collecting.id,
        amount: Math.round(Number(this.collect.amount) * 100) / 100,
        account_id: this.collect.account_id,
      });
      this.collecting = null;
      this.ui.success(r.message);
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e);
    } finally {
      this.saving = false;
    }
  }

  async forgiveDebt(d: any) {
    const reason = await this.askReason('Ya no se cobrará', `${d.person} · ${d.reason}. Lo que falta se da por perdido.`, 'Ya no se cobrará');
    if (!reason) return;
    try {
      await this.api.post('money/debt-cancel', { id: d.id, reason });
      this.ui.success('Listo');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  paidPct(d: any): number {
    return Math.min(100, Math.round((Number(d.paid) / Number(d.amount)) * 100));
  }
}
