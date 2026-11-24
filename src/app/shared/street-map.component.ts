// Mapa de calles (como Google Maps) para la asistencia: muestra el negocio con su radio
// permitido y, si hay lectura del GPS, tu ubicación con su margen de error.
// Usa los mosaicos de calles de Esri (World Street Map: no piden clave ni cuenta) y, si no
// responden, los de OpenStreetMap. Se dibuja sin librerías.
// (Antes eran los de CARTO, que ahora muestran "API key required" sobre el mapa.)
// Se mueve arrastrando; se acerca con + / −, doble clic, rueda o pellizco.
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
  fallback: string;
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
      (wheel)="wheel($event)"
      (dblclick)="zoomBy(1)"
      role="img"
      [attr.aria-label]="ariaLabel"
    >
      <div class="tiles">
        <img
          *ngFor="let t of tiles; trackBy: tileKey"
          [src]="t.url"
          [style.left.px]="t.x"
          [style.top.px]="t.y"
          alt=""
          draggable="false"
          (load)="$any($event.target).classList.add('ready')"
          (error)="tileError($event, t)"
        />
      </div>
      <svg class="overlay" [attr.width]="w" [attr.height]="h" aria-hidden="true">
        <circle *ngIf="shop && radius" [attr.cx]="shop.x" [attr.cy]="shop.y" [attr.r]="fencePx" class="fence" [class.ok]="inside === true" [class.out]="inside === false" />
        <line *ngIf="shop && mePx" [attr.x1]="shop.x" [attr.y1]="shop.y" [attr.x2]="mePx.x" [attr.y2]="mePx.y" class="link" />
        <circle *ngIf="mePx && accPx > 10" [attr.cx]="mePx.x" [attr.cy]="mePx.y" [attr.r]="accPx" class="acc" />
      </svg>
      <div class="pin-me" *ngIf="mePx" [style.left.px]="mePx.x" [style.top.px]="mePx.y"><i></i><span></span></div>
      <div class="pin-shop" *ngIf="shop" [style.left.px]="shop.x" [style.top.px]="shop.y">
        <span class="pin-label" *ngIf="label">{{ label }}</span>
        <svg viewBox="0 0 28 38" width="30" height="41" aria-hidden="true">
          <path d="M14 37c-1.2-3.6-3.2-6.6-5.6-9.4C5 23.7 2 20.4 2 14.5A12 12 0 0 1 26 14.5c0 5.9-3 9.2-6.4 13.1-2.4 2.8-4.4 5.8-5.6 9.4z" class="pin-body" />
          <circle cx="14" cy="14.5" r="4.6" class="pin-hole" />
        </svg>
        <span class="pin-shadow"></span>
      </div>

      <div class="zoom">
        <button type="button" (click)="zoomBy(1)" aria-label="Acercar" [disabled]="z >= maxZ">
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>
        </button>
        <span class="sep"></span>
        <button type="button" (click)="zoomBy(-1)" aria-label="Alejar" [disabled]="z <= minZ">
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M5 12h14"/></svg>
        </button>
      </div>
      <button type="button" class="center-btn" (click)="recenter()" aria-label="Centrar" [class.active]="!userMoved">
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><circle cx="12" cy="12" r="6.5"/><circle cx="12" cy="12" r="2.4" class="dot"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3"/></svg>
      </button>
      <div class="scale" *ngIf="scaleBar">
        <span [style.width.px]="scaleBar.px"></span>{{ scaleBar.label }}
      </div>
      <div class="offline" *ngIf="tilesFailed">Sin internet: el mapa no se pudo cargar</div>
      <div class="attrib">
        <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">© OpenStreetMap</a>
        <ng-container *ngIf="!useOsm"> · <a href="https://www.esri.com/" target="_blank" rel="noopener">© Esri</a></ng-container>
      </div>
    </div>
  `,
  styles: [`
    :host { display: block; }
    .map {
      position: relative; overflow: hidden; border-radius: 16px;
      background: #f2efe9; touch-action: none; user-select: none; cursor: grab;
      box-shadow: 0 0 0 1px rgba(0,0,0,.08), 0 6px 18px -8px rgba(0,0,0,.25);
      isolation: isolate;
    }
    .map:active { cursor: grabbing; }
    .tiles img {
      position: absolute; width: 256px; height: 256px; max-width: none; pointer-events: none;
      opacity: 0; transition: opacity .25s ease;
    }
    .tiles img.ready { opacity: 1; }
    .overlay { position: absolute; inset: 0; pointer-events: none; overflow: visible; }
    .fence { fill: rgba(26, 115, 232, 0.10); stroke: #1a73e8; stroke-width: 2; stroke-opacity: .8; }
    .fence.ok { fill: rgba(30, 142, 62, 0.12); stroke: #1e8e3e; }
    .fence.out { fill: rgba(217, 48, 37, 0.08); stroke: #d93025; stroke-dasharray: 6 5; }
    .link { stroke: #3c4043; stroke-width: 2; stroke-dasharray: 2 6; stroke-linecap: round; opacity: .6; }
    .acc { fill: rgba(26, 115, 232, 0.14); stroke: rgba(26, 115, 232, 0.35); stroke-width: 1; }

    .pin-shop {
      position: absolute; transform: translate(-50%, -100%); pointer-events: none;
      display: flex; flex-direction: column; align-items: center; z-index: 2;
    }
    .pin-shop svg { filter: drop-shadow(0 3px 3px rgba(0,0,0,.3)); display: block; }
    .pin-body { fill: #ea4335; stroke: #b31412; stroke-width: 1; }
    .pin-hole { fill: #b31412; }
    .pin-shadow {
      position: absolute; bottom: -3px; width: 14px; height: 5px; border-radius: 50%;
      background: rgba(0,0,0,.25); filter: blur(1.5px); z-index: -1;
    }
    .pin-label {
      margin-bottom: 6px; padding: 5px 10px; border-radius: 10px; background: #fff; color: #202124;
      font: 600 12.5px/1.2 var(--font); box-shadow: 0 2px 6px rgba(60,64,67,.3); white-space: nowrap;
      max-width: 220px; overflow: hidden; text-overflow: ellipsis; position: relative;
    }
    .pin-label::after {
      content: ''; position: absolute; left: 50%; bottom: -5px; width: 10px; height: 10px; background: #fff;
      transform: translateX(-50%) rotate(45deg); box-shadow: 2px 2px 3px rgba(60,64,67,.15);
    }

    .pin-me { position: absolute; width: 0; height: 0; pointer-events: none; z-index: 1; }
    .pin-me span {
      position: absolute; left: -9px; top: -9px; width: 18px; height: 18px; border-radius: 50%;
      background: #1a73e8; border: 3px solid #fff; box-shadow: 0 1px 5px rgba(0,0,0,.35); box-sizing: border-box;
    }
    .pin-me i {
      position: absolute; left: -9px; top: -9px; width: 18px; height: 18px; border-radius: 50%;
      background: rgba(26,115,232,.35); animation: pulse 2s ease-out infinite;
    }
    @keyframes pulse { 0% { transform: scale(1); opacity: .9; } 100% { transform: scale(3.2); opacity: 0; } }

    .zoom, .center-btn {
      position: absolute; right: 10px; background: #fff; border-radius: 10px;
      box-shadow: 0 1px 4px rgba(60,64,67,.3), 0 1px 1px rgba(60,64,67,.1); z-index: 3;
    }
    .zoom { top: 10px; display: flex; flex-direction: column; overflow: hidden; }
    .zoom .sep { height: 1px; margin: 0 7px; background: #e0e0e0; }
    .zoom button, .center-btn {
      width: 38px; height: 38px; border: 0; background: #fff; color: #5f6368; cursor: pointer;
      display: grid; place-items: center; padding: 0;
    }
    .zoom button:hover:not(:disabled), .center-btn:hover { color: #202124; background: #f6f6f6; }
    .zoom button:disabled { opacity: .35; cursor: default; }
    .center-btn { bottom: 26px; }
    svg path, .center-btn circle { fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; }
    .center-btn .dot { fill: currentColor; stroke: none; }
    .center-btn.active { color: #1a73e8; }

    .scale {
      position: absolute; left: 10px; bottom: 8px; display: flex; align-items: center; gap: 6px; z-index: 3;
      padding: 3px 7px; border-radius: 6px; background: rgba(255,255,255,.85);
      font: 600 11px/1 var(--font); color: #3c4043;
    }
    .scale span { display: block; height: 5px; border: 2px solid #3c4043; border-top: 0; }
    .attrib {
      position: absolute; right: 0; bottom: 0; padding: 2px 7px; background: rgba(255,255,255,.8);
      border-top-left-radius: 6px; font: 10px/1.4 var(--font); color: #5f6368; z-index: 3;
    }
    .attrib a { color: inherit; text-decoration: none; }
    .offline {
      position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); padding: 8px 14px; border-radius: 10px;
      background: rgba(255,255,255,.95); font: 13px var(--font); color: var(--muted); box-shadow: 0 1px 4px rgba(0,0,0,.2); z-index: 4;
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
  useOsm = false;
  private primaryErrors = 0;
  private wheelAcc = 0;
  private pointers = new Map<number, { x: number; y: number }>();
  private pinchStart = 0;

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

  // Mosaicos "World Street Map" de Esri (calles con nombres, parecido a Google Maps; sin clave).
  // Ojo: Esri usa el orden z/y/x. Si no responde, se usan los de OpenStreetMap.
  private tileUrl(z: number, x: number, y: number): string {
    if (this.useOsm) return `https://tile.openstreetmap.org/${z}/${x}/${y}.png`;
    return `https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/${z}/${y}/${x}`;
  }

  tileError(e: Event, t: Tile) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      this.tilesFailed = true;
      return;
    }
    this.primaryErrors++;
    if (!this.useOsm && this.primaryErrors >= 3) {
      this.useOsm = true;
      this.update();
      this.render.schedule();
      return;
    }
    const img = e.target as HTMLImageElement;
    if (!img.dataset['fallback']) {
      img.dataset['fallback'] = '1';
      img.src = t.fallback;
    }
  }

  // Ctrl + rueda del ratón, o pellizco en el touchpad (la rueda sola sigue moviendo la página)
  wheel(e: WheelEvent) {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    this.wheelAcc += e.deltaY;
    if (Math.abs(this.wheelAcc) < 60) return;
    this.zoomBy(this.wheelAcc < 0 ? 1 : -1);
    this.wheelAcc = 0;
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
          url: this.tileUrl(z, wx, ty),
          fallback: `https://tile.openstreetmap.org/${z}/${wx}/${ty}.png`,
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
    this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (this.pointers.size === 2) {
      this.pinchStart = this.pinchDistance();
      this.drag = null;
      return;
    }
    this.drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
    try {
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    } catch {
      // Sin captura: se sigue arrastrando mientras el dedo esté sobre el mapa
    }
  }

  move(e: PointerEvent) {
    if (this.pointers.has(e.pointerId)) this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    // Pellizcar con dos dedos: acercar / alejar
    if (this.pointers.size === 2 && this.pinchStart) {
      const d = this.pinchDistance();
      if (d / this.pinchStart > 1.35) {
        this.zoomBy(1);
        this.pinchStart = d;
      } else if (d / this.pinchStart < 0.74) {
        this.zoomBy(-1);
        this.pinchStart = d;
      }
      return;
    }
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
    this.pointers.delete(e.pointerId);
    if (this.pointers.size < 2) this.pinchStart = 0;
    if (this.drag?.id === e.pointerId) this.drag = null;
  }

  private pinchDistance(): number {
    const [a, b] = [...this.pointers.values()];
    return a && b ? Math.hypot(a.x - b.x, a.y - b.y) : 0;
  }
}
