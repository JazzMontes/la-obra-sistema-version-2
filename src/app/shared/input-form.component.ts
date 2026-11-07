// Formulario de insumo (nombre, unidad con la que se usa y existencia mínima).
// Se usa en Insumos y, en Compras, para registrar uno nuevo sin salir de la compra.
import { ChangeDetectionStrategy, Component, EventEmitter, Input, OnInit, Output } from '@angular/core';
import { ApiService, errorMessage } from '../services/api';
import { autoRefresh } from '../services/render';

export const UNITS = ['g', 'kg', 'ml', 'L', 'pieza', 'rebanada', 'porción', 'hoja', 'sobre'];

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-input-form',
  template: `
    <div class="stack">
      <div class="field">
        <label for="if-name">Nombre</label>
        <input id="if-name" class="input" [(ngModel)]="form.name" placeholder="Ej. Queso amarillo" maxlength="100" />
      </div>
      <div class="field">
        <label>Unidad con la que lo usas en recetas</label>
        <div class="unit-chips">
          <button type="button" *ngFor="let u of units" [class.active]="form.unit === u" (click)="form.unit = u">{{ u }}</button>
        </div>
        <input class="input" [(ngModel)]="form.unit" placeholder="Otra unidad" maxlength="20" />
        <span class="hint">Es la unidad que se descuenta del inventario. Ej. el queso se usa por rebanada; la carne, por gramo.</span>
      </div>
      <div class="field">
        <label for="if-min">Existencia mínima (opcional)</label>
        <div class="input-group">
          <input id="if-min" class="input" type="number" inputmode="decimal" min="0" step="any" [(ngModel)]="form.min_stock" placeholder="Sin alerta" />
          <span class="addon">{{ form.unit || 'unidad' }}</span>
        </div>
        <span class="hint">Te avisamos en Inicio e Inventario cuando quede esta cantidad o menos.</span>
      </div>
      <div class="form-error" *ngIf="error">{{ error }}</div>
    </div>
  `,
  styles: [`
    .unit-chips { display: flex; flex-wrap: wrap; gap: 6px; }
    .unit-chips button {
      height: 32px; padding: 0 12px; border-radius: 999px; border: 1px solid var(--border-strong);
      background: var(--surface); font: inherit; font-size: 13px; cursor: pointer; color: var(--text-2);
    }
    .unit-chips button.active { background: var(--ink); color: #fff; border-color: var(--ink); }
    .hint { font-size: 12px; color: var(--muted); }
  `],
  standalone: false,
})
export class InputFormComponent implements OnInit {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();

  @Input() value: any = null;
  @Input() initialName = '';
  @Output() saved = new EventEmitter<any>();

  readonly units = UNITS;
  form: any = {};
  error = '';
  saving = false;

  constructor(private api: ApiService) {}

  ngOnInit() {
    const v = this.value;
    this.form = {
      name: v?.name ?? this.initialName,
      unit: v?.unit ?? '',
      min_stock: v?.min_stock ?? null,
    };
  }

  // Valida y guarda; el componente padre llama a este método desde su botón
  async submit(): Promise<boolean> {
    if (this.saving) return false;
    this.error = '';
    const f = this.form;
    if (!String(f.name || '').trim()) { this.error = 'Escribe el nombre del insumo'; return false; }
    if (!String(f.unit || '').trim()) { this.error = 'Elige la unidad de medida'; return false; }
    // Cómo se compra (paquete, caja…) se captura en cada compra, no aquí
    const body = {
      name: String(f.name).trim(),
      unit: String(f.unit).trim(),
      min_stock: f.min_stock === null || f.min_stock === '' ? null : Number(f.min_stock),
    };
    this.saving = true;
    try {
      if (this.value?.id) {
        await this.api.patch('inputs/update.php', { id: this.value.id, ...body });
        this.saved.emit({ ...this.value, ...body });
      } else {
        const r = await this.api.post('inputs/create.php', body);
        this.saved.emit(r.input);
      }
      return true;
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo guardar el insumo');
      return false;
    } finally {
      this.saving = false;
    }
  }
}
