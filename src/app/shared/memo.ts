// Guarda el resultado de un cálculo y lo reutiliza mientras sus dependencias no cambien.
// Evita que un getter devuelva un arreglo nuevo en cada lectura (Angular lo marcaría como
// cambio y lanzaría NG0100 "ExpressionChangedAfterItHasBeenChecked").
export class Memo {
  private cache = new Map<string, { deps: unknown[]; value: unknown }>();

  get<T>(key: string, deps: unknown[], compute: () => T): T {
    const hit = this.cache.get(key);
    if (hit && hit.deps.length === deps.length && hit.deps.every((d, i) => Object.is(d, deps[i]))) {
      return hit.value as T;
    }
    const value = compute();
    this.cache.set(key, { deps, value });
    return value;
  }
}
