// Productos y recetas: lo que se vende, su foto y qué lleva cada uno.
// Los datos del producto se pueden editar sin conexión (se sincronizan después);
// la receta conecta insumos y preparaciones con el costo y con el inventario.
import { ChangeDetectionStrategy, Component, NgZone, OnDestroy, OnInit } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Products } from '../../services/products';
import { ProductSync } from '../../services/product-sync';
import { dataUrlToBlob } from '../../utils/image';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';

interface RecipeLine {
  ref: string | null;   // 'i:12' insumo, 'p:3' preparación
  quantity: number | null;
  delivery_mode: 'always' | 'local' | 'takeaway';
  is_estimated: boolean;
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-products',
  templateUrl: 'products.page.html',
  styleUrls: ['products.page.scss'],
  standalone: false,
})
export class ProductsPage implements OnInit, OnDestroy {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  products: any[] = [];
  categories: any[] = [];
  inputs: any[] = [];
  preparations: any[] = [];
  costs = new Map<number, any>();
  loading = true;
  query = '';
  category: number | null = null;
  status: 'active' | 'inactive' = 'active';

  // Conexión y sincronización
  offline = !navigator.onLine;
  pendingCount = 0;
  failed: any[] = [];
  syncing = false;

  // Editor
  open = false;
  tab: 'data' | 'recipe' = 'data';
  editingId: number | null = null;
  form: any = {};
  photo: string | null = null;
  newPhoto: string | null | undefined = undefined;
  recipe: RecipeLine[] = [];
  recipeLoaded = false;
  saving = false;
  formError = '';

  private onOnline = () => this.zone.run(() => this.syncNow());
  private onOffline = () => this.zone.run(() => (this.offline = true));

  constructor(
    private api: ApiService,
    private ui: UiService,
    private productsApi: Products,
    private sync: ProductSync,
    private zone: NgZone
  ) {}

  ngOnInit() {
    window.addEventListener('online', this.onOnline);
    window.addEventListener('offline', this.onOffline);
  }

  ngOnDestroy() {
    window.removeEventListener('online', this.onOnline);
    window.removeEventListener('offline', this.onOffline);
  }

  ionViewWillEnter() {
    this.load();
  }

  // ---------- Carga y sincronización ----------

  async load() {
    this.offline = !navigator.onLine;
    try {
      if (this.offline) {
        this.useLocal();
        return;
      }
      await this.sync.synchronize();
      const [p, c] = await Promise.allSettled([this.productsApi.getAll(), this.api.get('categories/index.php')]);
      if (p.status === 'fulfilled') {
        this.sync.saveProducts(p.value.products || []);
        this.products = this.sync.applyPending();
      } else if (this.sync.isNetworkError(p.reason)) {
        this.offline = true;
        this.useLocal();
        return;
      } else {
        throw p.reason;
      }
      if (c.status === 'fulfilled') {
        this.categories = c.value.categories;
        this.sync.saveCategories(this.categories);
      } else {
        this.categories = this.sync.getCategories();
      }
      this.loadRecipeCatalogs();
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar los productos'));
    } finally {
      this.pendingCount = this.sync.pendingCount;
      this.failed = this.sync.getFailed();
      this.loading = false;
    }
  }

  private useLocal() {
    this.products = this.sync.applyPending();
    this.categories = this.sync.getCategories();
    if (!this.sync.hasProducts()) this.ui.info('Sin conexión y sin productos guardados en este dispositivo');
  }

  // Insumos, preparaciones y costos para el editor de recetas
  async loadRecipeCatalogs() {
    try {
      const [inv, prep, costs] = await Promise.all([
        this.api.get('inventory/index.php'),
        this.api.get('preparations/index.php'),
        this.api.get('costs/index.php'),
      ]);
      this.inputs = inv.inventory.filter((i: any) => i.status === 'active');
      this.preparations = prep.preparations;
      this.costs = new Map(costs.products.map((c: any) => [Number(c.product_id), c]));
    } catch {
      // El catálogo de productos funciona aunque esto falle
    }
  }

  async syncNow() {
    this.offline = !navigator.onLine;
    if (this.offline || this.syncing) return;
    this.syncing = true;
    const r = await this.sync.synchronize();
    this.syncing = false;
    if (r.sent) this.ui.success(`${r.sent} cambio(s) sincronizados`);
    await this.load();
  }

  clearFailed() {
    this.sync.clearFailed();
    this.failed = [];
  }

  // ---------- Listado ----------

  get visible(): any[] {
    return this.memo.get('visible', [this.products, this.query, this.category, this.status], () => this.computeVisible());
  }

  private computeVisible(): any[] {
    const q = this.query.trim().toLowerCase();
    return this.products.filter(p =>
      (p.status ?? 'active') === this.status &&
      (!this.category || Number(p.category?.id ?? p.category_id) === this.category) &&
      (!q || String(p.name).toLowerCase().includes(q))
    );
  }

