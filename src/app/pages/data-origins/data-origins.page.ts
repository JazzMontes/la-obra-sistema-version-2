// Conexión y respaldo: a qué proyecto de Supabase se conecta la app y copias de seguridad.
// Versión 1: IP de la computadora con XAMPP. Versión 2: Supabase en internet (web + APK).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiConfigService } from '../../services/api-config';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { ApiService, errorMessage } from '../../services/api';
import { autoRefresh } from '../../services/render';
import { Router } from '@angular/router';

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

  form = { supabaseUrl: '', supabaseKey: '' };
  testing = false;
  result: { ok: boolean; text: string; ms?: number; time?: string; version?: string } | null = null;

  exporting = false;
  includeFiles = true;
  restoring = false;
  restoreFile: File | null = null;
  restoreInfo = '';
  private restoreData: any = null;

  constructor(
    private config: ApiConfigService,
    private ui: UiService,
    private auth: Auth,
    private api: ApiService,
    private router: Router
  ) {
    this.load();
  }

  get loggedIn(): boolean {
    return this.auth.isLoggedIn();
  }

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  get custom(): boolean {
    return this.config.isCustom();
  }

  get preview(): string {
    const url = (this.form.supabaseUrl || 'https://<proyecto>.supabase.co').replace(/\/+$/, '');
    return `${url}/rest/v1/rpc/${this.config.rpcName}`;
  }

  get json(): string {
    return this.config.getJson();
  }

  private load() {
    const o = this.config.getOrigin();
    this.form = {
      supabaseUrl: this.config.isValidUrl(o.supabaseUrl) ? o.supabaseUrl : '',
      supabaseKey: /TU-CLAVE/.test(o.supabaseKey) ? '' : o.supabaseKey,
    };
  }

  ionViewWillEnter() {
    this.load();
    if (this.config.isConfigured()) this.test();
  }

  save() {
    try {
      this.config.setOrigin(this.form);
      this.load();
      this.ui.success('Conexión guardada en este dispositivo');
      this.test();
    } catch (e: any) {
      this.ui.error(e.message);
    }
  }

  resetToDefault() {
    this.config.reset();
    this.load();
    this.ui.info('Se usan los datos del archivo environment');
    if (this.config.isConfigured()) this.test();
  }

  async test() {
    this.testing = true;
    const start = performance.now();
    try {
      const r: any = await this.api.request('GET', 'health.php', undefined, undefined, 10000);
      this.result = {
        ok: !!r?.success,
        text: r?.message ?? 'Respuesta recibida',
        ms: Math.round(performance.now() - start),
        time: r?.server_time,
        version: r?.schema_version,
      };
    } catch (e) {
      this.result = { ok: false, text: errorMessage(e, 'No se pudo conectar') };
    } finally {
      this.testing = false;
    }
  }

  // ---------- Respaldo ----------

  async exportBackup() {
    this.exporting = true;
    try {
      const r: any = await this.api.request('GET', 'backup/export.php', { files: this.includeFiles ? 1 : 0 }, undefined, 60000);
      const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
      const name = `respaldo-la-obra-v2-${stamp}.json`;
      const blob = new Blob([JSON.stringify(r.backup)], { type: 'application/json' });
      await this.saveFile(blob, name);
      const rows = Object.values(r.backup?.tables ?? {}).reduce((n: number, t: any) => n + (t?.length ?? 0), 0);
      this.ui.success(`Respaldo descargado (${rows} registros)`);
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo generar el respaldo'));
    } finally {
      this.exporting = false;
    }
  }

  // En el navegador se descarga; en el APK se intenta compartir el archivo
  private async saveFile(blob: Blob, name: string) {
    const file = new File([blob], name, { type: blob.type });
    const nav: any = navigator;
    if ((window as any).Capacitor?.isNativePlatform?.() && nav.canShare?.({ files: [file] })) {
      await nav.share({ files: [file], title: name });
      return;
    }
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  }

  async pickRestore(ev: Event) {
    const input = ev.target as HTMLInputElement;
    const file = input.files?.[0] ?? null;
    input.value = '';
    this.restoreFile = null;
    this.restoreData = null;
    this.restoreInfo = '';
    if (!file) return;
    try {
      const data = JSON.parse(await file.text());
      if (data?.app !== 'la-obra-sistema-version-2' || !data?.tables) throw new Error('El archivo no es un respaldo de La Obra v2');
      const rows = Object.values(data.tables).reduce((n: number, t: any) => n + (t?.length ?? 0), 0);
      this.restoreFile = file;
      this.restoreData = data;
      this.restoreInfo = `Respaldo del ${String(data.exported_at || '').slice(0, 16)} · ${rows} registros` +
        (data.includes_files ? ' · con fotos' : ' · sin fotos (se conservan las actuales)');
    } catch (e: any) {
      this.ui.error(e.message || 'No se pudo leer el archivo');
    }
  }

  async restore() {
    if (!this.restoreData) return;
    const ok = await this.ui.confirm(
      'Restaurar respaldo',
      'Se BORRARÁ toda la información actual (ventas, compras, usuarios…) y se reemplazará por la del archivo. Después tendrás que iniciar sesión otra vez. ¿Continuar?',
      'Restaurar',
      true
    );
    if (!ok) return;
    this.restoring = true;
    try {
      const r: any = await this.api.request('POST', 'backup/import.php', undefined, { backup: this.restoreData, confirm: 'RESTAURAR' }, 120000);
      this.ui.success(r?.message || 'Respaldo restaurado');
      try { await this.auth.logout(); } catch { /* la sesión ya no existe */ }
      await this.router.navigateByUrl('/login', { replaceUrl: true });
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo restaurar el respaldo'));
    } finally {
      this.restoring = false;
    }
  }
}
