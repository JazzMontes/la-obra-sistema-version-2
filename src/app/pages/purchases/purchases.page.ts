// Compras: lo que se compró, a quién, quién lo compró y el ticket.
// Al guardar, cada renglón entra al inventario y su precio actualiza los costos.
import { ChangeDetectionStrategy, Component, ViewChild } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { InputFormComponent } from '../../shared/input-form.component';
import { todayIso } from '../../shared/format.pipes';
import { dataUrlToBlob } from '../../utils/image';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';
import { SearchOption } from '../../shared/search-select.component';

// Un renglón de la compra. buy_unit: la unidad en que se compró (paquete, kg… o la principal);
// content_per_package: cuánto de la unidad principal trae cada una (se prellena con la medida del insumo).
interface Line {
  input_id: number | null;
  buy_unit: string;
  quantity: number | null;
  content_per_package: number | null;
  unit_cost: number | null;
}

interface BuyOption { name: string; factor: number; base: boolean; }

const NEW_INPUT = -1;

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-purchases',
  templateUrl: 'purchases.page.html',
  styleUrls: ['purchases.page.scss'],
  standalone: false,
})
export class PurchasesPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  @ViewChild(InputFormComponent) inputForm?: InputFormComponent;
  readonly NEW_INPUT = NEW_INPUT;

  purchases: any[] = [];
  inputs: any[] = [];
  methods: any[] = [];
  loading = true;
  from = todayIso(-30);
  to = todayIso();

  // Formulario
  formOpen = false;
  editingId: number | null = null;
  form: any = {};
  lines: Line[] = [];
  // Formas de pago: una (todo el total) o varias con su monto (ej. tarjeta $300 + efectivo $200)
  payments: { payment_method_id: number | null; amount: number | null }[] = [];
  ticket: string | null = null;      // vista previa
  newTicket: string | null | undefined = undefined; // undefined = sin cambios, null = quitar
  saving = false;
  formError = '';

  // Alta rápida de insumo desde un renglón
  inputModalOpen = false;
  inputForLine: Line | null = null;
  newInputName = '';
  savingInput = false;

  // Detalle
  detail: any = null;
  ticketBroken = false;   // la foto no se pudo cargar (archivo borrado o sin acceso)
  ticketZoom = false;     // foto ampliada

  constructor(private api: ApiService, private ui: UiService, private auth: Auth) {}

  ionViewWillEnter() {
    this.loadCatalogs();
    this.load();
  }

  async loadCatalogs() {
    try {
      const [inp, pm] = await Promise.all([this.api.get('inputs/index.php'), this.api.get('payment-methods/index.php')]);
      this.inputs = inp.inputs.filter((i: any) => i.status === 'active');
      this.methods = pm.payment_methods.filter((m: any) => m.status === 'active');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar insumos y métodos de pago'));
    }
  }

  async load() {
    this.loading = true;
    try {
      this.purchases = (await this.api.get('purchases/index.php', { date_from: this.from, date_to: this.to })).purchases;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar las compras'));
    } finally {
      this.loading = false;
    }
  }

  get periodTotal(): number {
    return this.purchases.reduce((s, p) => s + Number(p.total), 0);
  }

  get suppliers(): string[] {
    return this.memo.get('suppliers', [this.purchases], () => [...new Set(this.purchases.map(p => p.supplier).filter(Boolean))] as string[]);
  }

  ticketUrl(p: any): string | null {
    return this.api.fileUrl(p?.ticket_path);
  }

  input(id: number | null): any {
    return this.inputs.find(i => Number(i.id) === Number(id));
  }

  // ---------- Formulario ----------

  openNew() {
    this.editingId = null;
    this.form = {
      purchase_date: todayIso(),
      supplier: '',
      buyer: this.auth.getStoredUser()?.name ?? '',
      change_reason: '',
    };
    this.payments = [{ payment_method_id: this.methods[0]?.id ?? null, amount: null }];
    this.lines = [this.emptyLine()];
    this.ticket = null;
    this.newTicket = undefined;
    this.formError = '';
    this.formOpen = true;
  }

  async openEdit(p: any) {
    try {
      const full = (await this.api.get('purchases/show.php', { id: p.id })).purchase;
      this.detail = null;
      this.editingId = full.id;
      this.form = {
        purchase_date: full.purchase_date,
        supplier: full.supplier ?? '',
        buyer: full.buyer ?? '',
        change_reason: '',
      };
      const pays = (full.payments ?? []).map((x: any) => ({ payment_method_id: Number(x.payment_method_id), amount: Number(x.amount) }));
      this.payments = pays.length ? pays : [{ payment_method_id: full.payment_method_id, amount: null }];
      this.lines = full.items.map((i: any) => ({
        input_id: Number(i.input_id),
        buy_unit: i.buy_unit || (Number(i.content_per_package) === 1 ? i.unit : this.packLabel(this.input(Number(i.input_id)))) || i.unit,
        quantity: Number(i.quantity),
        content_per_package: Number(i.content_per_package),
        unit_cost: Number(i.unit_cost),
      }));
      this.ticket = full.ticket_path || null;
      this.newTicket = undefined;
      this.formError = '';
      this.formOpen = true;
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  emptyLine(): Line {
    return { input_id: null, buy_unit: '', quantity: 1, content_per_package: null, unit_cost: null };
  }

  addLine() {
    this.lines.push(this.emptyLine());
  }

  removeLine(i: number) {
    this.lines.splice(i, 1);
    if (!this.lines.length) this.addLine();
  }

  // Opciones del buscador de insumos
  get inputOptions(): SearchOption[] {
    return this.memo.get('inputOptions', [this.inputs], () => this.inputs.map(i => ({ id: Number(i.id), name: i.name, sub: i.unit })));
  }

  // "+ Registrar insumo nuevo" desde el buscador (con lo que se escribió como nombre)
  openNewInput(line: Line, name: string) {
    this.inputForLine = line;
    this.newInputName = name || '';
    this.inputModalOpen = true;
  }

  onInputChange(line: Line, value: any) {
    if (Number(value) === NEW_INPUT) {
      line.input_id = null;
      this.openNewInput(line, '');
      return;
    }
    line.input_id = value === null ? null : Number(value);
    this.prefill(line);
  }

  // ---------- Unidades de compra ----------
  // La unidad principal y las medidas del insumo marcadas "para compras" (primero las de compra)
  buyOptions(inputId: number | null): BuyOption[] {
    const inp = this.input(inputId);
    return this.memo.get('buy:' + inputId, [inp], () => {
      if (!inp) return [];
      const extra = (inp.units ?? [])
        .filter((u: any) => u.use_in !== 'recipe')
        .map((u: any) => ({ name: String(u.name), factor: Number(u.factor) || Number(u.base_amount) / (Number(u.unit_amount) || 1), base: false }));
      return [...extra, { name: String(inp.unit), factor: 1, base: true }];
    });
  }

  // Opciones del renglón (si una compra vieja usó una unidad que ya no existe, también aparece)
  lineOptions(l: Line): BuyOption[] {
    const opts = this.buyOptions(l.input_id);
    if (!l.buy_unit || opts.some(o => o.name === l.buy_unit)) return opts;
    return this.memo.get('lo:' + l.input_id + ':' + l.buy_unit, [opts], () => [...opts, { name: l.buy_unit, factor: Number(l.content_per_package) || 1, base: false }]);
  }

  private option(l: Line): BuyOption | undefined {
    return this.buyOptions(l.input_id).find(o => o.name === l.buy_unit);
  }

  isBaseUnit(l: Line): boolean {
    const inp = this.input(l.input_id);
    return !!inp && l.buy_unit === inp.unit;
  }

  // Al elegir el insumo: lo de la última compra (unidad, cantidad, contenido y precio). Todo se puede cambiar.
  private prefill(line: Line) {
    const inp = this.input(line.input_id);
    if (!inp) return;
    const opts = this.buyOptions(line.input_id);
    const lp = inp.last_purchase;
    const fromLast = lp ? opts.find(o => o.name.toLowerCase() === String(lp.buy_unit || '').toLowerCase()) : undefined;
    if (lp && (fromLast || !lp.buy_unit)) {
      const opt = fromLast ?? opts[opts.length - 1];
      line.buy_unit = opt.name;
      line.quantity = Number(lp.quantity) || 1;
      line.content_per_package = opt.base ? 1 : Number(lp.content_per_package) || opt.factor;
      line.unit_cost = lp.unit_cost !== null && lp.unit_cost !== undefined ? Number(lp.unit_cost) : this.priceFor(inp, opt);
      return;
    }
    // Sin compras anteriores (o la unidad ya no existe): la primera unidad de compra y el costo del insumo
    const opt = opts[0];
    line.buy_unit = opt.name;
    line.quantity = 1;
    line.content_per_package = opt.factor;
    line.unit_cost = this.priceFor(inp, opt);
  }

  // Precio sugerido para una unidad: el de la última compra si fue en esa unidad; si no, costo × contenido
  private priceFor(inp: any, opt: BuyOption, content = opt.factor): number | null {
    const lp = inp?.last_purchase;
    if (lp && String(lp.buy_unit || '').toLowerCase() === opt.name.toLowerCase() && Number(lp.content_per_package) === content) return Number(lp.unit_cost);
    if (inp?.unit_cost === null || inp?.unit_cost === undefined) return null;
    return Math.round(Number(inp.unit_cost) * content * 100) / 100;
  }

  onUnitChange(l: Line) {
    const opt = this.option(l);
    if (!opt) return;
    l.content_per_package = opt.factor;
    l.unit_cost = this.priceFor(this.input(l.input_id), opt);
  }

  async saveInput() {
    if (!this.inputForm) return;
    this.savingInput = true;
    const ok = await this.inputForm.submit();
    this.savingInput = false;
    if (!ok) return;
  }

  onInputCreated(input: any) {
    this.inputs = [...this.inputs, input].sort((a, b) => a.name.localeCompare(b.name));
    if (this.inputForLine) {
      this.inputForLine.input_id = Number(input.id);
      this.prefill(this.inputForLine);
    }
    this.inputModalOpen = false;
    this.inputForLine = null;
    this.ui.success(`"${input.name}" registrado`);
  }

  // Presentación guardada del insumo; vacía si nunca se ha comprado en presentación
  packLabel(inp: any): string {
    if (!inp || !inp.package_type || inp.package_type === inp.unit || inp.package_type === 'unidad') return '';
    return inp.package_type;
  }

  lineTotal(l: Line): number {
    return Math.round((Number(l.quantity) || 0) * (Number(l.unit_cost) || 0) * 100) / 100;
  }

  lineBase(l: Line): number {
    return (Number(l.quantity) || 0) * (this.isBaseUnit(l) ? 1 : Number(l.content_per_package) || 0);
  }

  lineUnitCost(l: Line): number | null {
    const base = this.lineBase(l);
    return base > 0 ? this.lineTotal(l) / base : null;
  }

  get total(): number {
    return this.lines.reduce((s, l) => s + this.lineTotal(l), 0);
  }

  // ---------- Formas de pago ----------
  splitPayment() {
    const first = this.payments[0];
    const other = this.methods.find(m => m.id !== first.payment_method_id)?.id ?? first.payment_method_id;
    first.amount = Math.round(this.total * 100) / 100;
    this.payments = [first, { payment_method_id: other, amount: 0 }];
  }

  addPayment() {
    this.payments = [...this.payments, { payment_method_id: this.methods[0]?.id ?? null, amount: null }];
  }

  removePayment(i: number) {
    this.payments = this.payments.filter((_, k) => k !== i);
    if (this.payments.length === 1) this.payments[0].amount = null;
  }

  get paid(): number {
    return Math.round(this.payments.reduce((s, p) => s + (Number(p.amount) || 0), 0) * 100) / 100;
  }

  // Lo que falta (positivo) o sobra (negativo) para llegar al total
  get payLeft(): number {
    return this.payments.length > 1 ? Math.round((this.total - this.paid) * 100) / 100 : 0;
  }

  fillRest(i: number) {
    const others = this.payments.reduce((s, p, k) => s + (k === i ? 0 : Number(p.amount) || 0), 0);
    this.payments[i].amount = Math.max(0, Math.round((this.total - others) * 100) / 100);
  }

  // "Tarjeta $300 · Efectivo $200" o solo "Efectivo"
  payLabel(p: any): string {
    const list = p?.payments ?? [];
    if (list.length > 1) {
      const f = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' });
      return list.map((x: any) => `${x.name} ${f.format(Number(x.amount))}`).join(' · ');
    }
    return list[0]?.name ?? p?.payment_method ?? '';
  }

  onTicket(value: string | null) {
    this.newTicket = value;
    this.ticket = value;
  }

  async save() {
    if (this.saving) return;
    this.formError = '';
    const items = this.lines.filter(l => l.input_id);
    if (!this.form.purchase_date) return void (this.formError = 'Indica la fecha de la compra');
    if (this.payments.some(p => !p.payment_method_id)) return void (this.formError = 'Elige la forma de pago');
    if (!items.length) return void (this.formError = 'Agrega al menos un artículo');
    if (this.payments.length > 1 && this.payLeft !== 0) {
      return void (this.formError = this.payLeft > 0 ? `Faltan ${this.payLeft.toFixed(2)} pesos por repartir entre las formas de pago` : `Las formas de pago suman ${(-this.payLeft).toFixed(2)} pesos de más`);
    }
    const ids = items.map(l => l.input_id);
    if (new Set(ids).size !== ids.length) return void (this.formError = 'Hay un insumo repetido; junta las cantidades en un solo renglón');
    for (const l of items) {
      const name = this.input(l.input_id)?.name ?? 'un artículo';
      if (!(Number(l.quantity) > 0)) return void (this.formError = `Indica la cantidad de ${name}`);
      if (!this.isBaseUnit(l) && !(Number(l.content_per_package) > 0)) return void (this.formError = `Indica cuánto trae cada ${l.buy_unit || 'unidad'} de ${name}`);
      if (l.unit_cost === null || Number(l.unit_cost) < 0) return void (this.formError = `Indica el precio de ${name}`);
    }
    const body: any = {
      purchase_date: this.form.purchase_date,
      supplier: String(this.form.supplier || '').trim() || null,
      buyer: String(this.form.buyer || '').trim() || null,
      payment_method_id: Number(this.payments[0].payment_method_id),
      payments: this.payments.length > 1
        ? this.payments.filter(p => Number(p.amount) > 0).map(p => ({ payment_method_id: Number(p.payment_method_id), amount: Math.round(Number(p.amount) * 100) / 100 }))
        : [{ payment_method_id: Number(this.payments[0].payment_method_id), amount: Math.round(this.total * 100) / 100 }],
      items: items.map(l => ({
        input_id: l.input_id,
        buy_unit: String(l.buy_unit || '').trim() || null,
        package_type: String(l.buy_unit || '').trim() || null,
        quantity: Number(l.quantity),
        content_per_package: this.isBaseUnit(l) ? 1 : Number(l.content_per_package),
        unit_cost: Math.round(Number(l.unit_cost) * 100) / 100,
      })),
    };
    this.saving = true;
    try {
      let id = this.editingId;
      if (id) {
        await this.api.patch('purchases/update.php', { id, ...body, change_reason: this.form.change_reason || null });
      } else {
        id = Number((await this.api.post('purchases/create.php', body)).purchase.id);
      }
      if (this.newTicket) {
        try {
          await this.api.upload('purchases/upload-ticket.php', { id: id! }, dataUrlToBlob(this.newTicket), `ticket-${id}.jpg`);
        } catch (e) {
          this.ui.error('La compra se guardó, pero el ticket no: ' + errorMessage(e));
        }
      } else if (this.newTicket === null && this.editingId) {
        await this.api.delete('purchases/delete-ticket.php', { id });
      }
      this.formOpen = false;
      this.ui.success(this.editingId ? 'Compra actualizada; costos recalculados' : 'Compra registrada; costos actualizados');
      await Promise.all([this.load(), this.loadCatalogs()]);
    } catch (e) {
      this.formError = errorMessage(e, 'No se pudo guardar la compra');
    } finally {
      this.saving = false;
    }
  }

  // ---------- Detalle ----------

  async openDetail(p: any) {
    try {
      this.ticketBroken = false;
      this.ticketZoom = false;
      this.detail = (await this.api.get('purchases/show.php', { id: p.id })).purchase;
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async remove(p: any) {
    const ok = await this.ui.confirm(
      'Eliminar compra',
      'Se quitarán también sus entradas de inventario. Esta acción no se puede deshacer.',
      'Eliminar',
      true
    );
    if (!ok) return;
    try {
      await this.api.delete('purchases/delete.php', { id: p.id });
      this.detail = null;
      this.ui.success('Compra eliminada');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }
}
