// Formulario de insumo (nombre, unidad con la que se usa, otras medidas y existencia mínima).
// Se usa en Insumos y, en Compras y Preparaciones, para registrar uno nuevo sin salir de ahí.
// "Otras medidas": el mismo insumo se puede usar en recetas por pieza, por gramos, por cucharada…
// El inventario y el costo siempre se llevan en la unidad principal.
import { ChangeDetectionStrategy, Component, EventEmitter, Input, OnInit, Output } from '@angular/core';
import { ApiService, errorMessage } from '../services/api';
import { autoRefresh } from '../services/render';

export const UNITS = ['g', 'kg', 'ml', 'L', 'pieza', 'rebanada', 'porción', 'hoja', 'sobre'];

interface UnitRow { id?: number; name: string; unit_amount: number | null; base_amount: number | null; }

// Equivalencias comunes que se sugieren según la unidad principal (se pueden corregir)
const SUGGESTED: Record<string, { name: string; unit_amount: number; base_amount: number | null }[]> = {
  g: [{ name: 'kg', unit_amount: 1, base_amount: 1000 }, { name: 'pieza', unit_amount: 1, base_amount: null },
      { name: 'cucharada', unit_amount: 1, base_amount: 15 }, { name: 'cucharadita', unit_amount: 1, base_amount: 5 }, { name: 'taza', unit_amount: 1, base_amount: 240 }],
  kg: [{ name: 'g', unit_amount: 1000, base_amount: 1 }, { name: 'pieza', unit_amount: 1, base_amount: null }],
  ml: [{ name: 'L', unit_amount: 1, base_amount: 1000 }, { name: 'cucharada', unit_amount: 1, base_amount: 15 },
       { name: 'cucharadita', unit_amount: 1, base_amount: 5 }, { name: 'taza', unit_amount: 1, base_amount: 240 }],
  l: [{ name: 'ml', unit_amount: 1000, base_amount: 1 }, { name: 'taza', unit_amount: 1, base_amount: 0.24 }],
  pieza: [{ name: 'g', unit_amount: null as any, base_amount: 1 }, { name: 'kg', unit_amount: 1, base_amount: null }],
};

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
        <label>Otras medidas (opcional)</label>
        <span class="hint">Para usarlo en recetas con otra medida. Ej. el tomate por <strong>pieza</strong> o por <strong>g</strong>; la mostaza por <strong>g</strong> o por <strong>cucharada</strong>.</span>
        <div class="units" *ngIf="form.units.length">
          <div class="unit-row" *ngFor="let u of form.units; let i = index">
            <input class="input amt" type="number" inputmode="decimal" min="0" step="any" [(ngModel)]="u.unit_amount" aria-label="Cantidad en esta medida" />
            <input class="input uname" [(ngModel)]="u.name" placeholder="pieza, cucharada…" maxlength="30" aria-label="Nombre de la medida" [attr.list]="'if-unit-names'" />
            <span class="eq">=</span>
            <input class="input amt" type="number" inputmode="decimal" min="0" step="any" [(ngModel)]="u.base_amount" placeholder="¿cuánto?" aria-label="Equivale en la unidad principal" />
            <span class="base">{{ form.unit || 'unidad' }}</span>
            <button type="button" class="btn btn-ghost btn-icon" (click)="removeUnit(i)" aria-label="Quitar medida"><app-icon name="trash"></app-icon></button>
          </div>
        </div>
        <datalist id="if-unit-names"><option *ngFor="let n of unitNames" [value]="n"></option></datalist>
        <div class="unit-chips small-chips">
          <button type="button" *ngFor="let sug of suggestions" (click)="addUnit(sug)">+ {{ sug.name }}</button>
          <button type="button" (click)="addUnit()">+ Otra medida</button>
        </div>
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
    .units { display: flex; flex-direction: column; gap: 6px; }
    .unit-row { display: grid; grid-template-columns: 70px minmax(0, 1fr) auto 80px auto 36px; gap: 6px; align-items: center; }
    .unit-row .eq, .unit-row .base { font-size: 13px; color: var(--muted); white-space: nowrap; }
    .small-chips button { height: 28px; font-size: 12px; border-style: dashed; }
    @media (max-width: 420px) { .unit-row { grid-template-columns: 56px minmax(0, 1fr) auto 64px auto 32px; } }
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

  readonly unitNames = ['pieza', 'g', 'kg', 'ml', 'L', 'cucharada', 'cucharadita', 'taza', 'rebanada', 'porción', 'paquete', 'lata', 'sobre'];

  ngOnInit() {
    const v = this.value;
    this.form = {
      name: v?.name ?? this.initialName,
      unit: v?.unit ?? '',
      min_stock: v?.min_stock ?? null,
      units: (v?.units ?? []).map((u: any) => ({ id: u.id, name: u.name, unit_amount: Number(u.unit_amount), base_amount: Number(u.base_amount) })) as UnitRow[],
    };
  }

  // Sugerencias que aún no están en la lista (y que no son la unidad principal)
  get suggestions() {
    const base = String(this.form.unit || '').trim().toLowerCase();
    const have = new Set((this.form.units as UnitRow[]).map(u => String(u.name).trim().toLowerCase()));
    return (SUGGESTED[base] ?? []).filter(x => x.name.toLowerCase() !== base && !have.has(x.name.toLowerCase())).slice(0, 4);
  }

  addUnit(s?: { name: string; unit_amount: number | null; base_amount: number | null }) {
    this.form.units.push({ name: s?.name ?? '', unit_amount: s ? s.unit_amount : 1, base_amount: s ? s.base_amount : null });
  }

  removeUnit(i: number) {
    this.form.units.splice(i, 1);
  }

  // Valida y guarda; el componente padre llama a este método desde su botón
  async submit(): Promise<boolean> {
    if (this.saving) return false;
    this.error = '';
    const f = this.form;
    if (!String(f.name || '').trim()) { this.error = 'Escribe el nombre del insumo'; return false; }
    if (!String(f.unit || '').trim()) { this.error = 'Elige la unidad de medida'; return false; }
    // Otras medidas: se ignoran los renglones vacíos; los incompletos se avisan
    const rows = (f.units as UnitRow[]).filter(u => String(u.name || '').trim() || u.base_amount);
    const base = String(f.unit).trim().toLowerCase();
    for (const u of rows) {
      const n = String(u.name || '').trim();
      if (!n) { this.error = 'Escribe el nombre de cada medida (pieza, cucharada…)'; return false; }
      if (n.toLowerCase() === base) { this.error = `"${n}" ya es la unidad principal`; return false; }
      if (!(Number(u.unit_amount) > 0) || !(Number(u.base_amount) > 0)) { this.error = `Indica a cuánto equivale "${n}" en ${f.unit}`; return false; }
    }
    const names = rows.map(u => String(u.name).trim().toLowerCase());
    if (new Set(names).size !== names.length) { this.error = 'Hay una medida repetida'; return false; }
    // Cómo se compra (paquete, caja…) se captura en cada compra, no aquí
    const body = {
      name: String(f.name).trim(),
      unit: String(f.unit).trim(),
      min_stock: f.min_stock === null || f.min_stock === '' ? null : Number(f.min_stock),
      units: rows.map(u => ({ id: u.id ?? null, name: String(u.name).trim(), unit_amount: Number(u.unit_amount), base_amount: Number(u.base_amount) })),
    };
    this.saving = true;
    try {
      if (this.value?.id) {
        const r = await this.api.patch('inputs/update.php', { id: this.value.id, ...body });
        this.saved.emit({ ...this.value, ...body, units: r.units ?? this.value.units ?? [] });
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
