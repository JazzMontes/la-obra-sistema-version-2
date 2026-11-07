// Usuarios: alta de cuentas con contraseña temporal, rol y estado.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { autoRefresh } from '../../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-users',
  templateUrl: 'users.page.html',
  styleUrls: ['users.page.scss'],
  standalone: false,
})
export class UsersPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  status: 'active' | 'inactive' = 'active';
  users: any[] = [];
  loading = true;

  open = false;
  form: any = {};
  saving = false;
  formError = '';
  created: any = null;

  constructor(private api: ApiService, private ui: UiService, private auth: Auth) {}

  get me(): number {
    return Number(this.auth.getStoredUser()?.id);
  }

  ionViewWillEnter() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.users = (await this.api.get('users/index.php', { status: this.status })).users;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar los usuarios'));
    } finally {
      this.loading = false;
    }
  }

  setStatus(s: 'active' | 'inactive') {
    this.status = s;
    this.load();
  }

  initials(u: any): string {
    return String(u.name || '?').split(/\s+/).map((w: string) => w[0]).slice(0, 2).join('');
  }

  openNew() {
    this.form = { name: '', username: '', email: '', role: 'employee' };
    this.formError = '';
    this.created = null;
    this.open = true;
  }

  async save() {
    if (this.saving) return;
    this.formError = '';
    const f = this.form;
    if (!f.name.trim() || !f.username.trim() || !f.email.trim()) return void (this.formError = 'Completa nombre, usuario y correo');
    this.saving = true;
    try {
      const r = await this.api.post('users/create.php', { name: f.name.trim(), username: f.username.trim(), email: f.email.trim(), role: f.role });
      this.created = { ...r.user, temporary_password: r.temporary_password };
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e, 'No se pudo crear el usuario');
    } finally {
      this.saving = false;
    }
  }

  async copy(text: string) {
    try {
      await navigator.clipboard.writeText(text);
      this.ui.success('Copiado');
    } catch {
      this.ui.info('Selecciona el texto para copiarlo');
    }
  }

  async toggle(u: any) {
    const next = u.status === 'active' ? 'inactive' : 'active';
    const ok = await this.ui.confirm(
      next === 'inactive' ? 'Desactivar cuenta' : 'Activar cuenta',
      next === 'inactive' ? `${u.name} ya no podrá iniciar sesión.` : `${u.name} podrá volver a iniciar sesión.`,
      next === 'inactive' ? 'Desactivar' : 'Activar',
      next === 'inactive'
    );
    if (!ok) return;
    try {
      await this.api.patch(`users/update.php?id=${u.id}`, { status: next });
      this.ui.success('Cuenta actualizada');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async changeRole(u: any, role: string) {
    if (role === u.role) return;
    try {
      await this.api.patch(`users/update.php?id=${u.id}`, { role });
      this.ui.success('Rol actualizado');
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
      await this.load();
    }
  }
}
