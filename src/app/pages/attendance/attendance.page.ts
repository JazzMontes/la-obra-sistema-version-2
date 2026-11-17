// Asistencia con geolocalización: cada usuario registra su llegada (entrada) y su salida
// desde el teléfono. La app obtiene la latitud y longitud reales, las muestra, calcula
// la distancia al negocio y solo permite registrar dentro del radio que definió el administrador.
// El servidor repite la validación de distancia (no confía en la app).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { RenderService, autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';
import { todayIso } from '../../shared/format.pipes';
import {
  GeoError,
  GeoReading,
  GeolocationService,
  PermissionStatus,
  distanceMeters,
  toDms,
} from '../../services/geolocation';

interface WorkLocation {
  name: string;
  latitude: number;
  longitude: number;
  radius_m: number;
  updated_at?: string;
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-attendance',
  templateUrl: 'attendance.page.html',
  styleUrls: ['attendance.page.scss'],
  standalone: false,
})
export class AttendancePage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  // Permiso y lectura GPS
  perm: PermissionStatus = 'unknown';
  reading: GeoReading | null = null;
  locating = false;
  geoError: GeoError | null = null;
  live = false;
  private stopWatch: (() => void) | null = null;
  private stopPermWatch: (() => void) | null = null;

  // Datos del servidor
  location: WorkLocation | null = null;
  lastToday: any = null;
  records: any[] = [];
  loading = true;
  from = todayIso(-6);
  to = todayIso();

  // Registro
  note = '';
  saving = false;
  checkError = '';

  // Configuración del lugar (administrador)
  configOpen = false;
  config: any = {};
  configError = '';
  savingConfig = false;

  readonly toDms = toDms;

  constructor(
    private api: ApiService,
    private ui: UiService,
    private auth: Auth,
    private geo: GeolocationService,
    private render: RenderService
  ) {}

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  async ionViewWillEnter() {
    this.load();
    // Solo se consulta el estado del permiso; NO se pide todavía
    this.perm = await this.geo.permission();
    this.stopPermWatch = await this.geo.onPermissionChange(s => {
      this.perm = s;
      if (s === 'denied') this.stopLive();
      this.render.schedule();
    });
    // Si el permiso ya estaba concedido, se puede leer la ubicación sin molestar al usuario
    if (this.perm === 'granted' && !this.reading) this.locate();
    this.render.schedule();
  }

  ionViewWillLeave() {
    // No se rastrea en segundo plano: al salir de la pantalla se apaga el GPS
    this.stopLive();
    this.stopPermWatch?.();
    this.stopPermWatch = null;
  }

  async load() {
    this.loading = true;
    try {
      const params = this.isAdmin ? { date_from: this.from, date_to: this.to } : {};
      const r = await this.api.get('attendance/index.php', params);
      this.records = r.records;
      this.lastToday = r.last_today;
      this.location = r.location;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo cargar la asistencia'));
    } finally {
      this.loading = false;
    }
  }

  // ---------- Ubicación ----------

  async locate(): Promise<GeoReading | null> {
    if (this.locating) return null;
    this.locating = true;
    this.geoError = null;
    this.checkError = '';
    this.render.schedule();
    try {
      this.reading = await this.geo.current();
      this.perm = 'granted';
      return this.reading;
    } catch (e: any) {
      this.handleGeoError(e);
      return null;
    } finally {
      this.locating = false;
      this.render.schedule();
    }
  }

  toggleLive() {
    if (this.live) return this.stopLive();
    this.geoError = null;
    this.live = true;
    this.stopWatch = this.geo.watch(
      r => {
        this.reading = r;
        this.perm = 'granted';
        this.geoError = null;
        this.render.schedule();
      },
      e => {
        this.handleGeoError(e);
        if (e.kind === 'denied' || e.kind === 'insecure' || e.kind === 'unsupported') this.stopLive();
        this.render.schedule();
      }
    );
  }

  stopLive() {
    this.stopWatch?.();
    this.stopWatch = null;
    this.live = false;
  }

  private handleGeoError(e: any) {
    this.geoError = e instanceof GeoError ? e : new GeoError('unknown', e?.message || 'Error al obtener la ubicación', 'Intenta de nuevo.');
    if (this.geoError.kind === 'denied') this.perm = 'denied';
  }

  // ---------- Cálculos para la vista ----------

  get distance(): number | null {
    if (!this.reading || !this.location) return null;
    return distanceMeters(this.reading.latitude, this.reading.longitude, this.location.latitude, this.location.longitude);
  }

  get inside(): boolean {
    const d = this.distance;
    return d !== null && !!this.location && d <= this.location.radius_m;
  }

  get lowAccuracy(): boolean {
    return !!this.reading && this.reading.accuracy > 150;
  }

  get nextType(): 'in' | 'out' {
    return this.lastToday?.type === 'in' ? 'out' : 'in';
  }

  get readingAge(): string {
    if (!this.reading) return '';
    const s = Math.max(0, Math.round((Date.now() - this.reading.timestamp) / 1000));
    return s < 5 ? 'ahora' : s < 60 ? `hace ${s} s` : `hace ${Math.round(s / 60)} min`;
  }

  // Tu ubicación para el mapa (misma referencia mientras no cambie la lectura)
  get mapMe() {
    return this.memo.get('mapMe', [this.reading], () =>
      this.reading ? { latitude: this.reading.latitude, longitude: this.reading.longitude, accuracy: this.reading.accuracy } : null
    );
  }

  // Punto que se está configurando (vista previa en la ventana del administrador)
  get configPoint() {
    const lat = Number(this.config?.latitude);
    const lng = Number(this.config?.longitude);
    const ok = this.config?.latitude !== null && this.config?.latitude !== '' && this.config?.longitude !== null && this.config?.longitude !== ''
      && Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
    return this.memo.get('configPoint', [ok ? lat : null, ok ? lng : null], () => (ok ? { latitude: lat, longitude: lng } : null));
  }

  // Cómo llegar desde tu ubicación al negocio, en Google Maps
  directionsUrl(lat: number, lng: number): string {
    if (!this.location) return this.mapUrl(lat, lng);
    return `https://www.google.com/maps/dir/?api=1&origin=${lat},${lng}&destination=${this.location.latitude},${this.location.longitude}&travelmode=walking`;
  }

  mapUrl(lat: number | string, lng: number | string): string {
    return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
  }

  // ---------- Registrar entrada / salida ----------

  async check() {
    if (this.saving) return;
    this.checkError = '';
    if (!this.location) return void (this.checkError = 'El administrador aún no ha configurado la ubicación del negocio.');

    // Siempre con una lectura reciente (menos de 30 s) para que no se use una ubicación vieja
    let r = this.reading;
    if (!r || Date.now() - r.timestamp > 30000) r = await this.locate();
    if (!r) return;
    if (this.lowAccuracy) return void (this.checkError = `La ubicación es poco precisa (±${Math.round(r.accuracy)} m). Activa el GPS de alta precisión o acércate a una ventana.`);
    if (!this.inside) return void (this.checkError = `Estás a ${Math.round(this.distance ?? 0)} m de ${this.location.name}. Debes estar a menos de ${this.location.radius_m} m.`);

    const type = this.nextType;
    this.saving = true;
    try {
      await this.api.post('attendance/check.php', {
        type,
        latitude: r.latitude,
        longitude: r.longitude,
        accuracy: Math.round(r.accuracy * 10) / 10,
        note: this.note.trim() || null,
      });
      this.note = '';
      this.ui.success(type === 'in' ? 'Llegada registrada' : 'Salida registrada');
      await this.load();
    } catch (e) {
      this.checkError = errorMessage(e, 'No se pudo registrar');
    } finally {
      this.saving = false;
    }
  }

  // ---------- Configurar ubicación del negocio (admin) ----------

  openConfig() {
    const l = this.location;
    this.config = {
      name: l?.name ?? 'La Obra',
      latitude: l?.latitude ?? null,
      longitude: l?.longitude ?? null,
      radius_m: l?.radius_m ?? 100,
    };
    this.configError = '';
    this.configOpen = true;
  }

  async useCurrentForConfig() {
    const r = await this.locate();
    if (!r) return void (this.configError = this.geoError ? `${this.geoError.message} ${this.geoError.help}` : 'No se pudo obtener la ubicación');
    this.config.latitude = Number(r.latitude.toFixed(7));
    this.config.longitude = Number(r.longitude.toFixed(7));
    this.configError = r.accuracy > 50 ? `Ojo: la lectura tiene ±${Math.round(r.accuracy)} m de margen. Si puedes, repítela con mejor señal.` : '';
  }

  async saveConfig() {
    if (this.savingConfig) return;
    this.configError = '';
    const lat = Number(this.config.latitude);
    const lng = Number(this.config.longitude);
    const radius = Number(this.config.radius_m);
    if (!Number.isFinite(lat) || Math.abs(lat) > 90 || this.config.latitude === null || this.config.latitude === '') return void (this.configError = 'Latitud inválida (entre -90 y 90)');
    if (!Number.isFinite(lng) || Math.abs(lng) > 180 || this.config.longitude === null || this.config.longitude === '') return void (this.configError = 'Longitud inválida (entre -180 y 180)');
    if (!(radius >= 20 && radius <= 2000)) return void (this.configError = 'El radio debe estar entre 20 y 2000 metros');
    this.savingConfig = true;
    try {
      const r = await this.api.put('attendance/location.php', { name: String(this.config.name || 'La Obra').trim(), latitude: lat, longitude: lng, radius_m: Math.round(radius) });
      this.location = r.location;
      this.configOpen = false;
      this.ui.success('Ubicación del negocio guardada');
    } catch (e) {
      this.configError = errorMessage(e, 'No se pudo guardar');
    } finally {
      this.savingConfig = false;
    }
  }
}
