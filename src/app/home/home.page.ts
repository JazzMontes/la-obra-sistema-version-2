// Inicio: ventas del día, pedidos pendientes, alertas de inventario y accesos rápidos.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../services/api';
import { Auth } from '../services/auth';
import { autoRefresh } from '../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
  standalone: false,
})
export class HomePage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  user: any = null;
  summary: any = null;
  loading = true;
  error = '';

  readonly flow = [
    { n: 1, title: 'Insumos', text: 'Lo que utilizas y su unidad', url: '/inputs', icon: 'inputs' },
    { n: 2, title: 'Compras', text: 'Alimentan inventario y costos', url: '/purchases', icon: 'purchases' },
    { n: 3, title: 'Preparaciones', text: 'Lo que produces y su rendimiento', url: '/preparations', icon: 'preparations' },
    { n: 4, title: 'Productos y recetas', text: 'Qué lleva cada producto', url: '/products', icon: 'products' },
    { n: 5, title: 'Costos', text: 'Costo contra precio de venta', url: '/costs', icon: 'costs' },
    { n: 6, title: 'Punto de venta', text: 'Al entregar se descuenta inventario', url: '/pos', icon: 'pos' },
    { n: 7, title: 'Inventario y reportes', text: 'Existencias, mermas y corte', url: '/inventory', icon: 'inventory' },
  ];

  constructor(private api: ApiService, private auth: Auth) {}

  get isAdmin(): boolean {
    return this.user?.role === 'admin';
  }

  get firstName(): string {
    return String(this.user?.name || '').split(' ')[0];
  }

  get today(): string {
    const s = new Intl.DateTimeFormat('es-MX', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date());
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  get salesDelta(): number | null {
    const t = this.summary?.today;
    if (!t || !t.yesterday_sales) return null;
    return Math.round(((t.sales - t.yesterday_sales) / t.yesterday_sales) * 100);
  }

  ionViewWillEnter() {
    this.user = this.auth.getStoredUser();
    this.load();
  }

  async load(event?: any) {
    this.error = '';
    try {
      this.summary = (await this.api.get('dashboard/summary.php')).summary;
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo cargar el resumen');
    } finally {
      this.loading = false;
      event?.target?.complete();
    }
  }
}