  get activeCategories(): any[] {
    return this.memo.get('activeCategories', [this.categories], () => this.categories.filter(c => c.status === 'active'));
  }

  imageUrl(p: any): string | null {
    return p?._imgError ? null : this.productsApi.imageUrl(p?.image_path);
  }

  cost(p: any): any {
    return this.costs.get(Number(p.id));
  }

  typeLabel(t: string): string {
    return t === 'resale' ? 'Reventa' : 'Preparado';
  }

  // ---------- Editor ----------

  openNew() {
    this.editingId = null;
    this.form = { name: '', description: '', category_id: this.activeCategories[0]?.id ?? null, type: 'prepared', price: null, is_available: true };
    this.photo = null;
    this.newPhoto = undefined;
    this.recipe = [];
    this.recipeLoaded = true;
    this.tab = 'data';
    this.formError = '';
    this.open = true;
  }

  async openEdit(p: any) {
    this.editingId = Number(p.id);
    this.form = {
      name: p.name,
      description: p.description,
      category_id: Number(p.category?.id ?? p.category_id),
      type: p.type,
      price: Number(p.price),
      is_available: p.is_available !== false && p.is_available !== 0,
      status: p.status,
    };
    this.photo = p._imgError ? null : p.image_path || null;
    this.newPhoto = undefined;
    this.recipe = [];
    this.recipeLoaded = false;
    this.tab = 'data';
    this.formError = '';
    this.open = true;
    if (this.editingId > 0 && !this.offline) this.loadRecipe(this.editingId);
  }

  async loadRecipe(id: number) {
    try {
      const rows = (await this.api.get('products/components.php', { product_id: id })).components;
      this.recipe = rows.map((r: any) => ({
        ref: r.input_id !== null ? `i:${r.input_id}` : `p:${r.preparation_id}`,
        quantity: Number(r.quantity),
        delivery_mode: r.delivery_mode,
        is_estimated: !!Number(r.is_estimated),
      }));
      this.recipeLoaded = true;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo cargar la receta'));
    }
  }

  onPhoto(v: string | null) {
    this.newPhoto = v;
    this.photo = v;
  }

  private validData(): boolean {
    const f = this.form;
    if (!String(f.name || '').trim()) return this.fail('Escribe el nombre del producto');
    if (!String(f.description || '').trim()) return this.fail('Escribe una descripción breve');
    if (!f.category_id) return this.fail('Elige una categoría');
    if (f.price === null || f.price === '' || !(Number(f.price) >= 0)) return this.fail('Indica el precio de venta');
    return true;
  }

  private fail(msg: string): boolean {
    this.formError = msg;
    return false;
  }

  async saveData() {
    if (this.saving) return;
    this.formError = '';
    if (!this.validData()) return;
    const f = this.form;
    const changes: any = {
      name: String(f.name).trim(),
      description: String(f.description).trim(),
      category_id: Number(f.category_id),
      type: f.type,
      price: Math.round(Number(f.price) * 100) / 100,
    };
    if (this.editingId) changes.is_available = !!f.is_available;
    this.saving = true;

    // Sin conexión o producto que aún no llega al servidor: a la cola local
    if (this.offline || !navigator.onLine || (this.editingId ?? 0) < 0) {
      this.saveOffline(changes);
      this.saving = false;
      return;
    }
    try {
      let id = this.editingId;
      if (id) {
        await this.productsApi.update(id, changes);
      } else {
        const r = await this.productsApi.create(changes.name, changes.description, changes.category_id, changes.type, changes.price);
        id = Number(r?.product?.id) || null;
      }
      if (id && this.newPhoto) {
        try {
          await this.productsApi.uploadImage(id, dataUrlToBlob(this.newPhoto));
        } catch (e) {
          if (this.sync.isNetworkError(e)) this.sync.queueUpdate(id, {}, this.newPhoto);
          else this.ui.error('El producto se guardó, pero la foto no: ' + errorMessage(e));
        }
      } else if (id && this.newPhoto === null && this.editingId) {
        await this.productsApi.deleteImage(id);
      }
      const wasNew = !this.editingId;
      this.editingId = id;
      this.newPhoto = undefined;
      await this.load();
      if (wasNew && id) {
        this.ui.success('Producto creado. Ahora define su receta.');
        this.tab = 'recipe';
        this.recipeLoaded = true;
      } else {
        this.ui.success('Producto guardado');
        this.open = false;
      }
    } catch (e) {
      if (this.sync.isNetworkError(e)) {
        this.offline = true;
        this.saveOffline(changes);
      } else {
        this.formError = errorMessage(e, 'No se pudo guardar el producto');
      }
    } finally {
      this.saving = false;
    }
  }

