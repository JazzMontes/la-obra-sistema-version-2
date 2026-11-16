// Costos: cuánto cuesta preparar cada producto según sus recetas y las últimas compras,
// comparado con su precio de venta. No se captura ningún precio aquí.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-costs',
  templateUrl: 'costs.page.html',
  styleUrls: ['costs.page.scss'],
  standalone: false,
})
export class CostsPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  products: any[] = [];
  summary: any = null;
  loading = true;
  mode: 'local' | 'takeaway' = 'local';
  sort: 'margin' | 'name' | 'cost' = 'margin';
  detail: any = null;

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const r = await this.api.get('costs/index.php', { delivery_mode: this.mode });
      this.products = r.products;
      this.summary = r.summary;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron calcular los costos'));
    } finally {
      this.loading = false;
    }
  }

  setMode(m: 'local' | 'takeaway') {
    this.mode = m;
    this.load();
  }

  get sorted(): any[] {
    return this.memo.get('sorted', [this.products, this.sort], () => this.computeSorted());
  }

  private computeSorted(): any[] {
    const list = [...this.products];
    if (this.sort === 'name') return list.sort((a, b) => a.name.localeCompare(b.name));
    if (this.sort === 'cost') return list.sort((a, b) => (b.standard_cost ?? -1) - (a.standard_cost ?? -1));
    // Por margen: primero los de menor margen (los que requieren atención)
    return list.sort((a, b) => (a.gross_margin ?? 999) - (b.gross_margin ?? 999));
  }

  imageUrl(p: any): string | null {
    return this.api.fileUrl(p.image_path);
  }

  level(m: number | null): string {
    if (m === null) return '';
    return m >= 60 ? 'good' : m >= 35 ? 'mid' : 'bad';
  }

  share(c: any, total: number | null): number {
    return !total || c.cost === null ? 0 : Math.round((c.cost / total) * 100);
  }
}
