// Inicio de sesión. El servidor es Supabase (environment o pantalla "Servidor").
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { Router } from '@angular/router';
import axios from 'axios';
import { Auth } from '../../services/auth';
import { ApiConfigService } from '../../services/api-config';
import { ApiDiagnosticsService } from '../../services/api-diagnostics';
import { errorMessage } from '../../services/api';
import { autoRefresh } from '../../services/render';

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
    private router: Router
  ) {}

  ionViewWillEnter() {
    this.serverHost = this.config.getHost();
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
      this.error = 'Escribe tu usuario y contraseña';
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
