// "Cómo reparto mi venta": la configuración que se toca cada varios meses.
//   venta del día − gastos fijos = sobrante → a cada apartado le toca su % del sobrante.
// También: cuentas de efectivo/banco, a qué cuenta cae cada método de pago y el redondeo.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';

interface Row {
  id: number | null;
  name: string;
  kind: 'cash' | 'bank' | 'fixed' | 'percent';
  value: number | null;
  balance?: number;
  original?: string;
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-money-settings',
  templateUrl: 'money-settings.page.html',
  styleUrls: ['money-settings.page.scss'],
  standalone: false,
})
export class MoneySettingsPage {
  private readonly refresher = autoRefresh();

  loading = true;
  saving = false;
  rows: Row[] = [];
  settings: any = { round_step: 5, round_mode: 'down', source_account_id: null, methods: [] };
  example = 2000;

  readonly roundModes = [
    { value: 'down', label: 'Hacia abajo' },
    { value: 'nearest', label: 'Al más cercano' },
    { value: 'up', label: 'Hacia arriba' },
    { value: 'none', label: 'Sin redondear' },
  ];
  readonly roundSteps = [1, 5, 10, 50, 100];

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const r = await this.api.get('money/summary');
      this.rows = r.accounts
        .filter((a: any) => a.status === 'active')
        .map((a: any) => {
          const row: Row = { id: a.id, name: a.name, kind: a.kind, value: Number(a.value), balance: Number(a.balance) };
          row.original = this.key(row);
          return row;
        });
      this.settings = r.settings;
      // Sugerencia de ejemplo: lo que se vendió hoy, o $2,000
      if (Number(r.today?.total_sales) > 0) this.example = Math.round(Number(r.today.total_sales));
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo cargar la configuración'));
    } finally {
      this.loading = false;
    }
  }

  private key(r: Row): string {
    return `${r.name.trim()}|${r.kind}|${Number(r.value) || 0}`;
  }

  get money(): Row[] {
    return this.rows.filter(r => r.kind === 'cash' || r.kind === 'bank');
  }
  get fixed(): Row[] {
    return this.rows.filter(r => r.kind === 'fixed');
  }
  get percent(): Row[] {
    return this.rows.filter(r => r.kind === 'percent');
  }
  get percentTotal(): number {
    return this.percent.reduce((s, r) => s + (Number(r.value) || 0), 0);
  }
  get fixedTotal(): number {
    return this.fixed.reduce((s, r) => s + (Number(r.value) || 0), 0);
  }

  // ---------- Ejemplo en vivo ----------
  get exLeft(): number {
    return Math.max((Number(this.example) || 0) - this.fixedTotal, 0);
  }
  exPart(r: Row): number {
    return this.round((this.exLeft * (Number(r.value) || 0)) / 100);
  }
  get exRest(): number {
    return this.exLeft - this.percent.reduce((s, r) => s + this.exPart(r), 0);
  }
  private round(v: number): number {
    const step = Number(this.settings.round_step) || 1;
    switch (this.settings.round_mode) {
      case 'none': return Math.round(v * 100) / 100;
      case 'up': return Math.ceil(v / step) * step;
      case 'nearest': return Math.round(v / step) * step;
      default: return Math.floor(v / step) * step;
    }
  }

  add(kind: Row['kind']) {
    const names: Record<string, string> = { fixed: 'Nuevo gasto fijo', percent: 'Nuevo apartado', cash: 'Otra caja', bank: 'Otra cuenta' };
    this.rows.push({ id: null, name: names[kind], kind, value: kind === 'percent' ? 5 : kind === 'fixed' ? 0 : null, original: '' });
  }

  async remove(r: Row) {
    if (!r.id) {
      this.rows = this.rows.filter(x => x !== r);
      return;
    }
    const ok = await this.ui.confirm(
      `Quitar "${r.name}"`,
      'Deja de usarse desde hoy. Su historial se conserva. Si todavía tiene dinero, primero pásalo a otra cuenta.',
      'Quitar',
      true
    );
    if (!ok) return;
    try {
      await this.api.post('money/account-archive', { id: r.id });
      this.rows = this.rows.filter(x => x !== r);
      this.ui.success('Quitado');
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async save() {
    if (this.saving) return;
    for (const r of this.rows) {
      if (!r.name.trim()) return this.ui.error('Hay una fila sin nombre');
      if ((r.kind === 'fixed' || r.kind === 'percent') && !(Number(r.value) >= 0)) return this.ui.error(`Revisa el valor de "${r.name}"`);
    }
    if (this.percentTotal > 100) return this.ui.error('Los porcentajes suman más de 100 %');
    this.saving = true;
    try {
      for (const r of this.rows) {
        if (r.id && this.key(r) === r.original) continue;
        await this.api.post('money/account-save', {
          id: r.id,
          name: r.name.trim(),
          kind: r.kind,
          value: r.kind === 'fixed' || r.kind === 'percent' ? Math.round(Number(r.value) * 100) / 100 : 0,
        });
      }
      await this.api.post('money/settings', {
        round_step: Number(this.settings.round_step),
        round_mode: this.settings.round_mode,
        source_account_id: this.settings.source_account_id,
        methods: (this.settings.methods || []).map((m: any) => ({ id: m.id, account_id: m.account_id })),
      });
      this.ui.success('Guardado. Se usa desde el próximo corte.');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.saving = false;
    }
  }
}
