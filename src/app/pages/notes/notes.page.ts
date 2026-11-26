// Notas del equipo: qué va a comprar cada quien, pendientes ("pedir el pan") y recordatorios.
// Los avisos los da services/reminders.ts (en la app y como notificación del dispositivo).
import { ChangeDetectionStrategy, Component, OnDestroy } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { REMINDERS_EVENT, RemindersService } from '../../services/reminders';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';
import { parseServerDate } from '../../shared/format.pipes';
import { SearchOption } from '../../shared/search-select.component';

type Preset = '' | '1h' | 'today18' | 'tomorrow8' | 'custom';

// Renglón de la lista de compra. price = aproximado de ese renglón; se calcula con el costo del insumo
// (cantidad × lo que trae la unidad × costo por unidad principal) hasta que lo cambies a mano.
interface ShopItem {
  input_id: number | null;
  name: string;
  qty: number | null;
  unit: string;
  price: number | null;
  manual: boolean;
}

interface NoteForm {
  items?: ShopItem[];
  id?: number | null;
  title: string;
  details: string;
  assigned_to: number | null;
  preset: Preset;
  remind_at: string;   // como lo da <input type="datetime-local">: 'YYYY-MM-DDTHH:MM'
  repeat: 'none' | 'daily' | 'weekly';
  created_by?: number | null;
}

interface Group { id: number | null; name: string; notes: any[]; }

const pad = (n: number) => String(n).padStart(2, '0');

function toInput(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-notes',
  templateUrl: 'notes.page.html',
  styleUrls: ['notes.page.scss'],
  standalone: false,
})
export class NotesPage implements OnDestroy {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly memo = new Memo();
  private readonly refresher = autoRefresh();

  status: 'pending' | 'done' = 'pending';
  notes: any[] = [];
  people: { id: number; name: string }[] = [];
  counts: { pending: number; mine: number } = { pending: 0, mine: 0 };
  me = 0;
  loading = true;
  onlyMine = false;
  busy = new Set<number>();

  draft: NoteForm = this.blank();
  private originalAssignee: number | null = null;

  // Insumos con su costo (para la lista de compra). Se cargan al abrir una nota.
  catalog: any[] = [];
  pickerKey = 0;
  open = false;
  form: NoteForm = this.blank();
  saving = false;
  formError = '';

  private visible = false;
  // Cada minuto el servicio de recordatorios pregunta al servidor: se aprovecha para refrescar
  private onReminders = () => {
    if (this.visible && !this.open && !this.saving) void this.load(true);
  };

  constructor(private api: ApiService, private ui: UiService, private auth: Auth, public reminders: RemindersService) {
    window.addEventListener(REMINDERS_EVENT, this.onReminders);
  }

  ngOnDestroy() {
    window.removeEventListener(REMINDERS_EVENT, this.onReminders);
  }

  get isAdmin(): boolean {
    return this.auth.getStoredUser()?.role === 'admin';
  }

  ionViewWillEnter() {
    this.visible = true;
    void this.reminders.readPermission();
    void this.load();
  }

  ionViewWillLeave() {
    this.visible = false;
  }

  private blank(): NoteForm {
    return { id: null, title: '', details: '', assigned_to: null, preset: '', remind_at: '', repeat: 'none', items: [] };
  }

  async load(silent = false) {
    if (!silent) this.loading = true;
    try {
      const r: any = await this.api.get('notes/index.php', { status: this.status });
      this.notes = r.notes ?? [];
      this.people = r.people ?? [];
      this.counts = r.counts ?? this.counts;
      this.me = Number(r.me) || Number(this.auth.getStoredUser()?.id) || 0;
    } catch (e) {
      if (!silent) this.ui.error(errorMessage(e, 'No se pudieron cargar las notas'));
    } finally {
      this.loading = false;
    }
  }

  setStatus(s: 'pending' | 'done') {
    if (this.status === s) return;
    this.status = s;
    this.notes = [];
    void this.load();
  }

