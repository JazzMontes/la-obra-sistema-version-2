// Pedidos: seguimiento de lo que está en preparación o por cobrar, e historial de ventas.
// Al entregar un pedido se descuenta del inventario lo que llevan sus productos.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { parseServerDate, todayIso } from '../../shared/format.pipes';
import { RenderService, autoRefresh } from '../../services/render';
import { SearchOption } from '../../shared/search-select.component';

// Línea del pedido mientras se edita
interface EditLine { product_id: number; name: string; price: number; quantity: number; isNew: boolean; }

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
  detailEdits: any[] = [];
  detailEditsLoading = false;

  // Edición de un pedido que aún no se entrega (productos, modalidad, cliente y cobro)
  editing: any = null;
  editLines: EditLine[] = [];
  editMode: 'local' | 'takeaway' = 'local';
  editCustomer = '';
  editPaid = false;
  editMethodId: number | null = null;
  editCash: number | null = null;
  editReason = '';
  editError = '';
  savingEdit = false;
  products: any[] = [];
  addOptions: SearchOption[] = [];

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

  // Comisión de la terminal del método elegido (ej. 4 % con tarjeta)
  get feePercent(): number {
    return Number(this.methods.find(m => m.id === this.methodId)?.commission_percent) || 0;
  }

  get fee(): number | null {
    return this.paying && this.feePercent > 0 ? Math.round(Number(this.paying.total) * this.feePercent) / 100 : null;
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

  // ---------- Editar pedido (solo si no se ha entregado) ----------

  canEdit(o: any): boolean {
    return o?.order_status === 'confirmed' && o?.delivery_status === 'pending';
  }

  async openEdit(o: any) {
    if (!this.canEdit(o)) return;
    this.detail = null;
    this.editing = o;
    this.editLines = (o.items ?? []).map((i: any) => ({
      product_id: i.product_id, name: i.name, price: Number(i.unit_price), quantity: Number(i.quantity), isNew: false,
    }));
    this.editMode = o.delivery_mode === 'takeaway' ? 'takeaway' : 'local';
    this.editCustomer = o.customer_name ?? '';
    this.editPaid = o.payment_status === 'paid';
    this.editMethodId = o.payment_method_id
      ?? this.methods.find(m => m.name.trim().toLowerCase() === 'efectivo')?.id ?? this.methods[0]?.id ?? null;
    this.editCash = o.cash_received ?? null;
    this.editReason = '';
    this.editError = '';
    this.refreshAddOptions();
    try {
      if (!this.products.length) {
        this.products = (await this.api.get('products/index.php')).products.filter((p: any) => p.status === 'active');
        this.refreshAddOptions();
      }
    } catch (e) {
      this.editError = errorMessage(e, 'No se pudo cargar el menú');
    }
  }

  // Productos que se pueden agregar (los que aún no están en el pedido)
  private refreshAddOptions() {
    const inOrder = new Set(this.editLines.map(l => l.product_id));
    this.addOptions = this.products
      .filter(p => !inOrder.has(p.id))
      .map(p => ({ id: p.id, name: p.name, sub: (p.is_available ? '' : 'No disponible · ') + '$' + Number(p.price).toFixed(2) }));
  }

  addEditProduct(id: number | null) {
    const p = this.products.find(x => x.id === id);
    if (!p) return;
    if (!p.is_available) {
      this.ui.info(`${p.name} no está disponible hoy`);
      this.refreshAddOptions();
      return;
    }
    this.editLines = [...this.editLines, { product_id: p.id, name: p.name, price: Number(p.price), quantity: 1, isNew: true }];
    this.editError = '';
    this.refreshAddOptions();
  }

  changeEditQty(l: EditLine, delta: number) {
    l.quantity = Math.max(0, Math.min(999, l.quantity + delta));
    if (l.quantity <= 0) {
      this.editLines = this.editLines.filter(x => x !== l);
      this.refreshAddOptions();
    }
  }

  get editTotal(): number {
    return Math.round(this.editLines.reduce((s, l) => s + l.quantity * l.price, 0) * 100) / 100;
  }

  get editIsCash(): boolean {
    return String(this.editMethods.find(m => m.id === this.editMethodId)?.name ?? '').trim().toLowerCase() === 'efectivo';
  }

  get editChange(): number | null {
    if (!this.editPaid || !this.editIsCash || this.editCash === null || (this.editCash as any) === '') return null;
    return Math.round((Number(this.editCash) - this.editTotal) * 100) / 100;
  }

  get editOldTotal(): number {
    return Number(this.editing?.total ?? 0);
  }

  // Lo que se cobró antes y la diferencia con el nuevo total (para devolver o cobrar la diferencia)
  get editPrevPaid(): number | null {
    return this.editing?.payment_status === 'paid' ? Number(this.editing.total) : null;
  }

  // Métodos para elegir: los activos y, si el cobro se hizo con uno que ya se desactivó, también ese
  get editMethods(): any[] {
    const id = this.editing?.payment_method_id;
    if (!id || this.methods.some(m => m.id === id)) return this.methods;
    return [...this.methods, { id, name: this.editing.payment_method }];
  }

  async saveEdit() {
    if (!this.editing || this.savingEdit) return;
    this.editError = '';
    if (!this.editLines.length) {
      this.editError = 'El pedido debe tener al menos un producto. Si ya no lo quieren, cancélalo.';
      return;
    }
    if (this.editPaid && !this.editMethodId) {
      this.editError = 'Elige el método de pago';
      return;
    }
    const cash = this.editCash === null || (this.editCash as any) === '' ? null : Number(this.editCash);
    if (this.editPaid && this.editIsCash && cash !== null && cash < this.editTotal) {
      this.editError = 'El efectivo recibido no cubre el nuevo total';
      return;
    }
    this.savingEdit = true;
    try {
      const r = await this.api.post('orders/edit.php', {
        order_id: this.editing.id,
        items: this.editLines.map(l => ({ product_id: l.product_id, quantity: l.quantity })),
        delivery_mode: this.editMode,
        customer_name: this.editCustomer.trim(),
        payment: this.editPaid
          ? { payment_method_id: this.editMethodId, cash_received: this.editIsCash ? cash ?? this.editTotal : null }
          : null,
        reason: this.editReason.trim() || undefined,
      });
      const change = r.order?.change_amount;
      this.ui.success(change ? `Pedido #${this.editing.id} actualizado. Cambio: $${Number(change).toFixed(2)}` : `Pedido #${this.editing.id} actualizado`);
      this.editing = null;
      await Promise.all([this.loadActive(), this.loadHistory()]);
    } catch (e) {
      this.editError = errorMessage(e, 'No se pudo guardar el pedido');
    } finally {
      this.savingEdit = false;
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
    this.detailEdits = [];
    if (s.edit_count > 0) this.loadDetailEdits(s);
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

  private async loadDetailEdits(s: any) {
    this.detailEditsLoading = true;
    try {
      const edits = (await this.api.get('orders/edits.php', { id: s.id })).edits;
      if (this.detail === s) this.detailEdits = edits;
    } catch {
      this.detailEdits = [];
    } finally {
      this.detailEditsLoading = false;
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
