// Estructura general: menú lateral, avisos, confirmaciones, estado de conexión
// y la ventana de diagnóstico cuando no hay respuesta del servidor.
import { ChangeDetectionStrategy, Component, NgZone, OnDestroy } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { MenuController } from '@ionic/angular';
import { ApiDiagnosticsService } from './services/api-diagnostics';
import { UiService } from './services/ui';
import { Auth } from './services/auth';
import { RenderService, autoRefresh } from './services/render';
import { Memo } from './shared/memo';
import { TOKEN_KEY, USER_KEY } from './services/storage-keys';

interface NavItem { label: string; icon: string; url: string; admin?: boolean; }
interface NavGroup { title: string; items: NavItem[]; }

const NAV: NavGroup[] = [
  { title: '', items: [{ label: 'Inicio', icon: 'home', url: '/home' }] },
  {
    title: 'Operación',
    items: [
      { label: 'Punto de venta', icon: 'pos', url: '/pos' },
      { label: 'Pedidos', icon: 'orders', url: '/orders' },
      { label: 'Compras', icon: 'purchases', url: '/purchases', admin: true },
      { label: 'Inventario', icon: 'inventory', url: '/inventory' },
      { label: 'Mermas', icon: 'waste', url: '/waste' },
      { label: 'Gastos', icon: 'expenses', url: '/expenses' },
    ],
  },
  {
    title: 'Menú y recetas',
    items: [
      { label: 'Productos', icon: 'products', url: '/products', admin: true },
      { label: 'Preparaciones', icon: 'preparations', url: '/preparations', admin: true },
      { label: 'Insumos', icon: 'inputs', url: '/inputs', admin: true },
      { label: 'Categorías', icon: 'categories', url: '/categories', admin: true },
    ],
  },
  {
    title: 'Análisis',
    items: [
      { label: 'Costos', icon: 'costs', url: '/costs', admin: true },
      { label: 'Reportes y corte', icon: 'reports', url: '/reports', admin: true },
    ],
  },
  {
    title: 'Administración',
    items: [
      { label: 'Usuarios', icon: 'users', url: '/users', admin: true },
      { label: 'Métodos de pago', icon: 'card', url: '/payment-methods', admin: true },
      { label: 'Validar estudiante', icon: 'student', url: '/student-validation' },
      { label: 'Conexión y respaldo', icon: 'server', url: '/data-origins' },
    ],
  },
];

const NO_MENU = ['/login', '/change-password'];

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-root',
  templateUrl: 'app.component.html',
  styleUrls: ['app.component.scss'],
  standalone: false,
})
export class AppComponent implements OnDestroy {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  user: any = null;
  url = '/';
  online = navigator.onLine;
  showTech = false;

  private onOnline = () => this.zone.run(() => (this.online = true));
  private onOffline = () => this.zone.run(() => (this.online = false));

  constructor(
    public diagnostics: ApiDiagnosticsService,
    public ui: UiService,
    private auth: Auth,
    private router: Router,
    private menu: MenuController,
    private zone: NgZone,
    render: RenderService
  ) {
    // Se crea aquí para que funcione en toda la app (ver services/render.ts)
    void render;
    // Al abrir la app siempre se pide iniciar sesión: se borra la sesión guardada en el dispositivo.
    // (El catálogo y los cambios pendientes de Productos se conservan y se sincronizan al volver a entrar.)
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
    this.user = null;
    this.router.events.subscribe(e => {
      if (e instanceof NavigationEnd) {
        this.url = e.urlAfterRedirects.split('?')[0];
        this.user = this.auth.getStoredUser();
        render.schedule();
      }
    });
    window.addEventListener('online', this.onOnline);
    window.addEventListener('offline', this.onOffline);
  }

  ngOnDestroy() {
    window.removeEventListener('online', this.onOnline);
    window.removeEventListener('offline', this.onOffline);
  }

  get showMenu(): boolean {
    return !!this.user && !NO_MENU.includes(this.url);
  }

  get isAdmin(): boolean {
    return this.user?.role === 'admin';
  }

  get groups(): NavGroup[] {
    return this.memo.get('groups', [this.isAdmin], () =>
      NAV.map(g => ({ ...g, items: g.items.filter(i => !i.admin || this.isAdmin) })).filter(g => g.items.length)
    );
  }

  get initials(): string {
    return String(this.user?.name || '?').split(/\s+/).map((w: string) => w[0]).slice(0, 2).join('');
  }

  isActive(url: string): boolean {
    return this.url === url || this.url.startsWith(url + '/');
  }

  async go(url: string) {
    await this.router.navigateByUrl(url);
    await this.menu.close();
  }

  async logout() {
    const ok = await this.ui.confirm('Cerrar sesión', '¿Quieres salir de tu cuenta en este dispositivo?', 'Cerrar sesión');
    if (!ok) return;
    try {
      await this.auth.logout();
    } catch {
      // Aunque el servidor no responda, la sesión local se borra.
    }
    this.user = null;
    await this.menu.close();
    await this.router.navigateByUrl('/login', { replaceUrl: true });
  }

  closeDiagnostics() {
    this.showTech = false;
    this.diagnostics.closeModal();
  }
}
