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
import { RemindersService } from './services/reminders';

interface NavItem { label: string; icon: string; url: string; admin?: boolean; }
interface NavGroup { title: string; items: NavItem[]; school?: boolean; }

// El menú sigue el día del puesto: vender → lo que pasa en el día → dinero → inventario →
// lo que se configura de vez en cuando. Lo que es solo para la escuela va al final, plegado.
const NAV: NavGroup[] = [
  { title: '', items: [{ label: 'Inicio', icon: 'home', url: '/home' }] },
  {
    title: 'Vender',
    items: [
      { label: 'Punto de venta', icon: 'pos', url: '/pos' },
      { label: 'Pedidos', icon: 'orders', url: '/orders' },
      { label: 'Corte de caja', icon: 'cash', url: '/cash-cut' },
    ],
  },
  {
    title: 'Día a día',
    items: [
      { label: 'Encargos y notas', icon: 'bag', url: '/notes' },
      { label: 'Gastos', icon: 'expenses', url: '/expenses' },
      { label: 'Mermas y pérdidas', icon: 'waste', url: '/waste' },
      { label: 'Asistencia', icon: 'pin', url: '/attendance' },
    ],
  },
  {
    title: 'Dinero',
    items: [{ label: 'Cuentas y apartados', icon: 'wallet', url: '/money', admin: true }],
  },
  {
    title: 'Inventario',
    items: [
      { label: 'Inventario', icon: 'inventory', url: '/inventory' },
      { label: 'Compras', icon: 'purchases', url: '/purchases', admin: true },
    ],
  },
  {
    title: 'Mi menú y costos',
    items: [
      { label: 'Productos', icon: 'products', url: '/products', admin: true },
      { label: 'Preparaciones', icon: 'preparations', url: '/preparations', admin: true },
      { label: 'Insumos', icon: 'inputs', url: '/inputs', admin: true },
      { label: 'Categorías', icon: 'categories', url: '/categories', admin: true },
      { label: 'Costos', icon: 'costs', url: '/costs', admin: true },
      { label: 'Reportes', icon: 'reports', url: '/reports', admin: true },
    ],
  },
  {
    title: 'Configuración',
    items: [
      { label: 'Cómo reparto mi venta', icon: 'pie', url: '/money-settings', admin: true },
      { label: 'Métodos de pago', icon: 'card', url: '/payment-methods', admin: true },
      { label: 'Usuarios', icon: 'users', url: '/users', admin: true },
    ],
  },
  {
    title: 'Escuela',
    school: true,
    items: [
      { label: 'Plan y créditos', icon: 'star', url: '/billing' },
      { label: 'Validar estudiante', icon: 'student', url: '/student-validation' },
      { label: 'Asistencia (técnico)', icon: 'target', url: '/attendance?tech=1' },
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
    public net: NetworkService,
    // Recordatorios de Notas (avisos y número en el menú)
    public reminders: RemindersService
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
        if (this.user && !NO_MENU.includes(this.url)) this.reminders.start();
        else if (!this.user) void this.reminders.stop();
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
    return this.memo.get('groups', [this.isAdmin], () =>
      NAV.map(g => ({ ...g, items: g.items.filter(i => !i.admin || this.isAdmin) })).filter(g => g.items.length)
    );
  }

  // La sección "Escuela" va plegada; se abre sola si estás en una de sus pantallas
  schoolOpen = false;
  get schoolVisible(): boolean {
    return this.schoolOpen || NAV.some(g => g.school && g.items.some(i => this.isActive(i.url)));
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
    const [path, query] = url.split('?');
    const here = this.url === path || this.url.startsWith(path + '/');
    if (!here) return false;
    // "Asistencia" y "Asistencia (técnico)" son la misma pantalla con distinta vista
    const tech = typeof location !== 'undefined' && /[?&]tech=1/.test(location.hash || location.search);
    return query ? tech : !tech || path !== '/attendance';
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
    this.billing.clear();
    await this.reminders.stop(true);
    await this.menu.close();
    await this.router.navigateByUrl('/login', { replaceUrl: true });
  }

  closeDiagnostics() {
    this.showTech = false;
    this.diagnostics.closeModal();
  }
}