  private saveOffline(changes: any) {
    try {
      if (this.editingId) this.sync.queueUpdate(this.editingId, changes, this.newPhoto ?? undefined);
      else this.sync.queueCreate(changes, this.newPhoto);
      this.products = this.sync.applyPending();
      this.pendingCount = this.sync.pendingCount;
      this.open = false;
      this.ui.info('Guardado en el dispositivo; se sincronizará al volver la conexión');
    } catch (e: any) {
      this.formError = e?.message || 'No se pudo guardar localmente';
    }
  }

  async toggleStatus() {
    const id = this.editingId;
    if (!id || id < 0) return;
    const activate = this.form.status !== 'active';
    try {
      if (activate) await this.productsApi.activate(id);
      else await this.productsApi.deactivate(id);
      this.ui.success(activate ? 'Producto activado' : 'Producto desactivado');
      this.open = false;
      await this.load();
    } catch (e) {
      this.ui.error(errorMessage(e));
    }
  }

  async remove() {
    const id = this.editingId;
    if (!id) return;
    const ok = await this.ui.confirm(
      'Eliminar producto',
      'Se elimina definitivamente. Si ya tiene ventas no se podrá; en ese caso desactívalo.',
      'Eliminar',
      true
    );
    if (!ok) return;
    if (this.offline || id < 0) {
      this.sync.queueDelete(id);
      this.products = this.sync.applyPending();
      this.pendingCount = this.sync.pendingCount;
      this.open = false;
      this.ui.info(id < 0 ? 'Alta pendiente descartada' : 'Baja guardada; se enviará al volver la conexión');
      return;
    }
    try {
      await this.productsApi.delete(id);
      this.open = false;
      this.ui.success('Producto eliminado');
      await this.load();
    } catch (e) {
      if (this.sync.isNetworkError(e)) {
        this.sync.queueDelete(id);
        this.pendingCount = this.sync.pendingCount;
        this.open = false;
      } else {
        this.ui.error(errorMessage(e));
      }
    }
  }

  // ---------- Receta ----------

  addComponent() {
    this.recipe.push({ ref: null, quantity: 1, delivery_mode: 'always', is_estimated: false });
  }

  removeComponent(i: number) {
    this.recipe.splice(i, 1);
  }

  private parse(ref: string | null): { kind: 'i' | 'p'; id: number } | null {
    if (!ref) return null;
    const [k, id] = ref.split(':');
    return { kind: k as 'i' | 'p', id: Number(id) };
  }

  componentUnit(c: RecipeLine): string {
    const r = this.parse(c.ref);
    if (!r) return '—';
    if (r.kind === 'i') return this.inputs.find(i => i.id === r.id)?.unit ?? '';
    const p = this.preparations.find(x => x.id === r.id);
    return p ? ({ portion: 'porción', piece: 'pieza', g: 'g', ml: 'ml' } as any)[p.yield_unit] ?? p.yield_unit : '';
  }

  componentCost(c: RecipeLine): number | null {
    const r = this.parse(c.ref);
    if (!r || !c.quantity) return null;
    const unit = r.kind === 'i' ? this.inputs.find(i => i.id === r.id)?.unit_cost : this.preparations.find(p => p.id === r.id)?.unit_cost;
    return unit === null || unit === undefined ? null : Number(unit) * Number(c.quantity);
  }

  recipeCost(mode: 'local' | 'takeaway'): number | null {
    const parts = this.recipe.filter(c => c.ref && (c.delivery_mode === 'always' || c.delivery_mode === mode));
    if (!parts.length) return null;
    let sum = 0;
    for (const c of parts) {
      const v = this.componentCost(c);
      if (v === null) return null;
      sum += v;
    }
    return sum;
  }

  margin(cost: number | null): number | null {
    const price = Number(this.form.price);
    return cost === null || !(price > 0) ? null : ((price - cost) / price) * 100;
  }

  get hasModes(): boolean {
    return this.recipe.some(c => c.delivery_mode !== 'always');
  }

  async saveRecipe() {
    if (this.saving || !this.editingId || this.editingId < 0) return;
    this.formError = '';
    const items = this.recipe.filter(c => c.ref);
    const refs = items.map(c => c.ref + c.delivery_mode);
    if (new Set(refs).size !== refs.length) return void (this.formError = 'Hay un componente repetido');
    if (items.some(c => !(Number(c.quantity) > 0))) return void (this.formError = 'Indica la cantidad de cada componente');
    const components = items.map(c => {
      const r = this.parse(c.ref)!;
      return {
        input_id: r.kind === 'i' ? r.id : null,
        preparation_id: r.kind === 'p' ? r.id : null,
        quantity: Number(c.quantity),
        is_estimated: c.is_estimated,
        delivery_mode: c.delivery_mode,
      };
    });
    this.saving = true;
    try {
      await this.api.put('products/save-components.php', { product_id: this.editingId, components });
      this.ui.success('Receta guardada; el costo se actualizó');
      this.open = false;
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e, 'No se pudo guardar la receta');
    } finally {
      this.saving = false;
    }
  }
}
