// Inicio de sesión. El servidor es Supabase (environment o pantalla "Servidor").
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { Router } from '@angular/router';
import axios from 'axios';
import { Auth } from '../../services/auth';
import { ApiConfigService } from '../../services/api-config';
import { ApiDiagnosticsService } from '../../services/api-diagnostics';
import { errorMessage } from '../../services/api';
import { autoRefresh } from '../../services/render';
import { UiService } from '../../services/ui';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-login',
  templateUrl: 'login.page.html',
  styleUrls: ['login.page.scss'],
  standalone: false,
})
export class LoginPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  username = '';
  password = '';
  showPassword = false;
  loading = false;
  error = '';
  showTech = false;
  techText = '';

  serverOpen = false;
  serverHost = '';
  testing = false;
  serverStatus: 'unknown' | 'ok' | 'warn' | 'fail' = 'unknown';
  serverMessage = '';

  constructor(
    private auth: Auth,
    private config: ApiConfigService,
    private diagnostics: ApiDiagnosticsService,
    private router: Router,
    private ui: UiService
  ) {}

  // Usuarios que ya entraron en este dispositivo (solo el nombre de usuario, nunca la contraseña)
  recentUsers: string[] = [];

  // Recuperar contraseña con un código que llega al correo
  mode: 'login' | 'forgot' | 'reset' = 'login';
  recoverLogin = '';
  code = '';
  newPassword = '';
  newPassword2 = '';
  notice = '';

  ionViewWillEnter() {
    this.serverHost = this.config.getHost();
    this.recentUsers = readRecentUsers();
    if (!this.username && this.recentUsers.length) this.username = this.recentUsers[0];
  }

  // Después de entrar se recuerda el usuario en este dispositivo
  private rememberLogin() {
    saveRecentUser(this.username.trim());
  }

  openForgot() {
    this.error = '';
    this.notice = '';
    this.recoverLogin = this.username.trim();
    this.mode = 'forgot';
  }

  backToLogin() {
    this.error = '';
    this.mode = 'login';
  }

  // Paso 1: el servidor manda un código de 6 dígitos al correo de la cuenta
  async sendCode(again = false) {
    if (this.loading) return;
    this.error = '';
    const login = this.recoverLogin.trim();
    if (!login) {
      this.error = 'Escribe tu usuario o tu correo';
      return;
    }
    this.loading = true;
    try {
      const r = await this.auth.forgotPassword(login);
      this.notice = r.message || 'Te enviamos un código a tu correo.';
      this.code = '';
      this.mode = 'reset';
      if (again) this.ui.success('Te enviamos un código nuevo');
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo enviar el código');
    } finally {
      this.loading = false;
    }
  }

  // Paso 2: con el código se elige la nueva contraseña
  async resetPassword() {
    if (this.loading) return;
    this.error = '';
    const code = this.code.replace(/\D/g, '');
    if (code.length !== 6) return void (this.error = 'El código tiene 6 dígitos');
    if (this.newPassword.length < 8) return void (this.error = 'La nueva contraseña debe tener al menos 8 caracteres');
    if (this.newPassword !== this.newPassword2) return void (this.error = 'Las contraseñas no coinciden');
    this.loading = true;
    try {
      const r = await this.auth.resetPassword(this.recoverLogin.trim(), code, this.newPassword);
      this.username = r.username || this.recoverLogin.trim();
      this.password = '';
      this.newPassword = this.newPassword2 = this.code = '';
      this.notice = r.message || 'Tu contraseña se cambió. Ya puedes iniciar sesión.';
      this.mode = 'login';
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo cambiar la contraseña');
    } finally {
      this.loading = false;
    }
  }

  async testServer(silent = false) {
    this.testing = true;
    try {
      const r = await axios.get(`${this.config.getApiUrl()}/health.php`, { timeout: 6000 });
      const dbOk = r.data?.database_ok !== false;
      this.serverStatus = !r.data?.success ? 'fail' : dbOk ? 'ok' : 'warn';
      this.serverMessage = !r.data?.success
        ? 'El servidor respondió con un error'
        : dbOk ? 'Servidor conectado' : 'Faltan migraciones: ' + (r.data.run_migrations ?? []).join(', ');
      if (r.data?.success && !silent) this.serverOpen = false;
    } catch (e) {
      this.serverStatus = 'fail';
      this.serverMessage = errorMessage(e, 'No se pudo conectar');
      this.serverOpen = true;
    } finally {
      this.testing = false;
    }
  }

  async login() {
    if (this.loading) return;
    this.error = '';
    this.showTech = false;
    if (!this.username.trim() || !this.password) {
      this.error = 'Escribe tu usuario (o correo) y tu contraseña';
      return;
    }
    try {
      this.config.getApiUrl();
    } catch (e: any) {
      this.error = e.message;
      return;
    }
    this.loading = true;
    try {
      const r = await this.auth.login(this.username, this.password);
      if (r.success) {
        this.rememberLogin();
        this.notice = '';
        this.password = '';
        await this.router.navigateByUrl(r.user.must_change_password ? '/change-password' : '/home', { replaceUrl: true });
      } else {
        this.error = r.message || 'No se pudo iniciar sesión';
      }
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo iniciar sesión');
      this.techText = this.diagnostics.asText();
    } finally {
      this.loading = false;
    }
  }
}

const RECENT_KEY = 'la_obra_recent_users';

function readRecentUsers(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(RECENT_KEY) || '[]');
    return Array.isArray(v) ? v.filter(x => typeof x === 'string' && x).slice(0, 5) : [];
  } catch {
    return [];
  }
}

function saveRecentUser(username: string) {
  if (!username) return;
  try {
    const list = [username, ...readRecentUsers().filter(u => u.toLowerCase() !== username.toLowerCase())].slice(0, 5);
    localStorage.setItem(RECENT_KEY, JSON.stringify(list));
  } catch {
    // Almacenamiento no disponible
  }
}
