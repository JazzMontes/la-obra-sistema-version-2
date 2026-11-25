// Notas del equipo: qué va a comprar cada quien, pendientes ("pedir el pan") y recordatorios.
// Los avisos los da services/reminders.ts (en la app y como notificación del dispositivo).
import { ChangeDetectionStrategy, Component, OnDestroy, ViewChild } from '@angular/core';
import { ErrandsComponent } from './errands.component';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { Auth } from '../../services/auth';
import { REMINDERS_EVENT, RemindersService } from '../../services/reminders';
import { autoRefresh } from '../../services/render';
import { Memo } from '../../shared/memo';
import { parseServerDate } from '../../shared/format.pipes';

type Preset = '' | '1h' | 'today18' | 'tomorrow8' | 'custom';

interface NoteForm {
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

  // Encargos de compra (dinero entregado y su cambio) o notas y pendientes
  view: 'errands' | 'notes' = 'errands';
  @ViewChild(ErrandsComponent) errandsPanel?: ErrandsComponent;
  status: 'pending' | 'done' = 'pending';
  notes: any[] = [];
  people: { id: number; name: string }[] = [];
  counts: { pending: number; mine: number } = { pending: 0, mine: 0 };
  me = 0;
  loading = true;
  onlyMine = false;
  busy = new Set<number>();

  draft: NoteForm = this.blank();
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
    if (/[?&]tab=errands/.test(location.hash || '')) this.view = 'errands';
    else if (/[?&]tab=notes/.test(location.hash || '')) this.view = 'notes';
    this.visible = true;
    void this.errandsPanel?.load();
    void this.reminders.readPermission();
    void this.load();
  }

  ionViewWillLeave() {
    this.visible = false;
  }

  private blank(): NoteForm {
    return { id: null, title: '', details: '', assigned_to: null, preset: '', remind_at: '', repeat: 'none' };
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

  private payload(f: NoteForm) {
    return {
      id: f.id || null,
      title: f.title.trim(),
      details: f.details?.trim() || null,
      assigned_to: f.assigned_to,
      remind_at: f.preset && f.remind_at ? f.remind_at.replace('T', ' ') : null,
      repeat: f.preset ? f.repeat : 'none',
    };
  }

  private validate(f: NoteForm): string {
    if (!f.title.trim()) return 'Escribe qué hay que comprar o hacer';
    if (f.preset === 'custom' && !f.remind_at) return 'Elige la fecha y hora del recordatorio';
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
    this.formError = '';
    this.open = true;
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
    };
    this.formError = '';
    this.open = true;
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
