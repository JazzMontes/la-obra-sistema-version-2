// Inventario: existencias calculadas a partir de compras, ventas entregadas, mermas y ajustes.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

const TYPES: Record<string, { label: string; icon: string }> = {
  purchase: { label: 'Compra', icon: 'purchases' },
  sale: { label: 'Venta entregada', icon: 'pos' },
  sale_reversal: { label: 'Venta cancelada', icon: 'refresh' },
  waste: { label: 'Merma', icon: 'waste' },
  adjustment: { label: 'Ajuste por conteo', icon: 'adjust' },
};

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-inventory',
  templateUrl: 'inventory.page.html',
  styleUrls: ['inventory.page.scss'],
  standalone: false,
})
export class InventoryPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  items: any[] = [];
  summary: any = null;
  loading = true;
  query = '';
  filter: 'all' | 'alert' = 'all';

  // Kárdex
  selected: any = null;
  movements: any[] = [];
  loadingMoves = false;

  // Ajuste
  adjustOpen = false;
  counted: number | null = null;
  note = '';
  minStock: number | null = null;
  saving = false;

  constructor(private api: ApiService, private ui: UiService, private auth: Auth) {}

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    try {
      const r = await this.api.get('inventory/index.php');
      this.items = r.inventory.filter((i: any) => i.status === 'active');
      this.summary = r.summary;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo cargar el inventario'));
    } finally {
      this.loading = false;
    }
  }

  get visible(): any[] {
    return this.memo.get('visible', [this.items, this.query, this.filter], () => {
      const q = this.query.trim().toLowerCase();
      return this.items.filter(i => (this.filter === 'all' || i.level !== 'ok') && (!q || i.name.toLowerCase().includes(q)));
    });
  }

  // Porcentaje de la barra: existencia contra el doble del mínimo (o contra sí misma si no hay mínimo)
  meter(i: any): number {
    if (i.stock <= 0) return 0;
    if (!i.min_stock) return 100;
    return Math.min(100, Math.round((i.stock / (i.min_stock * 2)) * 100));
  }

  type(t: string) {
    return TYPES[t] ?? { label: t, icon: 'info' };
  }

  async open(item: any) {
    this.selected = item;
    this.movements = [];
    this.loadingMoves = true;
    try {
      const r = await this.api.get('inventory/movements.php', { input_id: item.id });
      this.movements = r.movements;
      this.selected = { ...item, stock: r.stock };
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.loadingMoves = false;
    }
  }

  openAdjust() {
    this.counted = this.selected ? Math.max(0, Number(this.selected.stock)) : null;
    this.minStock = this.selected?.min_stock ?? null;
    this.note = '';
    this.adjustOpen = true;
  }

  get difference(): number {
    return this.counted === null ? 0 : Number(this.counted) - Number(this.selected?.stock ?? 0);
  }

  async saveAdjust() {
    if (this.saving || !this.selected) return;
    if (this.counted === null || Number(this.counted) < 0) {
      this.ui.error('Escribe la cantidad que contaste');
      return;
    }
    this.saving = true;
    try {
      const id = this.selected.id;
      if (Math.abs(this.difference) >= 0.0005) {
        await this.api.post('inventory/adjust.php', { input_id: id, counted_quantity: Number(this.counted), note: this.note });
      }
      const newMin = this.minStock === null || (this.minStock as any) === '' ? null : Number(this.minStock);
      if (newMin !== (this.selected.min_stock ?? null)) {
        await this.api.patch('inputs/update.php', { id, min_stock: newMin });
      }
      this.adjustOpen = false;
      this.ui.success('Inventario actualizado');
      await this.load();
      const fresh = this.items.find(i => i.id === id);
      if (fresh) await this.open(fresh);
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.saving = false;
    }
  }
}
