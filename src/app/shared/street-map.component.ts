// Mapa de calles (como Google Maps) para la asistencia: muestra el negocio con su radio
// permitido y, si hay lectura del GPS, tu ubicación con su margen de error.
// Usa los mosaicos libres de OpenStreetMap (sin clave ni costo) y se dibuja sin librerías.
// Se puede mover arrastrando, acercar con + / − o doble clic, y volver a centrar.
import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  Input,
  OnChanges,
  OnDestroy,
  ViewChild,
} from '@angular/core';
import { RenderService, autoRefresh } from '../services/render';

export interface MapPoint {
  latitude: number;
  longitude: number;
  accuracy?: number;
}

interface Tile {
  key: string;
  url: string;
  x: number;
  y: number;
}

const TILE = 256;
const MIN_Z = 3;
const MAX_Z = 19;

// Coordenadas "mundo" en píxeles (proyección Web Mercator, la misma de Google Maps)
function worldX(lng: number, z: number): number {
  return ((lng + 180) / 360) * TILE * 2 ** z;
}
function worldY(lat: number, z: number): number {
  const r = (Math.max(-85, Math.min(85, lat)) * Math.PI) / 180;
  return ((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * TILE * 2 ** z;
}
// Metros por píxel a esa latitud y zoom
function metersPerPixel(lat: number, z: number): number {
  return (156543.03392 * Math.cos((lat * Math.PI) / 180)) / 2 ** z;
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-street-map',
  template: `
    <div
      #box
      class="map"
      [style.height.px]="height"
      (pointerdown)="down($event)"
      (pointermove)="move($event)"
      (pointerup)="up($event)"
      (pointercancel)="up($event)"
      (dblclick)="zoomBy(1)"
      role="img"
      [attr.aria-label]="ariaLabel"
    >
      <div class="tiles">
        <img *ngFor="let t of tiles; trackBy: tileKey" [src]="t.url" [style.left.px]="t.x" [style.top.px]="t.y" alt="" draggable="false" loading="lazy" (error)="tileError()" />
      </div>
      <svg class="overlay" [attr.width]="w" [attr.height]="h" aria-hidden="true">
        <circle *ngIf="shop && radius" [attr.cx]="shop.x" [attr.cy]="shop.y" [attr.r]="fencePx" class="fence" [class.ok]="inside === true" [class.out]="inside === false" />
        <line *ngIf="shop && mePx" [attr.x1]="shop.x" [attr.y1]="shop.y" [attr.x2]="mePx.x" [attr.y2]="mePx.y" class="link" />
        <circle *ngIf="mePx && accPx > 6" [attr.cx]="mePx.x" [attr.cy]="mePx.y" [attr.r]="accPx" class="acc" />
      </svg>
      <div class="pin-shop" *ngIf="shop" [style.left.px]="shop.x" [style.top.px]="shop.y">
        <svg viewBox="0 0 24 32" width="30" height="40" aria-hidden="true">
          <path d="M12 31s-10-9.2-10-17a10 10 0 0 1 20 0c0 7.8-10 17-10 17z" class="pin-body" />
          <circle cx="12" cy="13" r="4" fill="#fff" />
        </svg>
        <span class="pin-label" *ngIf="label">{{ label }}</span>
      </div>
      <div class="pin-me" *ngIf="mePx" [style.left.px]="mePx.x" [style.top.px]="mePx.y"><span></span></div>

      <div class="controls">
        <button type="button" (click)="zoomBy(1)" aria-label="Acercar" [disabled]="z >= maxZ">+</button>
        <button type="button" (click)="zoomBy(-1)" aria-label="Alejar" [disabled]="z <= minZ">−</button>
        <button type="button" (click)="recenter()" aria-label="Centrar" class="center-btn" [class.active]="!userMoved">
          <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2.5"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></svg>
        </button>
      </div>
      <div class="scale" *ngIf="scaleBar">
        <span [style.width.px]="scaleBar.px"></span>{{ scaleBar.label }}
      </div>
      <div class="offline" *ngIf="tilesFailed">Sin internet: el mapa no se pudo cargar</div>
      <a class="attrib" href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">© OpenStreetMap</a>
    </div>
  `,
  styles: [`
    :host { display: block; }
    .map {
      position: relative; overflow: hidden; border-radius: var(--radius); border: 1px solid var(--border);
      background: #e9e5dc; touch-action: none; user-select: none; cursor: grab;
    }
    .map:active { cursor: grabbing; }
    .tiles img { position: absolute; width: 256px; height: 256px; max-width: none; pointer-events: none; }
    .overlay { position: absolute; inset: 0; pointer-events: none; overflow: visible; }
    .fence { fill: rgba(36, 87, 197, 0.12); stroke: #2457c5; stroke-width: 2; }
    .fence.ok { fill: rgba(23, 131, 74, 0.14); stroke: var(--success); }
    .fence.out { fill: rgba(201, 52, 52, 0.10); stroke: var(--danger); }
    .link { stroke: #1a1a1a; stroke-width: 1.5; stroke-dasharray: 5 4; opacity: 0.55; }
    .acc { fill: rgba(66, 133, 244, 0.18); stroke: rgba(66, 133, 244, 0.5); stroke-width: 1; }
    .pin-shop { position: absolute; transform: translate(-50%, -100%); pointer-events: none; display: flex; flex-direction: column; align-items: center; }
    .pin-shop svg { filter: drop-shadow(0 2px 2px rgba(0,0,0,.35)); order: 2; }
    .pin-body { fill: #ea4335; stroke: #a52714; stroke-width: 1; }
    .pin-label {
      order: 1; margin-bottom: 2px; padding: 2px 8px; border-radius: 999px; background: #fff; color: #1a1a1a;
      font: 600 12px/1.4 var(--font); box-shadow: 0 1px 3px rgba(0,0,0,.3); white-space: nowrap;
    }
    .pin-me { position: absolute; width: 0; height: 0; pointer-events: none; }
    .pin-me span {
      position: absolute; left: -9px; top: -9px; width: 18px; height: 18px; border-radius: 50%;
      background: #4285f4; border: 3px solid #fff; box-shadow: 0 1px 4px rgba(0,0,0,.4);
    }
    .controls { position: absolute; right: 10px; top: 10px; display: flex; flex-direction: column; gap: 6px; }
    .controls button {
      width: 34px; height: 34px; border-radius: 8px; border: 0; background: #fff; color: #333; cursor: pointer;
      font: 600 20px/1 var(--font); box-shadow: 0 1px 4px rgba(0,0,0,.3); display: grid; place-items: center; padding: 0;
    }
    .controls button:disabled { opacity: .45; cursor: default; }
    .controls svg { fill: none; stroke: currentColor; stroke-width: 2; }
    .controls .center-btn.active { color: #1a73e8; }
    .scale {
      position: absolute; left: 10px; bottom: 8px; display: flex; align-items: center; gap: 6px;
      font: 600 11px/1 var(--font); color: #333; text-shadow: 0 0 3px #fff, 0 0 3px #fff;
    }
    .scale span { display: block; height: 6px; border: 2px solid #333; border-top: 0; }
    .attrib {
      position: absolute; right: 0; bottom: 0; padding: 1px 6px; background: rgba(255,255,255,.8);
      font: 10px/1.4 var(--font); color: #333; text-decoration: none;
    }
    .offline {
      position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); padding: 6px 12px; border-radius: 8px;
      background: rgba(255,255,255,.9); font: 13px var(--font); color: var(--muted);
    }
  `],
  standalone: false,
})
export class StreetMapComponent implements OnChanges, AfterViewInit, OnDestroy {
  private readonly refresher = autoRefresh();

  // Negocio (centro del área permitida)
  @Input() center: MapPoint | null = null;
  // Radio permitido en metros
  @Input() radius: number | null = null;
  // Ubicación del usuario (con su margen de error en metros)
  @Input() me: MapPoint | null = null;
  // ¿El usuario está dentro del radio? (colorea el área); null = sin dato
  @Input() inside: boolean | null = null;
  @Input() label = '';
  @Input() height = 280;

  @ViewChild('box') box?: ElementRef<HTMLDivElement>;

  readonly minZ = MIN_Z;
  readonly maxZ = MAX_Z;
  w = 320;
  h = 280;
  z = 17;
  // Centro de la vista en coordenadas mundo (píxeles al zoom z)
  private cx = 0;
  private cy = 0;
  userMoved = false;

  tiles: Tile[] = [];
  shop: { x: number; y: number } | null = null;
  mePx: { x: number; y: number } | null = null;
  fencePx = 0;
  accPx = 0;
  scaleBar: { px: number; label: string } | null = null;
  tilesFailed = false;

  private resize?: ResizeObserver;
  private drag: { id: number; x: number; y: number } | null = null;

  constructor(private render: RenderService) {}

  get ariaLabel(): string {
    return this.label ? `Mapa de ${this.label}` : 'Mapa';
  }

  ngAfterViewInit() {
    const el = this.box?.nativeElement;
    if (!el) return;
    this.measure();
    if (typeof ResizeObserver !== 'undefined') {
      this.resize = new ResizeObserver(() => {
        if (this.measure()) {
          if (!this.userMoved) this.fit();
          this.update();
          this.render.schedule();
        }
      });
      this.resize.observe(el);
    }
    this.fit();
    this.update();
    this.render.schedule();
  }

  ngOnChanges() {
    this.h = this.height;
    if (!this.userMoved) this.fit();
    this.update();
  }

  ngOnDestroy() {
    this.resize?.disconnect();
  }

  tileKey(_: number, t: Tile): string {
    return t.key;
  }

  tileError() {
    if (typeof navigator !== 'undefined' && !navigator.onLine) this.tilesFailed = true;
  }

  // ---------- Vista ----------

  private measure(): boolean {
    const el = this.box?.nativeElement;
    const w = el?.clientWidth || 0;
    const h = el?.clientHeight || this.height;
    if (w > 0 && (w !== this.w || h !== this.h)) {
      this.w = w;
      this.h = h;
      return true;
    }
    return false;
  }

  // Elige el zoom más cercano en el que caben el negocio con su radio y tu ubicación
  private fit() {
    const pts: { lat: number; lng: number; r: number }[] = [];
    if (this.center) pts.push({ lat: +this.center.latitude, lng: +this.center.longitude, r: Math.max(+(this.radius || 0), 25) });
    if (this.me) pts.push({ lat: +this.me.latitude, lng: +this.me.longitude, r: Math.min(Math.max(+(this.me.accuracy || 0), 15), 300) });
    const valid = pts.filter(p => Number.isFinite(p.lat) && Number.isFinite(p.lng));
    if (!valid.length) return;
    const pad = 36;
    for (let z = MAX_Z; z >= MIN_Z; z--) {
      let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
      for (const p of valid) {
        const x = worldX(p.lng, z), y = worldY(p.lat, z), r = p.r / metersPerPixel(p.lat, z);
        minX = Math.min(minX, x - r); maxX = Math.max(maxX, x + r);
        minY = Math.min(minY, y - r); maxY = Math.max(maxY, y + r);
      }
      // Arriba se deja espacio para el globo con el nombre del negocio
      if (maxX - minX <= this.w - pad * 2 && maxY - minY <= this.h - pad * 2 - 30 || z === MIN_Z) {
        this.z = Math.min(z, 18);
        this.cx = (minX + maxX) / 2 * 2 ** (this.z - z);
        this.cy = ((minY + maxY) / 2 - 15) * 2 ** (this.z - z);
        return;
      }
    }
  }

  private toScreen(lat: number, lng: number) {
    return { x: worldX(lng, this.z) - this.cx + this.w / 2, y: worldY(lat, this.z) - this.cy + this.h / 2 };
  }

  private update() {
    if (!this.center && !this.me) {
      this.tiles = [];
      this.shop = this.mePx = null;
      return;
    }
    const z = this.z;
    const n = 2 ** z;
    const left = this.cx - this.w / 2;
    const top = this.cy - this.h / 2;
    const tiles: Tile[] = [];
    for (let ty = Math.floor(top / TILE); ty <= Math.floor((top + this.h) / TILE); ty++) {
      if (ty < 0 || ty >= n) continue;
      for (let tx = Math.floor(left / TILE); tx <= Math.floor((left + this.w) / TILE); tx++) {
        const wx = ((tx % n) + n) % n;
        tiles.push({
          key: `${z}/${tx}/${ty}`,
          url: `https://tile.openstreetmap.org/${z}/${wx}/${ty}.png`,
          x: Math.round(tx * TILE - left),
          y: Math.round(ty * TILE - top),
        });
      }
    }
    this.tiles = tiles;

    const refLat = this.center ? +this.center.latitude : +this.me!.latitude;
    const mpp = metersPerPixel(refLat, z);
    this.shop = this.center ? this.toScreen(+this.center.latitude, +this.center.longitude) : null;
    this.fencePx = this.radius ? +this.radius / mpp : 0;
    this.mePx = this.me ? this.toScreen(+this.me.latitude, +this.me.longitude) : null;
    this.accPx = this.me?.accuracy ? Math.min(+this.me.accuracy / mpp, 4000) : 0;

    // Escala: un número "redondo" de metros que mida entre 50 y 110 px
    const steps = [5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000];
    const m = steps.find(s => s / mpp >= 50) ?? steps[steps.length - 1];
    this.scaleBar = { px: Math.round(m / mpp), label: m >= 1000 ? `${m / 1000} km` : `${m} m` };
  }

  zoomBy(d: number) {
    const z = Math.max(MIN_Z, Math.min(MAX_Z, this.z + d));
    if (z === this.z) return;
    const f = 2 ** (z - this.z);
    this.cx *= f;
    this.cy *= f;
    this.z = z;
    this.userMoved = true;
    this.update();
    this.render.schedule();
  }

  recenter() {
    this.userMoved = false;
    this.fit();
    this.update();
    this.render.schedule();
  }

  // ---------- Arrastrar ----------

  down(e: PointerEvent) {
    if ((e.target as HTMLElement)?.closest('button, a')) return;
    this.drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
    try {
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    } catch {
      // Sin captura: se sigue arrastrando mientras el dedo esté sobre el mapa
    }
  }

  move(e: PointerEvent) {
    if (!this.drag || this.drag.id !== e.pointerId) return;
    const dx = e.clientX - this.drag.x;
    const dy = e.clientY - this.drag.y;
    if (!dx && !dy) return;
    this.drag.x = e.clientX;
    this.drag.y = e.clientY;
    this.cx -= dx;
    this.cy -= dy;
    this.userMoved = true;
    this.update();
    this.render.schedule();
  }

  up(e: PointerEvent) {
    if (this.drag?.id === e.pointerId) this.drag = null;
  }
}
