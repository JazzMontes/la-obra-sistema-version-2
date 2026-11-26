// Formulario de insumo: nombre, unidad con la que lo usas, otras medidas y su costo.
// Se usa en Insumos y, en Compras y Preparaciones, para registrar uno nuevo sin salir de ahí.
//  · Unidad principal: con la que lo usas; en ella se llevan el costo y el inventario.
//  · Otras medidas: cada una dice cuánto trae (1 paquete = 20 rebanadas) y para qué sirve:
//    para recetas, para compras o para las dos. En Compras solo aparecen las de compras.
//  · Costo: sale de tu última compra, pero lo puedes cambiar aquí (gana el más reciente).
import { ChangeDetectionStrategy, Component, EventEmitter, Input, OnInit, Output } from '@angular/core';
import { ApiService, errorMessage } from '../services/api';
import { autoRefresh } from '../services/render';

export const UNITS = ['g', 'kg', 'ml', 'L', 'pieza', 'rebanada', 'porción', 'hoja', 'sobre'];

type UseIn = 'recipe' | 'purchase' | 'both';
interface UnitRow { id?: number; name: string; unit_amount: number | null; base_amount: number | null; use_in: UseIn; }

// Equivalencias comunes que se sugieren según la unidad principal (se pueden corregir)
const SUGGESTED: Record<string, { name: string; unit_amount: number; base_amount: number | null; use_in: UseIn }[]> = {
  g: [{ name: 'kg', unit_amount: 1, base_amount: 1000, use_in: 'purchase' }, { name: 'paquete', unit_amount: 1, base_amount: null, use_in: 'purchase' },
      { name: 'pieza', unit_amount: 1, base_amount: null, use_in: 'both' }, { name: 'cucharada', unit_amount: 1, base_amount: 15, use_in: 'recipe' }],
  kg: [{ name: 'g', unit_amount: 1000, base_amount: 1, use_in: 'recipe' }, { name: 'paquete', unit_amount: 1, base_amount: null, use_in: 'purchase' }],
  ml: [{ name: 'L', unit_amount: 1, base_amount: 1000, use_in: 'purchase' }, { name: 'botella', unit_amount: 1, base_amount: null, use_in: 'purchase' },
       { name: 'cucharada', unit_amount: 1, base_amount: 15, use_in: 'recipe' }],
  l: [{ name: 'ml', unit_amount: 1000, base_amount: 1, use_in: 'recipe' }, { name: 'garrafa', unit_amount: 1, base_amount: null, use_in: 'purchase' }],
  pieza: [{ name: 'paquete', unit_amount: 1, base_amount: null, use_in: 'purchase' }, { name: 'caja', unit_amount: 1, base_amount: null, use_in: 'purchase' },
          { name: 'docena', unit_amount: 1, base_amount: 12, use_in: 'purchase' }],
  rebanada: [{ name: 'paquete', unit_amount: 1, base_amount: null, use_in: 'purchase' }, { name: 'kg', unit_amount: 1, base_amount: null, use_in: 'purchase' }],
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
        <label>¿Con qué unidad lo usas?</label>
        <div class="unit-chips">
          <button type="button" *ngFor="let u of units" [class.active]="form.unit === u" (click)="form.unit = u">{{ u }}</button>
        </div>
        <input class="input" [(ngModel)]="form.unit" placeholder="Otra unidad" maxlength="20" aria-label="Unidad principal" />
        <span class="hint">Es tu unidad principal: en ella se calcula el costo. Ej. el queso por rebanada, la carne por g, el pan por pieza.</span>
      </div>

      <div class="field">
        <label>Otras medidas</label>
        <span class="hint">Cómo lo compras (1 <strong>paquete</strong> = 20 rebanada) y otras medidas para tus recetas (1 <strong>cucharada</strong> = 15 g). Marca para qué sirve cada una.</span>
        <div class="units" *ngIf="form.units.length">
          <div class="unit-row" *ngFor="let u of form.units; let i = index">
            <div class="eq-line">
              <input class="input amt" type="number" inputmode="decimal" min="0" step="any" [(ngModel)]="u.unit_amount" aria-label="Cantidad en esta medida" />
              <input class="input uname" [(ngModel)]="u.name" placeholder="paquete, kg…" maxlength="30" aria-label="Nombre de la medida" [attr.list]="'if-unit-names'" />
              <span class="eq">=</span>
              <input class="input amt" type="number" inputmode="decimal" min="0" step="any" [(ngModel)]="u.base_amount" placeholder="¿cuánto?" aria-label="Equivale en la unidad principal" />
              <span class="base">{{ form.unit || 'unidad' }}</span>
              <button type="button" class="btn btn-ghost btn-icon" (click)="removeUnit(i)" aria-label="Quitar medida"><app-icon name="trash"></app-icon></button>
            </div>
            <div class="use-in">
              <span>Sirve para</span>
              <button type="button" [class.on]="u.use_in !== 'recipe'" (click)="toggleUse(u, 'purchase')"><app-icon name="purchases"></app-icon>Compras</button>
              <button type="button" [class.on]="u.use_in !== 'purchase'" (click)="toggleUse(u, 'recipe')"><app-icon name="preparations"></app-icon>Recetas</button>
            </div>
          </div>
        </div>
        <datalist id="if-unit-names"><option *ngFor="let n of unitNames" [value]="n"></option></datalist>
        <div class="unit-chips small-chips">
          <button type="button" *ngFor="let sug of suggestions" (click)="addUnit(sug)">+ {{ sug.name }}</button>
          <button type="button" (click)="addUnit()">+ Otra medida</button>
        </div>
      </div>

      <div class="field cost-box">
        <label for="if-cost">Costo</label>
        <div class="cost-line">
          <div class="input-group grow">
            <span class="addon">$</span>
            <input id="if-cost" class="input" type="number" inputmode="decimal" min="0" step="any" [(ngModel)]="form.cost" (ngModelChange)="costTouched = true" placeholder="Sin costo" />
          </div>
          <span class="por">por</span>
          <select class="select cost-unit" [(ngModel)]="form.cost_unit" (ngModelChange)="onCostUnit()" aria-label="Unidad del costo">
            <option *ngFor="let o of costUnits" [ngValue]="o.name">{{ o.name }}</option>
          </select>
        </div>
        <span class="hint" *ngIf="baseCostPreview !== null && form.cost_unit !== form.unit">= {{ baseCostPreview | money }} por {{ form.unit }}</span>
        <span class="hint" *ngIf="value?.last_purchase as lp">
          Última compra ({{ lp.date | dateMx: 'short' }}): {{ lp.quantity | qty }} {{ lp.buy_unit || value.unit }} a {{ lp.unit_cost | money }} c/u
          <ng-container *ngIf="lp.base_cost !== null"> → {{ lp.base_cost | money }} por {{ value.unit }}</ng-container>
        </span>
        <span class="hint" *ngIf="value?.cost_source === 'manual'">
          Ahora usa el costo que pusiste a mano. <button type="button" class="link small" (click)="useLastPurchase()" *ngIf="value?.last_purchase">Usar el de la última compra</button>
        </span>
        <span class="hint" *ngIf="!value?.last_purchase && value?.cost_source !== 'manual'">Se llena solo con tu próxima compra. También lo puedes escribir aquí.</span>
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
    .units { display: flex; flex-direction: column; gap: 8px; }
    .unit-row { padding: 8px; border-radius: 12px; background: var(--surface-2); border: 1px solid var(--border); }
    .eq-line { display: grid; grid-template-columns: 64px minmax(0, 1fr) auto 80px auto 36px; gap: 6px; align-items: center; }
    .eq-line .eq, .eq-line .base { font-size: 13px; color: var(--muted); white-space: nowrap; }
    .use-in { display: flex; align-items: center; gap: 6px; margin-top: 6px; font-size: 12px; color: var(--muted); flex-wrap: wrap; }
    .use-in button {
      display: inline-flex; align-items: center; gap: 4px; height: 26px; padding: 0 10px; border-radius: 99px;
      border: 1px dashed var(--border-strong); background: var(--surface); color: var(--faint); font: inherit; font-size: 12px; cursor: pointer;
    }
    .use-in button app-icon { width: 13px; height: 13px; }
    .use-in button.on { border-style: solid; border-color: var(--brand-hover); background: var(--brand-soft); color: var(--brand-ink); font-weight: 600; }
    .small-chips button { height: 28px; font-size: 12px; border-style: dashed; }
    .cost-box { padding: 12px; border-radius: 12px; background: var(--brand-soft); }
    .cost-line { display: flex; align-items: center; gap: 8px; }
    .cost-line .por { font-size: 13px; color: var(--muted); }
    .cost-unit { width: 130px; }
    .link { background: none; border: 0; padding: 0; color: var(--info); cursor: pointer; font: inherit; }
    @media (max-width: 480px) {
      /* En el teléfono: "1 paquete" arriba y "= 20 rebanada" abajo */
      .eq-line { grid-template-columns: 72px minmax(0, 1fr) 36px; grid-template-areas: 'a n t' 'b u u'; }
      .eq-line > :nth-child(1) { grid-area: a; } .eq-line > :nth-child(2) { grid-area: n; } .eq-line > :nth-child(6) { grid-area: t; }
      .eq-line > :nth-child(3) { display: none; }
      .eq-line > :nth-child(4) { grid-area: b; }
      .eq-line > :nth-child(5) { grid-area: u; }
      .eq-line > :nth-child(5)::before { content: '= '; }
      .cost-unit { width: 104px; }
    }
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
  costTouched = false;
  private resetCost = false;

  constructor(private api: ApiService) {}

  readonly unitNames = ['paquete', 'caja', 'bolsa', 'kg', 'g', 'L', 'ml', 'pieza', 'docena', 'cucharada', 'cucharadita', 'taza', 'rebanada', 'porción', 'lata', 'sobre', 'botella', 'manojo'];

  ngOnInit() {
    const v = this.value;
    this.form = {
      name: v?.name ?? this.initialName,
      unit: v?.unit ?? '',
      units: (v?.units ?? []).map((u: any) => ({
        id: u.id, name: u.name, unit_amount: Number(u.unit_amount), base_amount: Number(u.base_amount), use_in: (u.use_in || 'both') as UseIn,
      })) as UnitRow[],
      cost: v?.unit_cost !== null && v?.unit_cost !== undefined ? Math.round(Number(v.unit_cost) * 10000) / 10000 : null,
      cost_unit: v?.unit ?? '',
    };
  }

  // Sugerencias que aún no están en la lista (y que no son la unidad principal)
  get suggestions() {
    const base = String(this.form.unit || '').trim().toLowerCase();
    const have = new Set((this.form.units as UnitRow[]).map(u => String(u.name).trim().toLowerCase()));
    return (SUGGESTED[base] ?? []).filter(x => x.name.toLowerCase() !== base && !have.has(x.name.toLowerCase())).slice(0, 4);
  }

  addUnit(s?: { name: string; unit_amount: number | null; base_amount: number | null; use_in: UseIn }) {
    this.form.units.push({ name: s?.name ?? '', unit_amount: s ? s.unit_amount : 1, base_amount: s ? s.base_amount : null, use_in: s?.use_in ?? 'both' });
  }

  removeUnit(i: number) {
    this.form.units.splice(i, 1);
  }

  // Prende o apaga "Compras" / "Recetas" (siempre queda al menos una)
  toggleUse(u: UnitRow, which: 'recipe' | 'purchase') {
    const recipe = u.use_in !== 'purchase';
    const purchase = u.use_in !== 'recipe';
    const r = which === 'recipe' ? !recipe : recipe;
    const p = which === 'purchase' ? !purchase : purchase;
    if (!r && !p) return;
    u.use_in = r && p ? 'both' : r ? 'recipe' : 'purchase';
  }

  // ---------- Costo ----------
  // Unidades en que se puede escribir el costo: la principal y las demás (se convierte a la principal)
  get costUnits(): { name: string; factor: number }[] {
    const base = String(this.form.unit || '').trim();
    const extra = (this.form.units as UnitRow[])
      .filter(u => String(u.name || '').trim() && Number(u.unit_amount) > 0 && Number(u.base_amount) > 0)
      .map(u => ({ name: String(u.name).trim(), factor: Number(u.base_amount) / Number(u.unit_amount) }));
    return [{ name: base || 'unidad', factor: 1 }, ...extra];
  }

  private factorOf(name: string): number {
    return this.costUnits.find(o => o.name === name)?.factor ?? 1;
  }

  // Al cambiar "por kg" → "por paquete" se muestra el mismo costo en la nueva unidad
  private lastCostUnit = '';
  onCostUnit() {
    const prev = this.lastCostUnit || this.form.unit;
    if (this.form.cost !== null && this.form.cost !== '' && !this.costTouched) {
      const perBase = Number(this.form.cost) / this.factorOf(prev);
      this.form.cost = Math.round(perBase * this.factorOf(this.form.cost_unit) * 10000) / 10000;
    }
    this.lastCostUnit = this.form.cost_unit;
  }

  get baseCostPreview(): number | null {
    if (this.form.cost === null || this.form.cost === '' || !Number.isFinite(Number(this.form.cost))) return null;
    return Number(this.form.cost) / this.factorOf(this.form.cost_unit);
  }

  useLastPurchase() {
    this.resetCost = true;
    this.costTouched = false;
    const lp = this.value?.last_purchase;
    this.form.cost_unit = this.form.unit;
    this.lastCostUnit = this.form.unit;
    this.form.cost = lp?.base_cost !== null && lp?.base_cost !== undefined ? Math.round(Number(lp.base_cost) * 10000) / 10000 : null;
  }

  // Valida y guarda; el componente padre llama a este método desde su botón
  async submit(): Promise<boolean> {
    if (this.saving) return false;
    this.error = '';
    const f = this.form;
    if (!String(f.name || '').trim()) { this.error = 'Escribe el nombre del insumo'; return false; }
    if (!String(f.unit || '').trim()) { this.error = 'Elige la unidad con la que lo usas'; return false; }
    // Otras medidas: se ignoran los renglones vacíos; los incompletos se avisan
    const rows = (f.units as UnitRow[]).filter(u => String(u.name || '').trim() || u.base_amount);
    const base = String(f.unit).trim().toLowerCase();
    for (const u of rows) {
      const n = String(u.name || '').trim();
      if (!n) { this.error = 'Escribe el nombre de cada medida (paquete, cucharada…)'; return false; }
      if (n.toLowerCase() === base) { this.error = `"${n}" ya es la unidad principal`; return false; }
      if (!(Number(u.unit_amount) > 0) || !(Number(u.base_amount) > 0)) { this.error = `Indica cuánto ${f.unit} trae "${n}"`; return false; }
    }
    const names = rows.map(u => String(u.name).trim().toLowerCase());
    if (new Set(names).size !== names.length) { this.error = 'Hay una medida repetida'; return false; }
    const costBase = this.baseCostPreview;
    if (f.cost !== null && f.cost !== '' && (costBase === null || costBase < 0)) { this.error = 'Revisa el costo'; return false; }

    const body = {
      name: String(f.name).trim(),
      unit: String(f.unit).trim(),
      units: rows.map(u => ({ id: u.id ?? null, name: String(u.name).trim(), unit_amount: Number(u.unit_amount), base_amount: Number(u.base_amount), use_in: u.use_in })),
    };
    // ¿Cambió el costo? (se compara en la unidad principal)
    const before = this.value?.unit_cost ?? null;
    const costChanged = this.resetCost || (costBase !== null && (before === null || Math.abs(Number(before) - costBase) > 0.00005));

    this.saving = true;
    try {
      let saved: any;
      if (this.value?.id) {
        const r = await this.api.patch('inputs/update.php', { id: this.value.id, ...body });
        saved = { ...this.value, ...body, units: r.units ?? this.value.units ?? [] };
      } else {
        saved = (await this.api.post('inputs/create.php', body)).input;
      }
      if (costChanged) {
        const cost = this.resetCost && !this.costTouched ? null : Math.round((costBase as number) * 10000) / 10000;
        try {
          const r = await this.api.post('inputs/set-cost', { id: saved.id, cost });
          saved = { ...saved, unit_cost: r.unit_cost, cost_source: cost === null ? 'purchase' : 'manual' };
        } catch (e) {
          this.error = 'El insumo se guardó, pero el costo no: ' + errorMessage(e);
          return false;
        }
      }
      this.saved.emit(saved);
      return true;
    } catch (e) {
      this.error = errorMessage(e, 'No se pudo guardar el insumo');
      return false;
    } finally {
      this.saving = false;
    }
  }
}
