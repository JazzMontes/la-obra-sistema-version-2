// Categorías del menú (bebidas, hamburguesas, postres…). Agrupan los productos en el punto de venta.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-categories',
  templateUrl: 'categories.page.html',
  styleUrls: ['categories.page.scss'],
  standalone: false,
})
export class CategoriesPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  list: any[] = [];
  loading = true;
  newName = '';
  editingId: number | null = null;
  editName = '';
  busy = false;

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    try {
      this.list = (await this.api.get('categories/index.php')).categories;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar las categorías'));
    } finally {
      this.loading = false;
    }
  }

  async add() {
    const name = this.newName.trim();
    if (!name || this.busy) return;
    this.busy = true;
    try {
      await this.api.post('categories/create.php', { name });
      this.newName = '';
      this.ui.success('Categoría agregada');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.busy = false;
    }
  }

  startEdit(c: any) {
    this.editingId = c.id;
    this.editName = c.name;
  }

  async saveEdit(c: any) {
    const name = this.editName.trim();
    if (!name) return;
    if (name === c.name) {
      this.editingId = null;
      return;
    }
    try {
      await this.api.patch('categories/update.php', { id: c.id, name });
      this.editingId = null;
      this.ui.success('Categoría actualizada');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async toggle(c: any) {
    try {
      await this.api.patch(c.status === 'active' ? 'categories/deactivate.php' : 'categories/activate.php', { id: c.id });
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async remove(c: any) {
    const ok = await this.ui.confirm('Eliminar categoría', `¿Eliminar "${c.name}"? Si tiene productos no se podrá; desactívala en su lugar.`, 'Eliminar', true);
    if (!ok) return;
    try {
      await this.api.delete('categories/delete.php', { id: c.id });
      this.ui.success('Categoría eliminada');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }
}