  // Pendientes agrupados por persona: primero yo, luego los demás y al final "cualquiera"
  get groups(): Group[] {
    return this.memo.get('groups', [this.notes, this.onlyMine, this.people, this.me], () => {
      const map = new Map<number | null, Group>();
      for (const n of this.notes) {
        const id = n.assigned_to ?? null;
        if (this.onlyMine && id !== this.me) continue;
        if (!map.has(id)) {
          const name = id === null ? 'Cualquiera del equipo' : id === this.me ? 'Para mí' : n.assigned_name || 'Sin nombre';
          map.set(id, { id, name, notes: [] });
        }
        map.get(id)!.notes.push(n);
      }
      return [...map.values()].sort((a, b) => this.rank(a) - this.rank(b) || a.name.localeCompare(b.name, 'es'));
    });
  }

  private rank(g: Group): number {
    return g.id === this.me ? 0 : g.id === null ? 2 : 1;
  }

  // "Hoy 18:00", "Mañana 08:00", "Ayer 09:30", "5 dic 10:00"
  when(value: string): string {
    const d = parseServerDate(value);
    if (!d) return '';
    const now = new Date();
    const time = new Intl.DateTimeFormat('es-MX', { hour: '2-digit', minute: '2-digit' }).format(d);
    const tomorrow = new Date(now); tomorrow.setDate(now.getDate() + 1);
    const yesterday = new Date(now); yesterday.setDate(now.getDate() - 1);
    if (sameDay(d, now)) return `Hoy ${time}`;
    if (sameDay(d, tomorrow)) return `Mañana ${time}`;
    if (sameDay(d, yesterday)) return `Ayer ${time}`;
    return new Intl.DateTimeFormat('es-MX', { day: 'numeric', month: 'short' }).format(d) + ' ' + time;
  }

  get showToday18(): boolean {
    return new Date().getHours() < 18;
  }

  setPreset(f: NoteForm, p: Preset) {
    f.preset = p;
    const d = new Date();
    d.setSeconds(0, 0);
    if (p === '') {
      f.remind_at = '';
      f.repeat = 'none';
      return;
    }
    if (p === '1h') d.setMinutes(d.getMinutes() + 60);
    else if (p === 'today18') d.setHours(18, 0);
    else if (p === 'tomorrow8') { d.setDate(d.getDate() + 1); d.setHours(8, 0); }
    else if (p === 'custom' && f.remind_at) return;
    else { d.setMinutes(d.getMinutes() + 60); d.setMinutes(0); }
    f.remind_at = toInput(d);
  }

  canEdit(n: any): boolean {
    return this.isAdmin || n.created_by === this.me || n.assigned_to === this.me || n.assigned_to === null;
  }

  canDelete(n: any): boolean {
    return this.isAdmin || !n.created_by || n.created_by === this.me;
  }

  // La nota solo lleva a quién le toca y la lista. Al guardarla con una persona (o al cambiarla),
  // el recordatorio le llega a esa persona en ese momento.
  private payload(f: NoteForm) {
    const changedPerson = !f.id || f.assigned_to !== this.originalAssignee;
    const now = new Date();
    now.setSeconds(0, 0);
    return {
      id: f.id || null,
      title: '',
      details: null,
      assigned_to: f.assigned_to,
      remind_at: f.assigned_to ? (changedPerson ? toInput(now).replace('T', ' ') : f.remind_at ? f.remind_at.replace('T', ' ') : null) : null,
      repeat: 'none',
      items: (f.items ?? [])
        .filter(i => String(i.name || '').trim())
        .map(i => ({ input_id: i.input_id, name: i.name.trim(), qty: i.qty, unit: i.unit, price: i.price === null || (i.price as any) === '' ? null : Number(i.price) })),
    };
  }

  private validate(f: NoteForm): string {
    if (!(f.items ?? []).some(i => String(i.name || '').trim())) return 'Agrega al menos una cosa a la lista';
    return '';
  }

