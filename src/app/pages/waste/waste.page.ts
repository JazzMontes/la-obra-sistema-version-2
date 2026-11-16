// Mermas: pérdidas o desperdicios de insumos, preparaciones o productos terminados.
// Se descuentan del inventario y se valúan con el costo actual.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { todayIso } from '../../shared/format.pipes';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

type Kind = 'input' | 'preparation' | 'product';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-waste',
  templateUrl: 'waste.page.html',
  styleUrls: ['waste.page.scss'],
  standalone: false,
})
export class WastePage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  readonly classifications = ['Caducado', 'Se cayó o derramó', 'Mal preparado', 'Devolución del cliente', 'Sobrante del día', 'Otro'];
  readonly kinds: { key: Kind; label: string }[] = [
    { key: 'input', label: 'Insumo' },
    { key: 'preparation', label: 'Preparación' },
    { key: 'product', label: 'Producto' },
  ];

  records: any[] = [];
  loading = true;
  from = todayIso(-6);
  to = todayIso();

  inputs: any[] = [];
  preparations: any[] = [];
  products: any[] = [];

  open = false;
  form: any = {};
  saving = false;
  formError = '';

  constructor(private api: ApiService, private ui: UiService, private auth: Auth) {}

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  ionViewWillEnter() {
    this.load();
    this.loadCatalogs();
  }

  async load() {
    this.loading = true;
    try {
      const params = this.isAdmin ? { date_from: this.from, date_to: this.to } : {};
      this.records = (await this.api.get('waste/index.php', params)).waste_records;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar las mermas'));
    } finally {
      this.loading = false;
    }
  }

  async loadCatalogs() {
    try {
      const [inv, prep, prod] = await Promise.all([
        this.api.get('inventory/index.php'),
        this.api.get('preparations/index.php'),
        this.api.get('products/index.php'),
      ]);
      this.inputs = inv.inventory.filter((i: any) => i.status === 'active');
      this.preparations = prep.preparations;
      this.products = prod.products.filter((p: any) => p.status === 'active');
    } catch {
      // Se reintenta al abrir la pantalla
    }
  }

  get totalCost(): number {
    return this.records.reduce((s, r) => s + (Number(r.estimated_total_cost) || 0), 0);
  }

  get byClass(): { name: string; cost: number; count: number }[] {
    return this.memo.get('byClass', [this.records], () => this.computeByClass());
  }

  private computeByClass(): { name: string; cost: number; count: number }[] {
    const map = new Map<string, { name: string; cost: number; count: number }>();
    for (const r of this.records) {
      const e = map.get(r.classification) ?? { name: r.classification, cost: 0, count: 0 };
      e.cost += Number(r.estimated_total_cost) || 0;
      e.count++;
      map.set(r.classification, e);
    }
    return [...map.values()].sort((a, b) => b.cost - a.cost);
  }

  get maxClass(): number {
    return Math.max(1, ...this.byClass.map(c => c.cost));
  }

  kindLabel(k: string): string {
    return this.kinds.find(x => x.key === k)?.label ?? k;
  }

  // ---------- Registro ----------

  openNew() {
    this.form = { affected_type: 'input', affected_id: null, quantity: null, is_approximate: false, waste_date: todayIso(), classification: '', reason: '' };
    this.formError = '';
    this.open = true;
  }

  get options(): any[] {
    return this.form.affected_type === 'input' ? this.inputs : this.form.affected_type === 'preparation' ? this.preparations : this.products;
  }

  get selected(): any {
    return this.options.find(o => Number(o.id) === Number(this.form.affected_id));
  }

  get unit(): string {
    const s = this.selected;
    if (!s) return '';
    if (this.form.affected_type === 'input') return s.unit;
    if (this.form.affected_type === 'preparation') return ({ portion: 'porción', piece: 'pieza', g: 'g', ml: 'ml' } as any)[s.yield_unit] ?? s.yield_unit;
    return 'pieza';
  }

  get estimate(): number | null {
    const s = this.selected;
    const q = Number(this.form.quantity);
    if (!s || !(q > 0)) return null;
    const unitCost = this.form.affected_type === 'product' ? null : s.unit_cost;
    return unitCost === null || unitCost === undefined ? null : Number(unitCost) * q;
  }

  setKind(k: Kind) {
    this.form.affected_type = k;
    this.form.affected_id = null;
  }

  async save() {
    if (this.saving) return;
    this.formError = '';
    const f = this.form;
    if (!f.affected_id) return void (this.formError = 'Elige qué se perdió');
    if (!(Number(f.quantity) > 0)) return void (this.formError = 'Indica la cantidad');
    if (!f.classification) return void (this.formError = 'Elige una clasificación');
    if (!String(f.reason || '').trim()) return void (this.formError = 'Describe brevemente lo que pasó');
    this.saving = true;
    try {
      const r = await this.api.post('waste/create.php', {
        affected_type: f.affected_type,
        affected_id: Number(f.affected_id),
        quantity: Number(f.quantity),
        is_approximate: !!f.is_approximate,
        waste_date: f.waste_date,
        classification: f.classification,
        reason: String(f.reason).trim(),
      });
      const cost = r.waste?.estimated_total_cost;
      this.open = false;
      this.ui.success(cost ? `Merma registrada ($${Number(cost).toFixed(2)})` : 'Merma registrada');
      await Promise.all([this.load(), this.loadCatalogs()]);
    } catch (e) {
      this.formError = errorMessage(e, 'No se pudo registrar la merma');
    } finally {
      this.saving = false;
    }
  }
}
