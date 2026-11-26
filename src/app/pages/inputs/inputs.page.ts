// Insumos: lo que se utiliza (nombre, unidad con que se usa, cómo se compra y su costo).
// El costo sale de la última compra, pero se puede cambiar aquí (gana el más reciente).
import { ChangeDetectionStrategy, Component, ViewChild } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { InputFormComponent } from '../../shared/input-form.component';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-inputs',
  templateUrl: 'inputs.page.html',
  styleUrls: ['inputs.page.scss'],
  standalone: false,
})
export class InputsPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  @ViewChild(InputFormComponent) formCmp?: InputFormComponent;

  items: any[] = [];
  loading = true;
  query = '';
  filter: 'active' | 'inactive' | 'all' = 'active';
  modalOpen = false;
  editing: any = null;
  saving = false;

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  // "por cucharada, pieza"
  recipeUnits(i: any): string {
    return (i.units ?? []).filter((u: any) => u.use_in !== 'purchase').map((u: any) => u.name).join(', ');
  }

  // "paquete (20 rebanada) · kg (1000 g)"
  buyUnits(i: any): string {
    const n = (v: number) => String(+Number(v).toFixed(3));
    return (i.units ?? [])
      .filter((u: any) => u.use_in !== 'recipe')
      .map((u: any) => `${Number(u.unit_amount) !== 1 ? n(u.unit_amount) + ' ' : ''}${u.name} (${n(u.base_amount)} ${i.unit})`)
      .join(' · ');
  }

  async load() {
    try {
      this.items = (await this.api.get('inputs/index.php')).inputs;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar los insumos'));
    } finally {
      this.loading = false;
    }
  }

  get visible(): any[] {
    return this.memo.get('visible', [this.items, this.query, this.filter], () => {
      const q = this.query.trim().toLowerCase();
      return this.items.filter(i => (this.filter === 'all' || i.status === this.filter) && (!q || i.name.toLowerCase().includes(q)));
    });
  }

  count(status: string): number {
    return this.items.filter(i => status === 'all' || i.status === status).length;
  }

  openNew() {
    this.editing = null;
    this.modalOpen = true;
  }

  openEdit(item: any) {
    this.editing = item;
    this.modalOpen = true;
  }

  async save() {
    if (!this.formCmp) return;
    this.saving = true;
    const ok = await this.formCmp.submit();
    this.saving = false;
    if (ok) {
      this.modalOpen = false;
      this.ui.success(this.editing ? 'Insumo actualizado' : 'Insumo registrado');
      await this.load();
    }
  }

  async toggle(item: any) {
    const activate = item.status !== 'active';
    try {
      await this.api.patch(activate ? 'inputs/activate.php' : 'inputs/deactivate.php', { id: item.id });
      this.ui.success(activate ? 'Insumo activado' : 'Insumo desactivado');
      this.modalOpen = false;
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async remove(item: any) {
    const ok = await this.ui.confirm(
      'Eliminar insumo',
      `¿Eliminar "${item.name}" definitivamente? Si ya se usó en compras o recetas no se podrá; en ese caso desactívalo.`,
      'Eliminar',
      true
    );
    if (!ok) return;
    try {
      await this.api.delete('inputs/delete.php', { id: item.id });
      this.ui.success('Insumo eliminado');
      this.modalOpen = false;
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }
}
