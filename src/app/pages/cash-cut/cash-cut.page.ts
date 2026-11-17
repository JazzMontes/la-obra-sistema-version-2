// Corte de caja del día (parte de la operación, junto con Punto de venta y Pedidos).
//
//   Efectivo esperado en caja = fondo + ventas en efectivo − gastos y salidas
//
// · Las ventas se separan por método de pago (efectivo, tarjeta, transferencia…).
//   Solo el efectivo se queda en la caja; tarjeta y transferencia van al banco.
// · Las compras pagadas en efectivo NO afectan el corte.
// · Lo contado menos el fondo debe coincidir con: ventas en efectivo − gastos y salidas.
// · El cálculo lo hace el servidor (cash/cut.php, archivo supabase/11) para toda la caja del día;
//   si la base de datos aún no tiene esa ruta, se calcula aquí con lo que el usuario puede ver.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { CashFund, CashFundService } from '../../services/cash-fund';
import { todayIso } from '../../shared/format.pipes';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

interface MethodTotal {
  name: string;
  amount: number;
  orders: number;
  cash: boolean;
}

const round = (n: number) => Math.round(n * 100) / 100;
const isCashName = (n: any) => String(n ?? '').trim().toLowerCase() === 'efectivo';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-cash-cut',
  templateUrl: 'cash-cut.page.html',
  styleUrls: ['cash-cut.page.scss'],
  standalone: false,
})
export class CashCutPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  date = todayIso();
  loading = true;
  sales: any[] = [];
  expenses: any[] = [];
  methods: any[] = [];
  fund: CashFund | null = null;
  counted: number | null = null;
  notes = '';
  // Corte calculado por el servidor (cash/cut.php): toda la caja del día, de todos los usuarios.
  // null = la base de datos aún no tiene la ruta; se calcula aquí con lo que el usuario puede ver.
  server: any = null;
  saving = false;

  // Editar fondo
  fundOpen = false;
  fundAmount: number | null = null;
  fundError = '';
  savingFund = false;

  constructor(private api: ApiService, private ui: UiService, private auth: Auth, private funds: CashFundService) {}

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  get isToday(): boolean {
    return this.date === todayIso();
  }

  ionViewWillEnter() {
    if (!this.isAdmin) this.date = todayIso();
    this.load();
  }

  async load() {
    this.loading = true;
    this.counted = null;
    this.notes = '';
    try {
      try {
        this.server = (await this.api.get('cash/cut.php', { date: this.date })).cut;
        const o = this.server?.opening;
        this.fund = o ? { date: this.date, amount: Number(o.amount), user_name: o.user_name, created_at: o.created_at, source: 'server' } : null;
        return;
      } catch (e: any) {
        if (e?.response?.status !== 404) throw e;
        this.server = null;
      }
      const expParams = this.isAdmin ? { date_from: this.date, date_to: this.date } : {};
      const [s, e, m, f] = await Promise.all([
        this.api.get('sales/index.php', { date: this.date }),
        this.api.get('expenses/index.php', expParams),
        this.api.get('payment-methods/index.php'),
        this.funds.get(this.date),
      ]);
      this.sales = s.sales ?? [];
      this.expenses = e.expenses ?? [];
      this.methods = m.payment_methods ?? [];
      this.fund = f;
    } catch (err) {
      this.ui.error(errorMessage(err, 'No se pudo preparar el corte'));
    } finally {
      this.loading = false;
    }
  }

  get savedCuts(): any[] {
    return this.server?.saved_cuts ?? [];
  }

  async saveCut() {
    if (this.saving || !this.server || !this.hasCounted) return;
    this.saving = true;
    try {
      await this.api.post('cash/cut.php', { date: this.date, counted_cash: Math.round(Number(this.counted) * 100) / 100, notes: this.notes.trim() || null });
      this.ui.success('Corte guardado');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo guardar el corte'));
    } finally {
      this.saving = false;
    }
  }

  // ---------- Cálculos ----------

  // Ventas cobradas y no canceladas
  get paidSales(): any[] {
    return this.memo.get('paid', [this.sales], () =>
      this.sales.filter(s => s.order_status !== 'cancelled' && s.payment_status === 'paid')
    );
  }

  get pendingSales(): any[] {
    return this.memo.get('pending', [this.sales], () =>
      this.sales.filter(s => s.order_status !== 'cancelled' && s.payment_status === 'pending')
    );
  }

  get paidCount(): number {
    return this.server ? Number(this.server.paid_orders) || 0 : this.paidSales.length;
  }

  get pendingCount(): number {
    return this.server ? Number(this.server.pending_orders) || 0 : this.pendingSales.length;
  }

  get pendingAmount(): number {
    if (this.server) return Number(this.server.pending_amount) || 0;
    return round(this.pendingSales.reduce((t, s) => t + Number(s.total || 0), 0));
  }

  // Ventas por método de pago (todos los métodos activos aparecen, aunque estén en $0)
  get byMethod(): MethodTotal[] {
    return this.memo.get('byMethod', [this.paidSales, this.methods, this.server], () => {
      if (this.server) {
        return (this.server.methods ?? []).map((m: any) => ({ name: m.name, amount: Number(m.amount) || 0, orders: Number(m.orders) || 0, cash: !!m.cash }));
      }
      const map = new Map<string, MethodTotal>();
      for (const m of this.methods.filter(x => x.status === 'active')) {
        map.set(String(m.name).trim().toLowerCase(), { name: m.name, amount: 0, orders: 0, cash: isCashName(m.name) });
      }
      for (const s of this.paidSales) {
        const name = s.payment_method || 'Sin método';
        const key = String(name).trim().toLowerCase();
        const row = map.get(key) ?? { name, amount: 0, orders: 0, cash: isCashName(name) };
        row.amount = round(row.amount + Number(s.total || 0));
        row.orders++;
        map.set(key, row);
      }
      // Efectivo primero
      return [...map.values()].sort((a, b) => Number(b.cash) - Number(a.cash) || b.amount - a.amount);
    });
  }

  get totalSales(): number {
    return round(this.byMethod.reduce((t, m) => t + m.amount, 0));
  }

  get cashSales(): number {
    return round(this.byMethod.filter(m => m.cash).reduce((t, m) => t + m.amount, 0));
  }

  get nonCash(): MethodTotal[] {
    return this.memo.get('nonCash', [this.byMethod], () => this.byMethod.filter(m => !m.cash));
  }

  get activeExpenses(): any[] {
    return this.memo.get('exp', [this.expenses, this.server], () =>
      this.server ? this.server.expenses_list ?? [] : this.expenses.filter(e => e.status === 'active')
    );
  }

  get expensesTotal(): number {
    return round(this.activeExpenses.reduce((t, e) => t + Number(e.amount || 0), 0));
  }

  get fundAmountValue(): number {
    return this.fund?.amount ?? 0;
  }

  // Efectivo que dejaron las ventas del día (sin el fondo)
  get cashFromSales(): number {
    return round(this.cashSales - this.expensesTotal);
  }

  // Lo que debe haber físicamente en la caja
  get expectedCash(): number {
    return round(this.fundAmountValue + this.cashFromSales);
  }

  get hasCounted(): boolean {
    return this.counted !== null && (this.counted as any) !== '' && Number.isFinite(Number(this.counted));
  }

  get countedMinusFund(): number | null {
    return this.hasCounted ? round(Number(this.counted) - this.fundAmountValue) : null;
  }

  get difference(): number | null {
    return this.hasCounted ? round(Number(this.counted) - this.expectedCash) : null;
  }

  // ---------- Fondo ----------

  editFund() {
    this.fundAmount = this.fund ? this.fund.amount : null;
    this.fundError = '';
    this.fundOpen = true;
  }

  async saveFund() {
    if (this.savingFund) return;
    const v = this.fundAmount;
    if (v === null || (v as any) === '' || !Number.isFinite(Number(v)) || Number(v) < 0) {
      this.fundError = 'Escribe el fondo (puede ser 0)';
      return;
    }
    this.savingFund = true;
    try {
      this.fund = await this.funds.set(Number(v), this.date, this.auth.getStoredUser()?.name);
      this.fundOpen = false;
      this.ui.success('Fondo actualizado');
      if (this.server) await this.load();
    } catch (e) {
      this.fundError = errorMessage(e, 'No se pudo guardar el fondo');
    } finally {
      this.savingFund = false;
    }
  }

  print() {
    window.print();
  }
}
