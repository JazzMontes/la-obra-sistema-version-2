// Gastos y salidas de caja que no son compras de insumos (gas, limpieza, propinas, etc.).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { todayIso } from '../../shared/format.pipes';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-expenses',
  templateUrl: 'expenses.page.html',
  styleUrls: ['expenses.page.scss'],
  standalone: false,
})
export class ExpensesPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  readonly suggestions = ['Gas', 'Artículos de limpieza', 'Hielo', 'Transporte', 'Mantenimiento', 'Propinas'];

  expenses: any[] = [];
  loading = true;
  from = todayIso(-6);
  to = todayIso();
  showCancelled = false;

  open = false;
  editing: any = null;
  form: any = {};
  saving = false;
  formError = '';

  cancelling: any = null;
  cancelReason = '';
  history: any[] | null = null;

  constructor(private api: ApiService, private ui: UiService, private auth: Auth) {}

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const params = this.isAdmin ? { date_from: this.from, date_to: this.to } : {};
      this.expenses = (await this.api.get('expenses/index.php', params)).expenses;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar los gastos'));
    } finally {
      this.loading = false;
    }
  }

  get visible(): any[] {
    return this.memo.get('visible', [this.expenses, this.showCancelled], () => this.expenses.filter(e => this.showCancelled || e.status === 'active'));
  }

  get total(): number {
    return this.expenses.filter(e => e.status === 'active').reduce((s, e) => s + Number(e.amount), 0);
  }

  openNew() {
    this.editing = null;
    this.form = { amount: null, reason: '', change_reason: '' };
    this.formError = '';
    this.history = null;
    this.open = true;
  }

  async openEdit(e: any) {
    if (e.status !== 'active') return;
    this.editing = e;
    this.form = { amount: Number(e.amount), reason: e.reason, change_reason: '' };
    this.formError = '';
    this.history = null;
    this.open = true;
    if (this.isAdmin) {
      try {
        this.history = (await this.api.get('expenses/history.php', { id: e.id })).history;
      } catch {
        this.history = null;
      }
    }
  }

  async save() {
    if (this.saving) return;
    this.formError = '';
    if (!(Number(this.form.amount) > 0)) return void (this.formError = 'Indica el monto');
    if (!String(this.form.reason || '').trim()) return void (this.formError = 'Escribe el concepto');
    this.saving = true;
    try {
      const body = { amount: Math.round(Number(this.form.amount) * 100) / 100, reason: String(this.form.reason).trim() };
      if (this.editing) {
        await this.api.patch('expenses/update.php', { id: this.editing.id, ...body, change_reason: this.form.change_reason || null });
      } else {
        await this.api.post('expenses/create.php', body);
      }
      this.open = false;
      this.ui.success(this.editing ? 'Gasto actualizado' : 'Gasto registrado');
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e, 'No se pudo guardar el gasto');
    } finally {
      this.saving = false;
    }
  }

  askCancel() {
    this.cancelling = this.editing;
    this.cancelReason = '';
    this.open = false;
  }

  async confirmCancel() {
    if (!this.cancelReason.trim()) return this.ui.error('Escribe el motivo de la cancelación');
    try {
      await this.api.patch('expenses/cancel.php', { id: this.cancelling.id, cancellation_reason: this.cancelReason.trim() });
      this.cancelling = null;
      this.ui.success('Gasto cancelado');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }
}
