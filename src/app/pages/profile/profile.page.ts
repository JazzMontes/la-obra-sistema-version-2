// Perfil: nombre, usuario y correo de la cuenta; acceso al cambio de contraseña.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { Auth } from '../../services/auth';
import { UiService } from '../../services/ui';
import { errorMessage } from '../../services/api';
import { autoRefresh } from '../../services/render';
import { compressImage } from '../../utils/image';

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
  uploading = false;

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

  // Foto de perfil: se reduce en el teléfono (máx. 512 px) y se guarda al momento
  async pickPhoto(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file || this.uploading) return;
    this.uploading = true;
    try {
      const url = await compressImage(file, 512, 0.85);
      const r = await this.auth.setAvatar(url);
      this.user = { ...this.user, avatar_path: r.avatar_path };
      this.ui.success('Foto de perfil actualizada');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo guardar la foto'));
    } finally {
      this.uploading = false;
      this.refresher.schedule();
    }
  }

  async removePhoto() {
    if (this.uploading) return;
    const ok = await this.ui.confirm('Quitar foto', '¿Quitar tu foto de perfil?', 'Quitar', true);
    if (!ok) return;
    this.uploading = true;
    try {
      await this.auth.setAvatar(null);
      this.user = { ...this.user, avatar_path: null };
      this.ui.success('Foto de perfil eliminada');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo quitar la foto'));
    } finally {
      this.uploading = false;
      this.refresher.schedule();
    }
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
