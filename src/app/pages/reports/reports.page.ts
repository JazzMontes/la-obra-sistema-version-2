// Reportes de un periodo: ventas, utilidad, compras, gastos, mermas y corte de caja.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { parseServerDate, todayIso } from '../../shared/format.pipes';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

type Preset = 'today' | 'week' | 'month' | 'custom';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-reports',
  templateUrl: 'reports.page.html',
  styleUrls: ['reports.page.scss'],
  standalone: false,
})
export class ReportsPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  preset: Preset = 'today';
  from = todayIso();
  to = todayIso();
  report: any = null;
  loading = true;
  counted: number | null = null;

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  setPreset(p: Preset) {
    this.preset = p;
    const now = new Date();
    if (p === 'today') {
      this.from = this.to = todayIso();
    } else if (p === 'week') {
      this.from = todayIso(-6);
      this.to = todayIso();
    } else if (p === 'month') {
      this.from = todayIso(-(now.getDate() - 1));
      this.to = todayIso();
    }
    if (p !== 'custom') this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.report = (await this.api.get('reports/summary.php', { from: this.from, to: this.to })).report;
      this.counted = null;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo generar el reporte'));
    } finally {
      this.loading = false;
    }
  }

  get t(): any {
    return this.report?.totals ?? {};
  }

  get topProducts(): any[] {
    return this.memo.get('top', [this.report], () => (this.report?.products ?? []).slice(0, 8));
  }

  get maxDaily(): number {
    return Math.max(1, ...(this.report?.daily ?? []).map((d: any) => d.sales));
  }

  max(list: any[], key: string): number {
    return Math.max(1, ...(list ?? []).map(r => Number(r[key]) || 0));
  }

  dayLabel(d: string): string {
    const date = parseServerDate(d);
    return date ? new Intl.DateTimeFormat('es-MX', { weekday: 'short', day: 'numeric' }).format(date) : d;
  }

  get cashDifference(): number | null {
    if (this.counted === null || (this.counted as any) === '' || !this.report) return null;
    return Math.round((Number(this.counted) - this.report.cash_cut.expected_cash) * 100) / 100;
  }

  get netResult(): number {
    return (this.t.gross_profit ?? 0) - (this.t.expenses ?? 0) - (this.t.waste ?? 0);
  }

  print() {
    window.print();
  }
}
