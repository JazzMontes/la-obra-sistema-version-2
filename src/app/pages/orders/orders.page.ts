// Pedidos: seguimiento de lo que está en preparación o por cobrar, e historial de ventas.
// Al entregar un pedido se descuenta del inventario lo que llevan sus productos.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { parseServerDate, todayIso } from '../../shared/format.pipes';
import { RenderService, autoRefresh } from '../../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-orders',
  templateUrl: 'orders.page.html',
  styleUrls: ['orders.page.scss'],
  standalone: false,
})
export class OrdersPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  tab: 'active' | 'history' = 'active';
  active: any[] = [];
  history: any[] = [];
  methods: any[] = [];
  loading = true;
  date = todayIso();
  busy = new Set<number>();
  now = Date.now();
  private timer: any = null;

  // Cobro de un pedido pendiente
  paying: any = null;
  methodId: number | null = null;
  cash: number | null = null;
  savingPay = false;

  detail: any = null;

  // Factura de prueba (CFDI 4.0 timbrado en el ambiente de pruebas de Profact)
  invoice: { uuid: string; xml: string } | null = null;
  invoiceLoading = false;
  invoiceBusy = false;
  invoiceError = '';
  cardType: 'credit' | 'debit' | null = null;

  constructor(private api: ApiService, private ui: UiService, private auth: Auth, private render: RenderService) {}

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  ionViewWillEnter() {
    this.loadAll();
    this.timer = setInterval(() => {
      this.now = Date.now();
      this.render.schedule();
      if (this.tab === 'active') this.loadActive(true);
    }, 20000);
  }

  ionViewWillLeave() {
    clearInterval(this.timer);
  }

  async loadAll() {
    this.loading = true;
    try {
      const [m] = await Promise.all([this.api.get('payment-methods/index.php'), this.loadActive(), this.loadHistory()]);
      this.methods = m.payment_methods.filter((x: any) => x.status === 'active');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar los pedidos'));
    } finally {
      this.loading = false;
    }
  }

  async loadActive(silent = false) {
    try {
      this.active = (await this.api.get('orders/active.php')).orders;
    } catch (e) {
      if (!silent) throw e;
    }
  }

  async loadHistory() {
    this.history = (await this.api.get('sales/index.php', { date: this.date })).sales;
  }

  async changeDate() {
    try {
      await this.loadHistory();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  minutes(o: any): number {
    const d = parseServerDate(o.confirmed_at || o.created_at);
    return d ? Math.max(0, Math.floor((this.now - d.getTime()) / 60000)) : 0;
  }

  elapsed(o: any): string {
    const m = this.minutes(o);
    return m < 1 ? 'ahora' : m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`;
  }

  status(o: any): { label: string; cls: string } {
    if (o.order_status === 'cancelled') return { label: 'Cancelado', cls: 'badge-danger' };
    if (o.payment_status === 'pending') return { label: 'Por cobrar', cls: 'badge-warning' };
    if (o.delivery_status === 'pending') return { label: 'En preparación', cls: 'badge-info' };
    return { label: 'Completado', cls: 'badge-success' };
  }

  get historyTotal(): number {
    return this.history.filter(s => s.order_status === 'confirmed' && s.payment_status === 'paid').reduce((s, o) => s + Number(o.total), 0);
  }

  // ---------- Acciones ----------

  async deliver(o: any) {
    this.busy.add(o.id);
    try {
      await this.api.patch('orders/deliver.php', { order_id: o.id });
      this.ui.success(`Pedido #${o.id} entregado`);
      await Promise.all([this.loadActive(), this.loadHistory()]);
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.busy.delete(o.id);
    }
  }

  async cancel(o: any) {
    const ok = await this.ui.confirm('Cancelar pedido', `¿Cancelar el pedido #${o.id}? Si ya se entregó, lo descontado vuelve al inventario.`, 'Cancelar pedido', true);
    if (!ok) return;
    this.busy.add(o.id);
    try {
      await this.api.patch('orders/cancel.php', { order_id: o.id });
      this.ui.success('Pedido cancelado');
      await Promise.all([this.loadActive(), this.loadHistory()]);
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.busy.delete(o.id);
    }
  }

  openPay(o: any) {
    this.paying = o;
    this.methodId = this.methods.find(m => m.name.trim().toLowerCase() === 'efectivo')?.id ?? this.methods[0]?.id ?? null;
    this.cash = null;
  }

  get isCash(): boolean {
    return String(this.methods.find(m => m.id === this.methodId)?.name ?? '').trim().toLowerCase() === 'efectivo';
  }

  get changeDue(): number | null {
    if (!this.paying || !this.isCash || this.cash === null) return null;
    return Math.round((Number(this.cash) - Number(this.paying.total)) * 100) / 100;
  }

  async pay() {
    if (!this.paying || this.savingPay) return;
    if (!this.methodId) return this.ui.error('Elige el método de pago');
    if (this.isCash && (this.cash === null || Number(this.cash) < Number(this.paying.total))) return this.ui.error('El efectivo no cubre el total');
    this.savingPay = true;
    try {
      const r = await this.api.post('sales/payment.php', {
        order_id: this.paying.id,
        payment_method_id: this.methodId,
        cash_received: this.isCash ? Number(this.cash) : undefined,
      });
      const change = r.payment?.change_amount;
      this.ui.success(change ? `Cobrado. Cambio: $${Number(change).toFixed(2)}` : 'Pedido cobrado');
      this.paying = null;
      await Promise.all([this.loadActive(), this.loadHistory()]);
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.savingPay = false;
    }
  }

  // ---------- Detalle y facturación ----------

  canInvoice(s: any): boolean {
    return s?.order_status === 'confirmed' && s?.payment_status === 'paid';
  }

  async openDetail(s: any) {
    this.detail = s;
    this.invoice = null;
    this.invoiceError = '';
    this.cardType = null;
    if (!this.canInvoice(s)) return;
    this.invoiceLoading = true;
    try {
      this.invoice = (await this.api.get('invoices/order.php', { id: s.id })).invoice;
    } catch (e) {
      this.invoiceError = errorMessage(e, 'No se pudo consultar la factura');
    } finally {
      this.invoiceLoading = false;
    }
  }

  // Venta con "Tarjeta" sin indicar crédito o débito: se pregunta solo para la factura
  needsCardType(s: any): boolean {
    const n = String(s?.payment_method ?? '').trim().toLowerCase();
    return n.includes('tarjeta') && !n.includes('créd') && !n.includes('cred') && !n.includes('déb') && !n.includes('deb');
  }

  async stampInvoice() {
    if (!this.detail || this.invoiceBusy) return;
    if (this.needsCardType(this.detail) && !this.cardType) {
      this.invoiceError = 'Elige si la tarjeta fue de crédito o débito';
      return;
    }
    this.invoiceBusy = true;
    this.invoiceError = '';
    try {
      this.invoice = (await this.api.post('invoices/order.php', { order_id: this.detail.id, card_type: this.cardType })).invoice;
      this.ui.success('Factura de prueba timbrada');
    } catch (e) {
      this.invoiceError = errorMessage(e, 'No se pudo timbrar la factura');
    } finally {
      this.invoiceBusy = false;
    }
  }

  downloadXml() {
    if (!this.invoice || !this.detail) return;
    const blob = new Blob([this.invoice.xml], { type: 'application/xml' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `factura-prueba-pedido-${this.detail.id}.xml`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  async cancelSale(s: any) {
    const ok = await this.ui.confirm('Cancelar venta', `¿Cancelar la venta #${s.id} ya cobrada? Si se entregó, el inventario se devuelve.`, 'Cancelar venta', true);
    if (!ok) return;
    try {
      await this.api.patch('sales/cancel.php', { order_id: s.id });
      this.detail = null;
      this.ui.success('Venta cancelada');
      await Promise.all([this.loadActive(), this.loadHistory()]);
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }
}
