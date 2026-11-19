// Plan y créditos del NEGOCIO que contrata el sistema.
//   · Plan gratuito, Silver y Gold (los de paga, mensuales o anuales), cada uno con distintas funciones.
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
import { formatMoney, parseServerDate } from '../../shared/format.pipes';
import { CardErrors, CardForm, cardBrand, cvvLength, emptyCard, formatCardNumber, formatExp, validateCard } from '../../services/card';

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
  // Pago con tarjeta (modo de prueba). El número completo y el CVV no se guardan ni se envían.
  card: CardForm = emptyCard();
  cardTouched = false;
  blurred: Record<string, boolean> = {};
  paying = false;

  // Desbloqueo con créditos
  unlocking: BillingFeature | null = null;
  unit: 'hour' | 'day' = 'day';
  qty = 1;
  spending = false;

  // Historial (solo administradores)
  historyTab: 'payments' | 'credits' | 'unlocks' | 'subscriptions' = 'payments';
  history: any = null;

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

  // Plan gratuito: no se contrata; el negocio está en él cuando no tiene un plan de paga vigente
  isFree(p: BillingPlan): boolean {
    return !!this.s?.free_plan && p.code === this.s.free_plan;
  }

  get freePlanName(): string {
    return this.s?.plans.find(p => p.code === this.s?.free_plan)?.name || 'Plan gratuito';
  }

  isCurrent(p: BillingPlan): boolean {
    return this.sub ? this.sub.plan_code === p.code : this.isFree(p);
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
    if (!this.isAdmin || this.isFree(p)) return;
    const changing = !!this.sub && !this.isCurrent(p);
    const back = this.sub?.change_refund ?? 0;
    this.openCheckout({
      kind: 'plan',
      plan: p,
      title: `Plan ${p.name} ${this.cycle === 'annual' ? 'anual' : 'mensual'}`,
      amount: this.price(p),
      note: this.isCurrent(p) && this.sub?.cycle !== 'trial' && this.sub?.cycle !== 'gift'
        ? 'Se suma al final de lo que ya tienes pagado.'
        : changing
          ? `Empieza hoy y se paga completo. ` +
            (back > 0
              ? `Por el tiempo que te sobra del plan ${this.sub?.plan_name} se te abonan ${back} créditos (${this.refundRuleText}).`
              : `Lo que te sobra del plan ${this.sub?.plan_name} no alcanza para créditos (${this.refundRuleText}).`)
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
    this.card = emptyCard();
    this.cardTouched = false;
    this.blurred = {};
  }

  closeCheckout() {
    this.checkout = null;
    // No se deja la tarjeta en memoria al cerrar
    this.card = emptyCard();
    this.cardTouched = false;
    this.blurred = {};
  }

  // ---------- Formulario de tarjeta ----------
  get brand() {
    return cardBrand(this.card.number);
  }

  get cvvMax(): number {
    return cvvLength(this.brand);
  }

  get cardErrors(): CardErrors {
    return validateCard(this.card);
  }

  get cardValid(): boolean {
    return Object.keys(this.cardErrors).length === 0;
  }

  // Error de un campo: se muestra al salir del campo o al intentar pagar
  cardError(field: keyof CardErrors): string {
    if (!this.cardTouched && !this.blurred[field]) return '';
    return this.cardErrors[field] || '';
  }

  // Se da formato mientras se escribe (espacios en el número, diagonal en el vencimiento)
  private inputValue(event: Event, format: (v: string) => string): string {
    const el = event.target as HTMLInputElement;
    const v = format(el.value);
    if (el.value !== v) el.value = v;
    return v;
  }

  onNumber(event: Event) {
    this.card.number = this.inputValue(event, formatCardNumber);
    if (this.card.cvv.length > this.cvvMax) this.card.cvv = this.card.cvv.slice(0, this.cvvMax);
  }

  onExp(event: Event) {
    this.card.exp = this.inputValue(event, formatExp);
  }

  onCvv(event: Event) {
    this.card.cvv = this.inputValue(event, v => String(v || '').replace(/\D/g, '').slice(0, this.cvvMax));
  }

  async pay() {
    const c = this.checkout;
    if (!c || this.paying) return;
    this.cardTouched = true;
    if (!this.cardValid) {
      this.ui.error('Revisa los datos de la tarjeta');
      return;
    }
    this.paying = true;
    try {
      const r = c.kind === 'plan'
        ? await this.billing.subscribe(c.plan!.code, this.cycle, this.card)
        : await this.billing.buyCredits(c.packageId!, this.card);
      this.s = r.billing;
      this.closeCheckout();
      const card = r.result?.card ? ` con ${r.result.card}` : '';
      if (r.result?.status === 'pending') this.ui.info(`Pago${card} registrado. Se activará cuando se confirme.`);
      else this.ui.success(`${r.message}${card}` + (r.result?.note ? ` · ${r.result.note}` : ''));
      this.history = await this.billing.history().catch(() => this.history);
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo procesar el pago'));
    } finally {
      this.paying = false;
    }
  }

  // ---------- Cancelar el plan (al final del periodo) ----------
  // Cualquier plan vigente (mensual, anual, prueba o cortesía) se puede cancelar
  get canCancel(): boolean {
    const sub = this.sub;
    return this.isAdmin && !!sub && !sub.cancel_requested_at;
  }

  get refundRuleText(): string {
    const r = this.s?.refund_rule;
    return r ? `${r.credits} créditos por cada ${formatMoney(r.pesos)}, según los días que sobraban` : 'según los días que sobraban';
  }

  async cancelPlan() {
    const sub = this.sub;
    if (!sub || !this.canCancel) return;
    const shortened = sub.cancel_at !== sub.ends_at;
    const parts: string[] = [];
    if (shortened) parts.push('los meses de tu plan anual que ya no usarás');
    if (this.s?.queued.length) parts.push('las renovaciones que ya pagaste y aún no empiezan');
    const refund = parts.length
      ? sub.cancel_refund > 0
        ? ` Por ${parts.join(' y ')} se te devuelven ${sub.cancel_refund} créditos (${this.refundRuleText}).`
        : ` ${parts.join(' y ')} no alcanzan para créditos.`
      : '';
    const ok = await this.ui.confirm(
      'Cancelar plan',
      `El plan ${sub.plan_name} se quitará al terminar el mes en curso: seguirá funcionando hasta el ${this.dateText(sub.cancel_at)}. ` +
        `Después el negocio pasará al ${this.freePlanName}: solo ventas y gastos; lo demás se bloquea, pero tus datos no se borran.` +
        `${refund} Puedes reactivarlo antes de esa fecha.`,
      'Cancelar plan',
      true
    );
    if (!ok) return;
    try {
      const r = await this.billing.cancelPlan();
      this.s = r.billing;
      this.ui.success(r.message);
      this.history = await this.billing.history().catch(() => this.history);
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo cancelar el plan'));
    }
  }

  async resumePlan() {
    const sub = this.sub;
    if (!sub) return;
    // Al reactivar regresa la fecha original y se descuentan los créditos que se devolvieron al cancelar
    if (sub.cancel_refund > 0) {
      const ok = await this.ui.confirm(
        'Reactivar plan',
        `Tu plan ${sub.plan_name} vuelve a durar hasta su fecha original y se descuentan los ${sub.cancel_refund} créditos ` +
          `que se te devolvieron al cancelar.`,
        'Reactivar'
      );
      if (!ok) return;
    }
    try {
      const r = await this.billing.resumePlan();
      this.s = r.billing;
      this.ui.success(r.message);
      this.history = await this.billing.history().catch(() => this.history);
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo reactivar el plan'));
    }
  }

  private dateText(v: string): string {
    const d = parseServerDate(v);
    return d ? new Intl.DateTimeFormat('es-MX', { day: 'numeric', month: 'long', year: 'numeric' }).format(d) : v;
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