  async quickAdd() {
    if (this.saving) return;
    const err = this.validate(this.draft);
    if (err) return this.ui.error(err);
    this.saving = true;
    try {
      const r: any = await this.api.post('notes/save.php', this.payload(this.draft));
      this.ui.success(r.message || 'Nota agregada');
      // Se conserva a quién se le asignó para anotar varias cosas seguidas
      this.draft = { ...this.blank(), assigned_to: this.draft.assigned_to };
      await this.load(true);
      void this.reminders.check();
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo guardar la nota'));
    } finally {
      this.saving = false;
    }
  }

  openNew() {
    this.form = this.blank();
    this.originalAssignee = null;
    this.formError = '';
    this.open = true;
    void this.loadCatalog();
  }

  openEdit(n: any) {
    const at = parseServerDate(n.remind_at);
    this.form = {
      id: n.id,
      title: n.title,
      details: n.details ?? '',
      assigned_to: n.assigned_to ?? null,
      preset: at ? 'custom' : '',
      remind_at: at ? toInput(at) : '',
      repeat: n.repeat ?? 'none',
      created_by: n.created_by,
      items: (n.items ?? []).map((i: any) => ({
        input_id: i.input_id ?? null, name: i.name, qty: i.qty ?? null, unit: i.unit ?? '', price: i.price ?? null, manual: true,
      })),
    };
    this.originalAssignee = n.assigned_to ?? null;
    this.formError = '';
    this.open = true;
    void this.loadCatalog();
  }

  // ---------- Lista de compra (solo nota: no registra compras ni dinero) ----------
  async loadCatalog() {
    if (this.catalog.length) return;
    try {
      this.catalog = (await this.api.get('notes/inputs')).inputs ?? [];
    } catch {
      this.catalog = [];
    }
  }

  get catalogOptions(): SearchOption[] {
    return this.memo.get('catalog', [this.catalog], () =>
      this.catalog.map(i => ({ id: Number(i.id), name: i.name, sub: i.unit_cost !== null ? `$${Number(i.unit_cost).toFixed(2)} / ${i.unit}` : 'sin costo' })));
  }

  private inputOf(it: ShopItem): any {
    return it.input_id ? this.catalog.find(c => Number(c.id) === Number(it.input_id)) : null;
  }

  // Unidades del insumo: las de compra primero, luego la principal y las de receta
  unitsFor(it: ShopItem): { name: string; factor: number }[] {
    const inp = this.inputOf(it);
    return this.memo.get('u:' + it.input_id + ':' + it.unit, [inp], () => {
      if (!inp) return [];
      const all = (inp.units ?? []).map((u: any) => ({ name: String(u.name), factor: Number(u.factor) || Number(u.base_amount) / (Number(u.unit_amount) || 1), buy: u.use_in !== 'recipe' }));
      const list = [...all.filter((u: any) => u.buy), { name: String(inp.unit), factor: 1 }, ...all.filter((u: any) => !u.buy)];
      if (it.unit && !list.some(u => u.name === it.unit)) list.push({ name: it.unit, factor: 1 });
      return list;
    });
  }

  // Al agregar un insumo se llena con su última compra: unidad, cantidad y lo que costó.
  // Si nunca se ha comprado, con su primera unidad de compra y el costo que tiene en Insumos.
  addInput(id: any) {
    const inp = this.catalog.find(c => Number(c.id) === Number(id));
    if (!inp || !this.form.items) return;
    const lp = inp.last_purchase;
    const probe: ShopItem = { input_id: Number(inp.id), name: inp.name, qty: 1, unit: '', price: null, manual: false };
    const units = this.unitsFor(probe);
    const fromLast = lp ? units.find(u => u.name.toLowerCase() === String(lp.buy_unit || inp.unit).toLowerCase()) : undefined;
    const it: ShopItem = fromLast
      ? { ...probe, unit: fromLast.name, qty: Number(lp.quantity) || 1 }
      : { ...probe, unit: units[0]?.name ?? inp.unit };
    this.recalc(it);
    this.form.items = [...this.form.items, it];
    this.pickerKey++;
  }

  // "Última compra: 5 paquete a $100 c/u (25 nov)"
  lastInfo(it: ShopItem): any {
    return this.inputOf(it)?.last_purchase ?? null;
  }

