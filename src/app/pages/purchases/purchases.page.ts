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

interface Line {
  input_id: number | null;
  package_type: string;
  quantity: number | null;
  content_per_package: number | null;
  unit_cost: number | null;
}

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
  ticket: string | null = null;      // vista previa
  newTicket: string | null | undefined = undefined; // undefined = sin cambios, null = quitar
  saving = false;
  formError = '';

  // Alta rápida de insumo desde un renglón
  inputModalOpen = false;
  inputForLine: Line | null = null;
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
      payment_method_id: this.methods[0]?.id ?? null,
      change_reason: '',
    };
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
        payment_method_id: full.payment_method_id,
        change_reason: '',
      };
      this.lines = full.items.map((i: any) => ({
        input_id: Number(i.input_id),
        package_type: this.packLabel(this.input(Number(i.input_id))),
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
    return { input_id: null, package_type: '', quantity: 1, content_per_package: null, unit_cost: null };
  }

  addLine() {
    this.lines.push(this.emptyLine());
  }

  removeLine(i: number) {
    this.lines.splice(i, 1);
    if (!this.lines.length) this.addLine();
  }

  onInputChange(line: Line, value: any) {
    if (Number(value) === NEW_INPUT) {
      line.input_id = null;
      this.inputForLine = line;
      this.inputModalOpen = true;
      return;
    }
    line.input_id = value === null ? null : Number(value);
    // Prellenar con la última presentación con que se compró este insumo
    const inp = this.input(line.input_id);
    if (inp) {
      line.package_type = this.packLabel(inp);
      line.content_per_package = Number(inp.package_quantity) || 1;
    }
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
      this.inputForLine.package_type = '';
      this.inputForLine.content_per_package = 1;
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
    return (Number(l.quantity) || 0) * (Number(l.content_per_package) || 0);
  }

  lineUnitCost(l: Line): number | null {
    const base = this.lineBase(l);
    return base > 0 ? this.lineTotal(l) / base : null;
  }

  get total(): number {
    return this.lines.reduce((s, l) => s + this.lineTotal(l), 0);
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
    if (!this.form.payment_method_id) return void (this.formError = 'Elige el método de pago');
    if (!items.length) return void (this.formError = 'Agrega al menos un artículo');
    const ids = items.map(l => l.input_id);
    if (new Set(ids).size !== ids.length) return void (this.formError = 'Hay un insumo repetido; junta las cantidades en un solo renglón');
    for (const l of items) {
      const name = this.input(l.input_id)?.name ?? 'un artículo';
      if (!(Number(l.quantity) > 0)) return void (this.formError = `Indica la cantidad de ${name}`);
      if (!(Number(l.content_per_package) > 0)) return void (this.formError = `Indica el contenido por presentación de ${name}`);
      if (l.unit_cost === null || Number(l.unit_cost) < 0) return void (this.formError = `Indica el precio de ${name}`);
    }
    const body: any = {
      purchase_date: this.form.purchase_date,
      supplier: String(this.form.supplier || '').trim() || null,
      buyer: String(this.form.buyer || '').trim() || null,
      payment_method_id: Number(this.form.payment_method_id),
      items: items.map(l => ({
        input_id: l.input_id,
        package_type: String(l.package_type || '').trim() || null,
        quantity: Number(l.quantity),
        content_per_package: Number(l.content_per_package),
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
      this.ui.success(this.editingId ? 'Compra actualizada; inventario recalculado' : 'Compra registrada; inventario y costos actualizados');
      await this.load();
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
