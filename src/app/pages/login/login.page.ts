// Inicio de sesión y configuración rápida de la conexión con Supabase.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { Router } from '@angular/router';
import { Auth } from '../../services/auth';
import { ApiConfigService } from '../../services/api-config';
import { ApiDiagnosticsService } from '../../services/api-diagnostics';
import { ApiService, errorMessage } from '../../services/api';
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
  serverUrl = '';
  serverKey = '';
  serverLabel = '';
  testing = false;
  serverStatus: 'unknown' | 'ok' | 'warn' | 'fail' = 'unknown';
  serverMessage = '';

  constructor(
    private auth: Auth,
    private config: ApiConfigService,
    private diagnostics: ApiDiagnosticsService,
    private router: Router,
    private api: ApiService
  ) {}

  ionViewWillEnter() {
    const o = this.config.getOrigin();
    this.serverUrl = this.config.isValidUrl(o.supabaseUrl) ? o.supabaseUrl : '';
    this.serverKey = /TU-CLAVE/.test(o.supabaseKey) ? '' : o.supabaseKey;
    this.serverLabel = this.config.isConfigured() ? this.config.getServerLabel() : '';
    if (!this.config.isConfigured()) this.serverOpen = true;
    else this.testServer(true);
  }

  saveServer() {
    try {
      this.config.setOrigin({ supabaseUrl: this.serverUrl, supabaseKey: this.serverKey });
      this.serverLabel = this.config.getServerLabel();
      this.testServer();
    } catch (e: any) {
      this.serverStatus = 'fail';
      this.serverMessage = e.message;
    }
  }

  async testServer(silent = false) {
    this.testing = true;
    try {
      const r: any = await this.api.request('GET', 'health.php', undefined, undefined, 10000);
      this.serverStatus = r?.success ? 'ok' : 'fail';
      this.serverMessage = r?.success ? 'Conectado a Supabase' : 'Supabase respondió con un error';
      if (r?.success && !silent) this.serverOpen = false;
    } catch (e) {
      this.serverStatus = 'fail';
      this.serverMessage = errorMessage(e, 'No se pudo conectar');
      if (!silent) this.serverOpen = true;
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
      this.serverOpen = true;
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
