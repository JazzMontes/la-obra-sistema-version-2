// Perfil: nombre, usuario y correo de la cuenta; acceso al cambio de contraseña.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { Auth } from '../../services/auth';
import { UiService } from '../../services/ui';
import { errorMessage } from '../../services/api';
import { autoRefresh } from '../../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-profile',
  templateUrl: 'profile.page.html',
  styleUrls: ['profile.page.scss'],
  standalone: false,
})
export class ProfilePage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  user: any = null;
  form = { name: '', username: '', email: '' };
  saving = false;

  constructor(private auth: Auth, private ui: UiService) {}

  async ionViewWillEnter() {
    this.fill(this.auth.getStoredUser());
    try {
      const r = await this.auth.getMe();
      if (r.user) this.fill(r.user);
    } catch {
      // Se muestra lo guardado en el dispositivo
    }
  }

  private fill(u: any) {
    this.user = u;
    this.form = { name: u?.name ?? '', username: u?.username ?? '', email: u?.email ?? '' };
  }

  get initials(): string {
    return String(this.user?.name || '?').split(/\s+/).map((w: string) => w[0]).slice(0, 2).join('');
  }

  async save() {
    if (this.saving) return;
    if (!this.form.name.trim() || !this.form.username.trim() || !this.form.email.trim()) {
      this.ui.error('Completa nombre, usuario y correo');
      return;
    }
    this.saving = true;
    try {
      const r = await this.auth.updateProfile(this.form.name, this.form.username, this.form.email);
      if (r.user) this.fill(r.user);
      this.ui.success('Perfil actualizado');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo actualizar el perfil'));
    } finally {
      this.saving = false;
    }
  }
}
