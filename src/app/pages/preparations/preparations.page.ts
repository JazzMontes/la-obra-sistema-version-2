// Preparaciones: lo que se produce con insumos (ej. carne preparada) y cuánto rinde.
// Su costo por porción sale de las compras y se usa en las recetas de los productos.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

export const YIELD_UNITS: Record<string, string> = { portion: 'porción', piece: 'pieza', g: 'g', ml: 'ml' };

interface Ingredient { input_id: number | null; quantity: number | null; is_estimated: boolean; }

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-preparations',
  templateUrl: 'preparations.page.html',
  styleUrls: ['preparations.page.scss'],
  standalone: false,
})
export class PreparationsPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  readonly yieldUnits = YIELD_UNITS;
  readonly yieldKeys = Object.keys(YIELD_UNITS);

  list: any[] = [];
  inputs: any[] = [];
  loading = true;
  query = '';

  formOpen = false;
  editingId: number | null = null;
  form: any = {};
  ingredients: Ingredient[] = [];
  saving = false;
  formError = '';

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    try {
      const [p, inv] = await Promise.all([this.api.get('preparations/index.php'), this.api.get('inventory/index.php')]);
      this.list = p.preparations;
      this.inputs = inv.inventory.filter((i: any) => i.status === 'active');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar las preparaciones'));
    } finally {
      this.loading = false;
    }
  }

  get visible(): any[] {
    return this.memo.get('visible', [this.list, this.query], () => {
      const q = this.query.trim().toLowerCase();
      return this.list.filter(p => !q || p.name.toLowerCase().includes(q));
    });
  }

  unitLabel(u: string, qty = 1): string {
    const label = YIELD_UNITS[u] ?? u;
    if (qty === 1 || u === 'g' || u === 'ml') return label;
    return label === 'porción' ? 'porciones' : label + 's';
  }

  input(id: number | null): any {
    return this.inputs.find(i => Number(i.id) === Number(id));
  }

  // ---------- Formulario ----------

  openNew() {
    this.editingId = null;
    this.form = { name: '', description: '', yield_quantity: null, yield_unit: 'portion', yield_estimated: false };
    this.ingredients = [{ input_id: null, quantity: null, is_estimated: false }];
    this.formError = '';
    this.formOpen = true;
  }

  openEdit(p: any) {
    this.editingId = p.id;
    this.form = {
      name: p.name,
      description: p.description ?? '',
      yield_quantity: Number(p.yield_quantity),
      yield_unit: p.yield_unit,
      yield_estimated: !!p.yield_estimated,
    };
    this.ingredients = p.inputs.map((i: any) => ({ input_id: Number(i.input_id), quantity: Number(i.quantity), is_estimated: !!i.is_estimated }));
    this.formError = '';
    this.formOpen = true;
  }

  addIngredient() {
    this.ingredients.push({ input_id: null, quantity: null, is_estimated: false });
  }

  removeIngredient(i: number) {
    this.ingredients.splice(i, 1);
  }

  ingredientCost(g: Ingredient): number | null {
    const c = this.input(g.input_id)?.unit_cost;
    return c === null || c === undefined || !g.quantity ? null : Number(c) * Number(g.quantity);
  }

  get batchCost(): number | null {
    const parts = this.ingredients.filter(g => g.input_id);
    if (!parts.length) return null;
    let sum = 0;
    for (const g of parts) {
      const c = this.ingredientCost(g);
      if (c === null) return null;
      sum += c;
    }
    return sum;
  }

  get unitCost(): number | null {
    const b = this.batchCost;
    return b === null || !(Number(this.form.yield_quantity) > 0) ? null : b / Number(this.form.yield_quantity);
  }

  get missingPrices(): string[] {
    const names = this.ingredients.filter(g => g.input_id && this.input(g.input_id)?.unit_cost === null).map(g => this.input(g.input_id).name);
    return this.memo.get('missing', [names.join('|')], () => names);
  }

  async save() {
    if (this.saving) return;
    this.formError = '';
    const items = this.ingredients.filter(g => g.input_id);
    if (!String(this.form.name || '').trim()) return void (this.formError = 'Escribe el nombre de la preparación');
    if (!(Number(this.form.yield_quantity) > 0)) return void (this.formError = 'Indica cuánto rinde');
    if (!items.length) return void (this.formError = 'Agrega al menos un ingrediente');
    const ids = items.map(g => g.input_id);
    if (new Set(ids).size !== ids.length) return void (this.formError = 'Hay un ingrediente repetido');
    if (items.some(g => !(Number(g.quantity) > 0))) return void (this.formError = 'Indica la cantidad de cada ingrediente');
    const body: any = {
      name: String(this.form.name).trim(),
      description: String(this.form.description || '').trim(),
      yield_quantity: Number(this.form.yield_quantity),
      yield_unit: this.form.yield_unit,
      yield_estimated: !!this.form.yield_estimated,
      inputs: items.map(g => ({ input_id: g.input_id, quantity: Number(g.quantity), is_estimated: g.is_estimated })),
    };
    this.saving = true;
    try {
      if (this.editingId) await this.api.patch('preparations/update.php', { id: this.editingId, ...body });
      else await this.api.post('preparations/create.php', body);
      this.formOpen = false;
      this.ui.success('Preparación guardada');
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e, 'No se pudo guardar la preparación');
    } finally {
      this.saving = false;
    }
  }

  async remove() {
    const p = this.list.find(x => x.id === this.editingId);
    if (!p) return;
    const ok = await this.ui.confirm('Eliminar preparación', `¿Eliminar "${p.name}"? Si algún producto la usa, primero quítala de su receta.`, 'Eliminar', true);
    if (!ok) return;
    try {
      await this.api.delete('preparations/delete.php', { id: p.id });
      this.formOpen = false;
      this.ui.success('Preparación eliminada');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }
}
