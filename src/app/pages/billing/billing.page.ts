// Plan y créditos del NEGOCIO que contrata el sistema.
//   · Planes Bronze, Silver y Gold, mensuales o anuales, cada uno con distintas funciones.
//   · Créditos: se compran con dinero y se gastan en desbloquear una función por horas o días.
// Todos los usuarios ven qué tiene el negocio; solo un administrador puede contratar o comprar.
// Los permisos, saldos, compras y vencimientos los controla el servidor (supabase/13_planes_y_creditos.sql).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { Auth } from '../../services/auth';
import { BillingFeature, BillingPlan, BillingService, BillingStatus } from '../../services/billing';
import { errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';
import { formatMoney } from '../../shared/format.pipes';

type Cycle = 'monthly' | 'annual';

interface Checkout {
  kind: 'plan' | 'credits';
  title: string;
  amount: number;
  plan?: BillingPlan;
  packageId?: number;
  note?: string;
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-billing',
  templateUrl: 'billing.page.html',
  styleUrls: ['billing.page.scss'],
  standalone: false,
})
export class BillingPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  s: BillingStatus | null = null;
  loading = true;
  error = '';
  user: any = null;
  highlight = '';

  cycle: Cycle = 'monthly';

  // Pago (plan o paquete de créditos)
  checkout: Checkout | null = null;
  method = 'card_test';
  reference = '';
  paying = false;

  // Desbloqueo con créditos
  unlocking: BillingFeature | null = null;
  unit: 'hour' | 'day' = 'day';
  qty = 1;
  spending = false;

  // Historial (solo administradores)
  historyTab: 'payments' | 'credits' | 'unlocks' | 'subscriptions' = 'payments';
  history: any = null;

  readonly methods = [
    { key: 'card_test', label: 'Tarjeta' },
    { key: 'transfer', label: 'Transferencia' },
    { key: 'cash', label: 'Efectivo' },
  ];

  constructor(private billing: BillingService, private auth: Auth, private ui: UiService, private route: ActivatedRoute) {}

  get isAdmin(): boolean {
    return this.user?.role === 'admin';
  }

  ionViewWillEnter() {
    this.user = this.auth.getStoredUser();
    this.highlight = this.route.snapshot.queryParamMap.get('feature') || '';
    this.s = this.billing.status;
    if (this.s) this.loading = false;
    this.load();
  }

  async load(event?: any) {
    this.error = '';
    try {
      const st = await this.billing.refresh();
      if (st) this.s = st;
      else if (!this.s) this.error = 'No se pudo consultar el plan del negocio';
      if (this.isAdmin) this.history = await this.billing.history().catch(() => this.history);
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo consultar el plan del negocio');
    } finally {
      this.loading = false;
      event?.target?.complete();
    }
  }

  // ---------- Lectura ----------
  get sub() {
    return this.s?.subscription ?? null;
  }

  get highlighted(): BillingFeature | undefined {
    return this.highlight ? this.s?.features.find(f => f.key === this.highlight && !f.active) : undefined;
  }

  get lastPlanName(): string {
    const code = this.s?.last_plan?.plan_code;
    return this.s?.plans.find(p => p.code === code)?.name || '';
  }

  cycleLabel(c: string): string {
    return ({ monthly: 'Mensual', annual: 'Anual', trial: 'Prueba gratis', gift: 'Cortesía' } as any)[c] || c;
  }

  planName(code: string): string {
    return this.s?.plans.find(p => p.code === code)?.name || code;
  }

  featureName(key: string): string {
    return this.s?.features.find(f => f.key === key)?.name || key;
  }

  price(p: BillingPlan): number {
    return this.cycle === 'annual' ? p.annual_price : p.monthly_price;
  }

  // Lo que se ahorra pagando anual contra 12 meses
  saving(p: BillingPlan): number {
    return Math.max(0, p.monthly_price * 12 - p.annual_price);
  }

  isCurrent(p: BillingPlan): boolean {
    return this.sub?.plan_code === p.code;
  }

  planButton(p: BillingPlan): string {
    if (this.isCurrent(p)) return this.sub?.cycle === 'trial' || this.sub?.cycle === 'gift' ? 'Contratar' : 'Renovar';
    if (!this.sub) return 'Contratar';
    const cur = this.s?.plans.find(x => x.code === this.sub?.plan_code);
    return cur && p.monthly_price > cur.monthly_price ? 'Mejorar a ' + p.name : 'Cambiar a ' + p.name;
  }

  hasFeature(p: BillingPlan, key: string): boolean {
    return p.features.includes(key);
  }

  usersLabel(max: number | null): string {
    return max === null ? 'Usuarios ilimitados' : `Hasta ${max} usuarios activos`;
  }

  get usersPercent(): number {
    const u = this.s?.users;
    if (!u || u.max === null) return 0;
    return Math.min(100, Math.round((u.active / u.max) * 100));
  }

  methodLabel(m: string): string {
    return ({ card_test: 'Tarjeta', transfer: 'Transferencia', cash: 'Efectivo', provider: 'Proveedor' } as any)[m] || m;
  }

  statusLabel(st: string): string {
    return (
      ({ paid: 'Pagado', pending: 'Pendiente', rejected: 'Rechazado', cancelled: 'Cancelado', active: 'Vigente',
         expired: 'Vencido', scheduled: 'Programado', replaced: 'Reemplazado' } as any)[st] || st
    );
  }

  statusBadge(st: string): string {
    return ({ paid: 'badge-success', active: 'badge-success', pending: 'badge-warning', scheduled: 'badge-info',
              rejected: 'badge-danger', expired: 'badge-danger' } as any)[st] || '';
  }

  creditTypeLabel(t: string): string {
    return ({ purchase: 'Compra', bonus: 'Bono', spend: 'Desbloqueo', proration: 'Cambio de plan', refund: 'Devolución', adjust: 'Ajuste' } as any)[t] || t;
  }

  // ---------- Contratar un plan ----------
  choosePlan(p: BillingPlan) {
    if (!this.isAdmin) return;
    const changing = !!this.sub && !this.isCurrent(p) && (this.sub.cycle === 'monthly' || this.sub.cycle === 'annual');
    this.openCheckout({
      kind: 'plan',
      plan: p,
      title: `Plan ${p.name} ${this.cycle === 'annual' ? 'anual' : 'mensual'}`,
      amount: this.price(p),
      note: this.isCurrent(p) && this.sub?.cycle !== 'trial' && this.sub?.cycle !== 'gift'
        ? 'Se suma al final de lo que ya tienes pagado.'
        : changing
          ? `Empieza hoy. El tiempo que no usaste del plan ${this.sub?.plan_name} se te devuelve en créditos.`
          : 'Empieza hoy.',
    });
  }

  // ---------- Comprar créditos ----------
  choosePackage(k: { id: number; name: string; credits: number; bonus: number; price: number }) {
    if (!this.isAdmin) return;
    this.openCheckout({
      kind: 'credits',
      packageId: k.id,
      title: `${k.name}: ${k.credits + k.bonus} créditos`,
      amount: k.price,
      note: k.bonus ? `Incluye ${k.bonus} créditos de bono.` : '',
    });
  }

  private openCheckout(c: Checkout) {
    this.checkout = c;
    this.method = 'card_test';
    this.reference = '';
  }

  get needsReference(): boolean {
    return this.s?.payment_mode === 'manual' && this.method === 'transfer';
  }

  async pay() {
    const c = this.checkout;
    if (!c || this.paying) return;
    if (this.needsReference && !this.reference.trim()) {
      this.ui.error('Escribe la referencia o folio de la transferencia');
      return;
    }
    this.paying = true;
    try {
      const r = c.kind === 'plan'
        ? await this.billing.subscribe(c.plan!.code, this.cycle, this.method, this.reference.trim())
        : await this.billing.buyCredits(c.packageId!, this.method, this.reference.trim());
      this.s = r.billing;
      this.checkout = null;
      const note = r.result?.note ? ` · ${r.result.note}` : '';
      if (r.result?.status === 'pending') this.ui.info('Pago registrado. Se activará cuando se confirme.');
      else this.ui.success(r.message + note);
      this.history = await this.billing.history().catch(() => this.history);
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo registrar el pago'));
    } finally {
      this.paying = false;
    }
  }

  async cancelPayment(p: { id: number; description: string }) {
    const ok = await this.ui.confirm('Cancelar pago', `¿Cancelar el pago pendiente "${p.description}"?`, 'Cancelar pago', true);
    if (!ok) return;
    try {
      this.s = (await this.billing.cancelPayment(p.id)).billing;
      this.ui.success('Pago cancelado');
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  // ---------- Desbloquear con créditos ----------
  canUnlock(f: BillingFeature): boolean {
    return this.isAdmin && !f.in_plan && (!!f.credits_per_hour || !!f.credits_per_day);
  }

  openUnlock(f: BillingFeature) {
    if (!this.canUnlock(f)) return;
    this.unlocking = f;
    this.unit = f.credits_per_day ? 'day' : 'hour';
    this.qty = 1;
  }

  get unlockRate(): number {
    const f = this.unlocking;
    if (!f) return 0;
    return (this.unit === 'hour' ? f.credits_per_hour : f.credits_per_day) || 0;
  }

  get unlockMax(): number {
    return this.unit === 'hour' ? 72 : 90;
  }

  get unlockQty(): number {
    const n = Math.floor(Number(this.qty));
    return Number.isFinite(n) ? n : 0;
  }

  get unlockCost(): number {
    return this.unlockRate * this.unlockQty;
  }

  get unlockValid(): boolean {
    return this.unlockQty >= 1 && this.unlockQty <= this.unlockMax && this.unlockRate > 0;
  }

  get enoughCredits(): boolean {
    return (this.s?.credits ?? 0) >= this.unlockCost;
  }

  setUnit(u: 'hour' | 'day') {
    this.unit = u;
    if (this.unlockQty > this.unlockMax) this.qty = this.unlockMax;
  }

  async confirmUnlock() {
    const f = this.unlocking;
    if (!f || this.spending || !this.unlockValid || !this.enoughCredits) return;
    this.spending = true;
    try {
      const r = await this.billing.unlock(f.key, this.unit, this.unlockQty);
      this.s = r.billing;
      this.unlocking = null;
      this.ui.success(r.message);
      this.history = await this.billing.history().catch(() => this.history);
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo desbloquear'));
    } finally {
      this.spending = false;
    }
  }

  money(n: number): string {
    return formatMoney(n);
  }
}
