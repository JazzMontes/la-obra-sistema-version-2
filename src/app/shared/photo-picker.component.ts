// Selector de foto: cámara o galería, con vista previa. Comprime la imagen en el teléfono
// y entrega un data URL JPEG (para productos y tickets de compra).
import { ChangeDetectionStrategy, Component, ElementRef, EventEmitter, Input, Output, ViewChild } from '@angular/core';
import { compressImage } from '../utils/image';
import { RenderService, autoRefresh } from '../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-photo-picker',
  template: `
    <div class="picker" [class.wide]="wide">
      <button type="button" class="preview" (click)="current ? null : camera()" [class.empty]="!current">
        <img *ngIf="current" [apiSrc]="current" [alt]="label" />
        <span *ngIf="!current" class="placeholder">
          <app-icon name="camera"></app-icon>
          <span>{{ label }}</span>
        </span>
      </button>
      <div class="actions">
        <button type="button" class="btn btn-sm" (click)="camera()" [disabled]="busy"><app-icon name="camera"></app-icon>Cámara</button>
        <button type="button" class="btn btn-sm" (click)="gallery()" [disabled]="busy"><app-icon name="image"></app-icon>Galería</button>
        <button type="button" class="btn btn-sm btn-danger-ghost" *ngIf="current" (click)="remove()" [disabled]="busy">Quitar</button>
        <span class="small muted" *ngIf="busy">Procesando…</span>
        <span class="small text-danger" *ngIf="error">{{ error }}</span>
      </div>
      <input #cam type="file" accept="image/*" capture="environment" hidden (change)="pick($event)" />
      <input #gal type="file" accept="image/jpeg,image/png,image/webp" hidden (change)="pick($event)" />
    </div>
  `,
  styles: [`
    .picker { display: flex; gap: 14px; align-items: center; flex-wrap: wrap; }
    .preview { width: 96px; height: 96px; border-radius: 14px; overflow: hidden; padding: 0; cursor: pointer;
      border: 1px solid var(--border); background: var(--surface-2); flex-shrink: 0; }
    .wide .preview { width: 100%; height: 180px; }
    .preview.empty { border-style: dashed; border-color: var(--border-strong); }
    .preview img { width: 100%; height: 100%; object-fit: cover; display: block; }
    .wide .preview img { object-fit: contain; background: var(--surface-3); }
    .placeholder { display: flex; flex-direction: column; align-items: center; gap: 6px; color: var(--muted); font-size: 12px; font-family: var(--font); }
    .placeholder app-icon { width: 24px; height: 24px; }
    .actions { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; }
  `],
  standalone: false,
})
export class PhotoPickerComponent {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  // Foto actual (URL del servidor o data URL)
  @Input() current: string | null = null;
  @Input() label = 'Agregar foto';
  @Input() wide = false;
  // Nueva foto (data URL) o null si se quitó
  @Output() changed = new EventEmitter<string | null>();

  @ViewChild('cam') cam?: ElementRef<HTMLInputElement>;
  @ViewChild('gal') gal?: ElementRef<HTMLInputElement>;
  busy = false;
  error = '';

  constructor(private render: RenderService) {}

  camera() { this.cam?.nativeElement.click(); }
  gallery() { this.gal?.nativeElement.click(); }

  async pick(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    this.busy = true;
    this.error = '';
    try {
      const url = await compressImage(file, this.wide ? 1600 : 1024);
      this.current = url;
      this.changed.emit(url);
    } catch (e: any) {
      this.error = e?.message || 'No se pudo usar la imagen';
    } finally {
      this.busy = false;
      this.render.schedule();
    }
  }

  remove() {
    this.current = null;
    this.changed.emit(null);
  }
}
