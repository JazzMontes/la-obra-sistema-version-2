// Estructura general: menú lateral, avisos, confirmaciones, estado de conexión
// y la ventana de diagnóstico cuando no hay respuesta del servidor.
import { ChangeDetectionStrategy, Component, NgZone, OnDestroy } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { MenuController } from '@ionic/angular';
import { ApiDiagnosticsService } from './services/api-diagnostics';
import { UiService } from './services/ui';
import { Auth } from './services/auth';
import { BILLING_EVENT, BillingService } from './services/billing';
import { RenderService, autoRefresh } from './services/render';
import { Memo } from './shared/memo';
import { NetworkService } from './services/network';

// feature: función del plan del negocio que necesita la pantalla; si no está vigente se muestra con candado
interface NavItem { label: string; icon: string; url: string; admin?: boolean; feature?: string; locked?: boolean; }
interface NavGroup { title: string; items: NavItem[]; }

const NAV: NavGroup[] = [
  { title: '', items: [{ label: 'Inicio', icon: 'home', url: '/home' }] },
  {
    // Operación del empleado: vender, entregar pedidos y cortar caja
    title: 'Ventas y caja',
    items: [
      { label: 'Punto de venta', icon: 'pos', url: '/pos', feature: 'ventas' },
      { label: 'Pedidos', icon: 'orders', url: '/orders', feature: 'ventas' },
      { label: 'Corte de caja', icon: 'cash', url: '/cash-cut', feature: 'ventas' },
    ],
  },
  {
    title: 'Operación',
    items: [
      { label: 'Asistencia', icon: 'pin', url: '/attendance', feature: 'asistencia' },
      { label: 'Gastos', icon: 'expenses', url: '/expenses', feature: 'gastos' },
      { label: 'Mermas', icon: 'waste', url: '/waste', feature: 'inventario' },
      { label: 'Inventario', icon: 'inventory', url: '/inventory', feature: 'inventario' },
      { label: 'Compras', icon: 'purchases', url: '/purchases', admin: true, feature: 'inventario' },
    ],
  },
  {
    title: 'Menú y recetas',
    items: [
      { label: 'Productos', icon: 'products', url: '/products', admin: true, feature: 'ventas' },
      { label: 'Preparaciones', icon: 'preparations', url: '/preparations', admin: true, feature: 'recetas' },
      { label: 'Insumos', icon: 'inputs', url: '/inputs', admin: true, feature: 'inventario|recetas' },
      { label: 'Categorías', icon: 'categories', url: '/categories', admin: true, feature: 'ventas' },
    ],
  },
  {
    title: 'Análisis',
    items: [
      { label: 'Costos', icon: 'costs', url: '/costs', admin: true, feature: 'recetas' },
      { label: 'Reportes', icon: 'reports', url: '/reports', admin: true, feature: 'reportes' },
    ],
  },
  {
    title: 'Administración',
    items: [
      { label: 'Plan y créditos', icon: 'star', url: '/billing' },
      { label: 'Usuarios', icon: 'users', url: '/users', admin: true },
      { label: 'Métodos de pago', icon: 'card', url: '/payment-methods', admin: true, feature: 'ventas' },
      { label: 'Validar estudiante', icon: 'student', url: '/student-validation' },
      { label: 'Servidor', icon: 'server', url: '/data-origins' },
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
  showTech = false;
  // Cambió el nombre o la foto de perfil (pantalla Mi perfil)
  private onUserUpdated = () => {
    this.user = this.auth.getStoredUser();
    this.render.schedule();
  };
  // Cambió el plan, los créditos o venció algo: se vuelven a calcular los candados del menú
  private billingVersion = 0;
  private onBillingUpdated = () => {
    this.billingVersion++;
    this.render.schedule();
  };

  constructor(
    public diagnostics: ApiDiagnosticsService,
    public ui: UiService,
    private auth: Auth,
    private router: Router,
    private menu: MenuController,
    private zone: NgZone,
    private render: RenderService,
    public billing: BillingService,
    // Sensor de red: ícono de conexión en los encabezados y panel "Estado de conexión"
    public net: NetworkService
  ) {
    // Se crea aquí para que funcione en toda la app (ver services/render.ts)
    void render;
    // Al abrir la app siempre se pide iniciar sesión: se borra la sesión guardada en el dispositivo.
    // (El catálogo y los cambios pendientes de Productos se conservan y se sincronizan al volver a entrar.)
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    billing.clear();
    this.user = null;
    this.router.events.subscribe(e => {
      if (e instanceof NavigationEnd) {
        this.url = e.urlAfterRedirects.split('?')[0];
        this.user = this.auth.getStoredUser();
        render.schedule();
      }
    });
    window.addEventListener('la-obra-user-updated', this.onUserUpdated);
    window.addEventListener(BILLING_EVENT, this.onBillingUpdated);
  }

  ngOnDestroy() {
    window.removeEventListener('la-obra-user-updated', this.onUserUpdated);
    window.removeEventListener(BILLING_EVENT, this.onBillingUpdated);
  }

  // Lo usa la barra "Sin conexión"
  get online(): boolean {
    return this.net.online;
  }

  get showMenu(): boolean {
    return !!this.user && !NO_MENU.includes(this.url);
  }

  get isAdmin(): boolean {
    return this.user?.role === 'admin';
  }

  get groups(): NavGroup[] {
    return this.memo.get('groups', [this.isAdmin, this.billingVersion], () =>
      NAV.map(g => ({
        ...g,
        items: g.items
          .filter(i => !i.admin || this.isAdmin)
          .map(i => ({ ...i, locked: !!i.feature && !i.feature.split('|').some(k => this.billing.isActive(k)) })),
      })).filter(g => g.items.length)
    );
  }

  // Resumen del plan del negocio para el pie del menú
  get planLabel(): string {
    const s = this.billing.status;
    if (!s) return '';
    const plan = s.subscription
      ? s.subscription.plan_name + (s.subscription.cycle === 'trial' ? ' (prueba)' : '')
      : s.effective_plan?.name || 'Plan gratuito';
    return `${plan} · ${s.credits} créditos`;
  }

  get planWarning(): boolean {
    const s = this.billing.status;
    return !!s?.subscription && (s.subscription.days_left <= 5 || !!s.subscription.cancel_requested_at);
  }

  get initials(): string {
    return String(this.user?.name || '?').split(/\s+/).map((w: string) => w[0]).slice(0, 2).join('');
  }

  isActive(url: string): boolean {
    return this.url === url || this.url.startsWith(url + '/');
  }

  async go(url: string, item?: NavItem) {
    // Una pantalla con candado lleva a Plan y créditos con esa función marcada
    if (item?.locked && item.feature) {
      await this.router.navigate(['/billing'], { queryParams: { feature: item.feature.split('|')[0] } });
    } else {
      await this.router.navigateByUrl(url);
    }
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
    this.billing.clear();
    await this.menu.close();
    await this.router.navigateByUrl('/login', { replaceUrl: true });
  }

  closeDiagnostics() {
    this.showTech = false;
    this.diagnostics.closeModal();
  }
}
