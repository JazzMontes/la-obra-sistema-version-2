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

  // Usuarios que ya entraron en este dispositivo (solo el nombre de usuario, nunca la contraseña)
  recentUsers: string[] = [];
  // El navegador permite leer contraseñas guardadas (Chrome, Edge, Chrome de Android)
  readonly canUseSaved = typeof window !== 'undefined' && 'PasswordCredential' in window && !!navigator.credentials;

  ionViewWillEnter() {
    this.serverHost = this.config.getHost();
    this.recentUsers = readRecentUsers();
    if (!this.username && this.recentUsers.length) this.username = this.recentUsers[0];
  }

  ionViewDidEnter() {
    // Si el navegador tiene la contraseña guardada, se rellena sola (sin entrar automáticamente)
    void this.useSaved(false);
  }

  // Pide al administrador de contraseñas del navegador la cuenta guardada para este sitio
  async useSaved(ask: boolean) {
    if (!this.canUseSaved) return;
    try {
      const cred: any = await navigator.credentials.get({ password: true, mediation: ask ? 'required' : 'optional' } as any);
      if (cred && cred.type === 'password' && cred.id) {
        this.username = cred.id;
        this.password = cred.password ?? '';
        this.refresher.schedule();
      }
    } catch {
      // El usuario cerró el aviso o el navegador no lo permite: se escribe a mano
    }
  }

  // Después de entrar: el navegador ofrece "¿Guardar contraseña?" y se recuerda el usuario
  private async rememberLogin(user: any, password: string) {
    saveRecentUser(this.username.trim());
    if (!this.canUseSaved) return;
    try {
      const PC = (window as any).PasswordCredential;
      await navigator.credentials.store(new PC({ id: this.username.trim(), password, name: user?.name || this.username.trim() }));
    } catch {
      // Sin soporte o el usuario dijo que no
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
        await this.rememberLogin(r.user, this.password);
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
