// Métodos de pago aceptados en ventas y compras. "Efectivo" calcula el cambio y entra en el corte.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-payment-methods',
  templateUrl: 'payment-methods.page.html',
  styleUrls: ['payment-methods.page.scss'],
  standalone: false,
})
export class PaymentMethodsPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  list: any[] = [];
  loading = true;
  newName = '';
  busy = false;

  constructor(private api: ApiService, private ui: UiService) {}

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    try {
      this.list = (await this.api.get('payment-methods/index.php')).payment_methods;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar los métodos de pago'));
    } finally {
      this.loading = false;
    }
  }

  isCash(m: any): boolean {
    return String(m.name).trim().toLowerCase() === 'efectivo';
  }

  async add() {
    const name = this.newName.trim();
    if (!name || this.busy) return;
    this.busy = true;
    try {
      await this.api.post('payment-methods/create.php', { name });
      this.newName = '';
      this.ui.success('Método agregado');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.busy = false;
    }
  }

  // Comisión de la terminal (porcentaje); aplica a los cobros que se hagan desde ahora
  async setFee(m: any, event: Event) {
    const input = event.target as HTMLInputElement;
    const raw = input.value.trim();
    const value = raw === '' ? 0 : Number(raw);
    if (!Number.isFinite(value) || value < 0 || value >= 100) {
      this.ui.error('La comisión debe ser un porcentaje entre 0 y 99.99');
      input.value = String(m.commission_percent ?? 0);
      return;
    }
    if (Math.abs(value - Number(m.commission_percent ?? 0)) < 0.001) return;
    try {
      const r = await this.api.patch('payment-methods/commission.php', { id: m.id, commission_percent: value });
      m.commission_percent = r.payment_method?.commission_percent ?? value;
      this.ui.success(value > 0 ? `Comisión de ${m.name}: ${value} %` : `${m.name} sin comisión`);
    } catch (e) {
      input.value = String(m.commission_percent ?? 0);
      this.ui.error(errorMessage(e));
    }
  }

  async toggle(m: any) {
    try {
      await this.api.patch('payment-methods/status.php', { id: m.id, status: m.status === 'active' ? 'inactive' : 'active' });
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async remove(m: any) {
    const ok = await this.ui.confirm('Eliminar método de pago', `¿Eliminar "${m.name}"? Si ya se usó en ventas o compras no se podrá; desactívalo en su lugar.`, 'Eliminar', true);
    if (!ok) return;
    try {
      await this.api.delete('payment-methods/delete.php', { id: m.id });
      this.ui.success('Método eliminado');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }
}
