// Punto de venta: tomar el pedido, cobrar y mandarlo a preparar.
// El inventario se descuenta cuando el pedido se entrega (aquí o en Pedidos).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { Router } from '@angular/router';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { CashFund, CashFundService } from '../../services/cash-fund';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

interface CartLine { product: any; quantity: number; }

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-pos',
  templateUrl: 'pos.page.html',
  styleUrls: ['pos.page.scss'],
  standalone: false,
})
export class PosPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  products: any[] = [];
  categories: any[] = [];
  methods: any[] = [];
  loading = true;
  query = '';
  category: number | null = null;

  cart: CartLine[] = [];
  mode: 'local' | 'takeaway' = 'local';
  customer = '';
  cartOpen = false;   // ticket en teléfono

  // Cobro
  payOpen = false;
  payLater = false;
  methodId: number | null = null;
  cash: number | null = null;
  deliverNow = false;
  paying = false;
  result: any = null;

  // Fondo de caja del día (se pide antes de la primera venta)
  fund: CashFund | null = null;
  fundChecked = false;
  fundOpen = false;
  fundAmount: number | null = null;
  fundError = '';
  savingFund = false;

  constructor(
    private api: ApiService,
    private ui: UiService,
    private router: Router,
    private auth: Auth,
    private funds: CashFundService
  ) {}

  ionViewWillEnter() {
    this.load();
    this.checkFund();
  }

  // ---------- Fondo de caja ----------

  async checkFund() {
    try {
      this.fund = await this.funds.get();
    } catch {
      this.fund = null;
    }
    this.fundChecked = true;
    if (!this.fund) this.askFund();
  }

  askFund() {
    this.fundAmount = this.fund ? this.fund.amount : null;
    this.fundError = '';
    this.fundOpen = true;
  }

  async saveFund() {
    if (this.savingFund) return;
    const v = this.fundAmount;
    if (v === null || (v as any) === '' || !Number.isFinite(Number(v)) || Number(v) < 0) {
      this.fundError = 'Escribe el efectivo con el que abres la caja (puede ser 0)';
      return;
    }
    this.savingFund = true;
    try {
      this.fund = await this.funds.set(Number(v), undefined, this.auth.getStoredUser()?.name);
      this.fundOpen = false;
      this.ui.success('Fondo de caja registrado');
    } catch (e) {
      this.fundError = errorMessage(e, 'No se pudo guardar el fondo');
    } finally {
      this.savingFund = false;
    }
  }

  // Sin fondo del día no se puede vender: se vuelve a pedir
  private needFund(): boolean {
    if (this.fund) return false;
    this.askFund();
    return true;
  }

  async load() {
    try {
      const [p, c, m] = await Promise.all([
        this.api.get('products/index.php'),
        this.api.get('categories/index.php'),
        this.api.get('payment-methods/index.php'),
      ]);
      this.products = p.products.filter((x: any) => x.status === 'active');
      const used = new Set(this.products.map(x => x.category?.id));
      this.categories = c.categories.filter((x: any) => x.status === 'active' && used.has(x.id));
      this.methods = m.payment_methods.filter((x: any) => x.status === 'active');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo cargar el menú'));
    } finally {
      this.loading = false;
    }
  }

  get visible(): any[] {
    return this.memo.get('visible', [this.products, this.query, this.category], () => {
      const q = this.query.trim().toLowerCase();
      return this.products.filter(p => (!this.category || p.category?.id === this.category) && (!q || p.name.toLowerCase().includes(q)));
    });
  }

  imageUrl(p: any): string | null {
    return p._imgError ? null : this.api.fileUrl(p.image_path);
  }

  qtyInCart(p: any): number {
    return this.cart.find(l => l.product.id === p.id)?.quantity ?? 0;
  }

  // Toque en la tarjeta: mitad derecha suma, mitad izquierda resta (nunca baja de 0)
  tap(p: any, ev: MouseEvent) {
    const el = ev.currentTarget as HTMLElement | null;
    // Teclado (Enter / espacio): siempre suma
    if (!el || ev.detail === 0) return this.add(p);
    const r = el.getBoundingClientRect();
    if (ev.clientX - r.left < r.width / 2) this.remove(p);
    else this.add(p);
  }

  remove(p: any) {
    const line = this.cart.find(l => l.product.id === p.id);
    if (!line) return;
    this.change(line, -1);
  }

  add(p: any) {
    if (this.needFund()) return;
    if (!p.is_available) {
      this.ui.info(`${p.name} no está disponible hoy`);
      return;
    }
    const line = this.cart.find(l => l.product.id === p.id);
    if (line) line.quantity++;
    else this.cart.push({ product: p, quantity: 1 });
  }

  change(line: CartLine, delta: number) {
    line.quantity = Math.max(0, line.quantity + delta);
    if (line.quantity <= 0) this.cart = this.cart.filter(l => l !== line);
  }

  clear() {
    this.cart = [];
    this.customer = '';
    this.mode = 'local';
  }

  get count(): number {
    return this.cart.reduce((s, l) => s + l.quantity, 0);
  }

  get total(): number {
    return Math.round(this.cart.reduce((s, l) => s + l.quantity * Number(l.product.price), 0) * 100) / 100;
  }

  // ---------- Cobro ----------

  get method(): any {
    return this.methods.find(m => m.id === this.methodId);
  }

  get isCash(): boolean {
    return String(this.method?.name ?? '').trim().toLowerCase() === 'efectivo';
  }

  // Comisión que cobra la terminal con este método (ej. 4 % con tarjeta); null si no tiene
  get feePercent(): number {
    return Number(this.method?.commission_percent) || 0;
  }

  get fee(): number | null {
    return this.feePercent > 0 ? Math.round(this.total * this.feePercent) / 100 : null;
  }

  get changeDue(): number | null {
    if (!this.isCash || this.cash === null) return null;
    return Math.round((Number(this.cash) - this.total) * 100) / 100;
  }

  get quickCash(): number[] {
    return this.memo.get('quickCash', [this.total], () => this.computeQuickCash());
  }

  private computeQuickCash(): number[] {
    const t = this.total;
    const opts = [t, ...[50, 100, 200, 500, 1000].filter(v => v > t)];
    return [...new Set(opts.map(v => Math.ceil(v)))].slice(0, 5);
  }

  openPay() {
    if (!this.cart.length) return;
    if (this.needFund()) return;
    this.cartOpen = false;
    this.payLater = false;
    this.methodId = this.methods.find(m => m.name.trim().toLowerCase() === 'efectivo')?.id ?? this.methods[0]?.id ?? null;
    this.cash = null;
    this.deliverNow = false;
    this.result = null;
    this.payOpen = true;
  }

  async checkout() {
    if (this.paying) return;
    if (!this.payLater) {
      if (!this.methodId) return this.ui.error('Elige el método de pago');
      if (this.isCash && (this.cash === null || Number(this.cash) < this.total)) return this.ui.error('El efectivo recibido no cubre el total');
    }
    this.paying = true;
    try {
      const r = await this.api.post('orders/checkout.php', {
        items: this.cart.map(l => ({ product_id: l.product.id, quantity: l.quantity })),
        delivery_mode: this.mode,
        customer_name: this.customer.trim() || null,
        deliver_now: this.deliverNow,
        payment: this.payLater ? null : { payment_method_id: this.methodId, cash_received: this.isCash ? Number(this.cash) : null },
      });
      this.result = { ...r.order, items: this.count, customer: this.customer.trim() };
      this.clear();
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo registrar la venta'));
    } finally {
      this.paying = false;
    }
  }

  newSale() {
    this.payOpen = false;
    this.result = null;
  }

  goOrders() {
    this.payOpen = false;
    this.result = null;
    this.router.navigateByUrl('/orders');
  }
}
