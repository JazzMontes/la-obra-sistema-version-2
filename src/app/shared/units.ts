// Medidas de un insumo: la principal (la del inventario y el costo) y las otras que se
// registraron en Insumos (pieza, cucharada…). Se usan al capturar recetas y existencias.

export interface UnitOption {
  id: number | null; // null = unidad principal
  name: string;
  factor: number;    // unidades principales que hay en 1 de esta medida
  unit_amount?: number;
  base_amount?: number;
}

// purpose: 'recipe' = medidas para recetas · 'purchase' = medidas para comprar · sin valor = todas
// (cada medida del insumo dice para qué sirve en use_in: recipe, purchase o both)
export function unitOptions(input: any, purpose?: 'recipe' | 'purchase'): UnitOption[] {
  if (!input) return [];
  const all = Array.isArray(input.units) ? input.units : [];
  const extra = purpose ? all.filter((u: any) => !u.use_in || u.use_in === 'both' || u.use_in === purpose) : all;
  return [
    { id: null, name: String(input.unit ?? ''), factor: 1 },
    ...extra.map((u: any) => ({
      id: Number(u.id),
      name: String(u.name),
      factor: Number(u.factor) || Number(u.base_amount) / (Number(u.unit_amount) || 1),
      unit_amount: Number(u.unit_amount) || 1,
      base_amount: Number(u.base_amount),
    })),
  ];
}

// Cantidad en la unidad principal
export function toBase(input: any, unitId: number | null | undefined, qty: number | null | undefined): number {
  const q = Number(qty) || 0;
  if (!unitId) return q;
  const u = unitOptions(input).find(o => o.id === Number(unitId));
  return u ? q * u.factor : q;
}

export function unitName(input: any, unitId: number | null | undefined): string {
  if (!input) return '—';
  if (!unitId) return input.unit ?? '';
  return unitOptions(input).find(o => o.id === Number(unitId))?.name ?? input.unit ?? '';
}

// "1 cucharada = 15 g · 120 g = 1 pieza"
export function unitsSummary(input: any): string {
  const n = (v: number | undefined) => String(+Number(v ?? 0).toFixed(3));
  return unitOptions(input)
    .filter(o => o.id !== null)
    .map(o => `${n(o.unit_amount)} ${o.name} = ${n(o.base_amount)} ${input.unit}`)
    .join(' · ');
}
