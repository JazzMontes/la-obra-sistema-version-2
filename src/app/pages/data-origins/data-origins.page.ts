// Servidor: muestra a qué proyecto de Supabase se conecta la app, prueba la conexión
// y (para el administrador) descarga o restaura un respaldo.
import { ChangeDetectionStrategy, Component } from '@angular/core';
import axios from 'axios';
import { ApiConfigService } from '../../services/api-config';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { ApiService, errorMessage } from '../../services/api';
import { autoRefresh } from '../../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-data-origins',
  templateUrl: 'data-origins.page.html',
  styleUrls: ['data-origins.page.scss'],
  standalone: false,
})
export class DataOriginsPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  apiUrl = '';
  host = '';
  source: 'build' | 'none' = 'none';
  configError = '';
  testing = false;
  result: { ok: boolean; text: string; ms?: number; time?: string } | null = null;

  backingUp = false;
  restoring = false;

  constructor(public config: ApiConfigService, private ui: UiService, private auth: Auth, private api: ApiService) {
    this.load();
  }

  private load() {
    const s = this.config.settings;
    this.host = this.config.getHost();
    this.source = s.source;
    try {
      this.apiUrl = this.config.getApiUrl();
      this.configError = '';
    } catch (e: any) {
      this.apiUrl = '';
      this.configError = e.message;
    }
  }

  get loggedIn(): boolean {
    return this.auth.isLoggedIn();
  }

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  ionViewWillEnter() {
    this.load();
    if (this.apiUrl) this.test();
  }

  async test() {
    this.testing = true;
    const start = performance.now();
    try {
      const r = await axios.get(`${this.config.getApiUrl()}/health.php`, { timeout: 10000 });
      this.result = {
        ok: !!r.data?.success,
        text: r.data?.message ?? 'Respuesta recibida',
        ms: Math.round(performance.now() - start),
        time: r.data?.server_time,
      };
    } catch (e) {
      this.result = { ok: false, text: errorMessage(e, 'No se pudo conectar') };
    } finally {
      this.testing = false;
    }
  }

  // Respaldo completo en JSON (solo administrador)
  async backup(withFiles: boolean) {
    if (this.backingUp) return;
    this.backingUp = true;
    try {
      const r = await this.api.get('backup/export.php', { files: withFiles ? 1 : 0 }, );
      const blob = new Blob([JSON.stringify(r.backup)], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `la-obra-respaldo-${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
      this.ui.success('Respaldo descargado');
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo descargar el respaldo'));
    } finally {
      this.backingUp = false;
    }
  }

  async restore(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    let data: any;
    try {
      data = JSON.parse(await file.text());
    } catch {
      return this.ui.error('El archivo no es un respaldo válido (.json)');
    }
    const ok = await this.ui.confirm(
      'Restaurar respaldo',
      'Se reemplazará TODA la información actual por la del archivo. Después tendrás que volver a iniciar sesión. ¿Continuar?',
      'Restaurar',
      true
    );
    if (!ok) return;
    this.restoring = true;
    try {
      const r = await this.api.post('backup/import.php', { backup: data });
      this.ui.success(r.message || 'Respaldo restaurado');
      await this.auth.logout().catch(() => undefined);
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      location.hash = '#/login';
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo restaurar'));
    } finally {
      this.restoring = false;
    }
  }
}