  // Algo que no está en Insumos (servilletas, una herramienta…): el precio se escribe a mano
  addFree(name: string) {
    if (!this.form.items) return;
    this.form.items = [...this.form.items, { input_id: null, name: String(name || '').trim(), qty: 1, unit: 'pza', price: null, manual: true }];
    this.pickerKey++;
  }

  removeItem(i: number) {
    this.form.items = (this.form.items ?? []).filter((_, k) => k !== i);
  }

  // Precio aproximado: si es la misma unidad de la última compra, con el precio de esa compra;
  // si no, con el costo del insumo (cantidad × lo que trae la unidad × costo por unidad principal).
  recalc(it: ShopItem) {
    if (it.manual) return;
    const inp = this.inputOf(it);
    const u = this.unitsFor(it).find(x => x.name === it.unit);
    if (!inp || !u || !(Number(it.qty) > 0)) {
      it.price = null;
      return;
    }
    const lp = inp.last_purchase;
    const sameAsLast = lp && String(lp.buy_unit || inp.unit).toLowerCase() === it.unit.toLowerCase()
      && Math.abs(Number(lp.content_per_package || 1) - u.factor) < 0.0005;
    if (sameAsLast && lp.unit_cost !== null && lp.unit_cost !== undefined) {
      it.price = Math.round(Number(it.qty) * Number(lp.unit_cost) * 100) / 100;
    } else if (inp.unit_cost !== null && inp.unit_cost !== undefined) {
      it.price = Math.round(Number(it.qty) * u.factor * Number(inp.unit_cost) * 100) / 100;
    } else {
      it.price = null;
    }
  }

  priceTyped(it: ShopItem) {
    it.manual = true;
  }

  usePrice(it: ShopItem) {
    it.manual = false;
    this.recalc(it);
  }

  hasCost(it: ShopItem): boolean {
    const inp = this.inputOf(it);
    return !!inp && ((inp.unit_cost !== null && inp.unit_cost !== undefined) || !!inp.last_purchase);
  }

  get formTotal(): number {
    return Math.round((this.form.items ?? []).reduce((s, i) => s + (Number(i.price) || 0), 0) * 100) / 100;
  }

  // "2 paquete · 1.5 kg"
  itemLabel(i: any): string {
    const q = i.qty === null || i.qty === undefined ? '' : String(+Number(i.qty).toFixed(3));
    return [q, i.unit].filter(Boolean).join(' ');
  }

  async save() {
    if (this.saving) return;
    this.formError = this.validate(this.form);
    if (this.formError) return;
    this.saving = true;
    try {
      const r: any = await this.api.post('notes/save.php', this.payload(this.form));
      this.ui.success(r.message || 'Nota guardada');
      this.open = false;
      if (this.status !== 'pending') this.status = 'pending';
      await this.load(true);
      void this.reminders.check();
    } catch (e) {
      this.formError = errorMessage(e, 'No se pudo guardar la nota');
    } finally {
      this.saving = false;
    }
  }

  // Pendiente → hecha (las que se repiten se recorren a la siguiente vez) · hecha → pendiente
  async toggle(n: any) {
    if (this.busy.has(n.id)) return;
    this.busy.add(n.id);
    try {
      const r: any = await this.api.patch('notes/done.php', { id: n.id, done: this.status === 'pending' });
      this.ui.success(r.message || 'Listo');
      await this.load(true);
      void this.reminders.check();
    } catch (e) {
      this.ui.error(errorMessage(e));
    } finally {
      this.busy.delete(n.id);
    }
  }

  async remove(n: any) {
    const ok = await this.ui.confirm('Borrar nota', `¿Borrar "${n.title}"?`, 'Borrar', true);
    if (!ok) return;
    try {
      await this.api.delete('notes/delete.php', { id: n.id });
      this.ui.success('Nota borrada');
      this.open = false;
      await this.load(true);
      void this.reminders.check();
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudo borrar la nota'));
    }
  }
}
