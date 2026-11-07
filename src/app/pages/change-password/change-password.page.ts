// Cambio de contraseña (obligatorio en el primer inicio de sesión).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { Router } from '@angular/router';
import { Auth } from '../../services/auth';
import { UiService } from '../../services/ui';
import { errorMessage } from '../../services/api';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-change-password',
  templateUrl: 'change-password.page.html',
  styleUrls: ['change-password.page.scss'],
  standalone: false,
})
export class ChangePasswordPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  current = '';
  next = '';
  confirm = '';
  loading = false;
  error = '';

  constructor(private auth: Auth, private router: Router, private ui: UiService) {}

  get forced(): boolean {
    return !!this.auth.getStoredUser()?.must_change_password;
  }

  get checks() {
    return this.memo.get('checks', [this.next, this.confirm], () => [
      { ok: this.next.length >= 8, text: 'Al menos 8 caracteres' },
      { ok: /[A-Za-z]/.test(this.next) && /\d/.test(this.next), text: 'Letras y números' },
      { ok: !!this.next && this.next === this.confirm, text: 'Las dos coinciden' },
    ]);
  }

  async save() {
    if (this.loading) return;
    this.error = '';
    if (!this.current || !this.next || !this.confirm) return void (this.error = 'Completa los tres campos');
    if (this.next !== this.confirm) return void (this.error = 'Las contraseñas nuevas no coinciden');
    this.loading = true;
    try {
      const r = await this.auth.changePassword(this.current, this.next);
      if (r.success) {
        await this.auth.getMe();
        this.ui.success('Contraseña actualizada');
        await this.router.navigateByUrl('/home', { replaceUrl: true });
      }
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo cambiar la contraseña');
    } finally {
      this.loading = false;
    }
  }

  async exit() {
    try {
      await this.auth.logout();
    } catch {}
    await this.router.navigateByUrl('/login', { replaceUrl: true });
  }
}
