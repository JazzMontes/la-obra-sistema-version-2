// Encargos de compra: quién va, a dónde, qué compra (con lo que calculamos que cuesta),
// cuánto se le da y de qué cuenta. Al regresar se pone lo que gastó de verdad:
// la app dice si te devuelve cambio o si hay que reponerle, y lo gastado queda como gasto.
import { ChangeDetectionStrategy, Component, OnInit } from '@angular/core';
import { ApiService, errorMessage } from '../../services/api';
import { UiService } from '../../services/ui';
import { autoRefresh } from '../../services/render';

interface Item { name: string; qty: string; estimate: number | null; real?: number | null; }

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-errands',
  templateUrl: 'errands.component.html',
  styleUrls: ['errands.component.scss'],
  standalone: false,
})
export class ErrandsComponent implements OnInit {
  private readonly refresher = autoRefresh();

  status: 'open' | 'closed' = 'open';
  loading = true;
  errands: any[] = [];
  accounts: any[] = [];
  cashId: number | null = null;

  // Nuevo / editar
  open = false;
  form: any = this.blank();
  // Cerrar
  closing: any = null;
  close: any = {};

  saving = false;
  formError = '';

  readonly quickGive = [100, 200, 500, 1000];

  constructor(private api: ApiService, private ui: UiService) {}

  ngOnInit() {
    void this.load();
  }

  async load() {
    this.loading = true;
    try {
      const r = await this.api.get('errands/index', { status: this.status });
      this.errands = r.errands;
      this.accounts = r.accounts.filter((a: any) => !a.is_reserve);
      this.cashId = r.cash_account_id;
    } catch (e) {
      this.ui.error(errorMessage(e, 'No se pudieron cargar los encargos'));
    } finally {
      this.loading = false;
    }
  }

  setStatus(s: 'open' | 'closed') {
    this.status = s;
    void this.load();
  }

  private blank(): any {
    return { id: null, person: '', place: '', items: [this.emptyItem(), this.emptyItem()], given: null, account_id: null, note: '' };
  }

  private emptyItem(): Item {
    return { name: '', qty: '', estimate: null };
  }

  // ---------- Formulario ----------
  openNew() {
    this.form = this.blank();
    this.form.account_id = this.cashId;
    this.formError = '';
    this.open = true;
  }

  openEdit(e: any) {
    if (e.status !== 'open') return;
    this.form = {
      id: e.id,
      person: e.person,
      place: e.place || '',
      items: (e.items || []).map((i: any) => ({ name: i.name, qty: i.qty || '', estimate: i.estimate ?? null })),
      given: e.given || null,
      account_id: e.account_id,
      note: e.note || '',
    };
    this.form.items.push(this.emptyItem());
    this.formError = '';
    this.open = true;
  }

  addItem() {
    this.form.items = [...this.form.items, this.emptyItem()];
  }

  removeItem(i: number) {
    this.form.items = this.form.items.filter((_: Item, k: number) => k !== i);
    if (!this.form.items.length) this.addItem();
  }

  // Al escribir en el último renglón aparece otro vacío
  touchItem(i: number) {
    if (i === this.form.items.length - 1 && String(this.form.items[i].name || '').trim()) this.addItem();
  }

  get estimate(): number {
    return (this.form.items as Item[]).reduce((s, i) => s + (String(i.name || '').trim() ? Number(i.estimate) || 0 : 0), 0);
  }

  // Lo que se entrega sugerido: el estimado redondeado hacia arriba a $50
  get suggestedGive(): number {
    return this.estimate > 0 ? Math.ceil(this.estimate / 50) * 50 : 0;
  }

  async save() {
    if (this.saving) return;
    const f = this.form;
    this.formError = '';
    const items = (f.items as Item[]).filter(i => String(i.name || '').trim());
    if (!String(f.person || '').trim()) return void (this.formError = '¿Quién va a comprar?');
    if (!items.length) return void (this.formError = 'Agrega al menos una cosa a la lista');
    this.saving = true;
    try {
      await this.api.post('errands/save', {
        id: f.id,
        person: f.person.trim(),
        place: String(f.place || '').trim(),
        items: items.map(i => ({ name: i.name.trim(), qty: String(i.qty || '').trim(), estimate: i.estimate === null || (i.estimate as any) === '' ? null : Number(i.estimate) })),
        given: Number(f.given) > 0 ? Math.round(Number(f.given) * 100) / 100 : 0,
        account_id: f.account_id,
        note: String(f.note || '').trim(),
      });
      this.open = false;
      this.ui.success('Encargo guardado');
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e);
    } finally {
      this.saving = false;
    }
  }

  async cancel(e: any) {
    const from = e.account_name || this.accounts.find(a => a.id === e.account_id)?.name || 'su cuenta';
    const ok = await this.ui.confirm('Cancelar encargo', `Al final no se hizo la compra de ${e.person}. El dinero entregado regresa a ${from}.`, 'Cancelar encargo', true);
    if (!ok) return;
    try {
      await this.api.post('errands/cancel', { id: e.id });
      this.open = false;
      this.ui.success('Encargo cancelado');
      await this.load();
    } catch (err) {
      this.ui.error(errorMessage(err));
    }
  }

  // ---------- Cerrar (regresó de comprar) ----------
  openClose(e: any) {
    this.closing = e;
    this.close = {
      items: (e.items || []).map((i: any) => ({ ...i, real: i.estimate ?? null })),
      spent: null,
      useItems: true,
    };
    this.formError = '';
  }

  get itemsReal(): number {
    return (this.close.items || []).reduce((s: number, i: any) => s + (Number(i.real) || 0), 0);
  }

  get spent(): number {
    return this.close.useItems ? this.itemsReal : Number(this.close.spent) || 0;
  }

  get change(): number {
    return Math.round((Number(this.closing?.given || 0) - this.spent) * 100) / 100;
  }

  async saveClose() {
    if (this.saving) return;
    this.formError = '';
    if (!(this.spent >= 0)) return void (this.formError = 'Escribe cuánto gastó');
    this.saving = true;
    try {
      const r = await this.api.post('errands/close', {
        id: this.closing.id,
        spent: Math.round(this.spent * 100) / 100,
        items: this.close.items.map((i: any) => ({ ...i, real: i.real === '' ? null : i.real })),
      });
      this.closing = null;
      this.ui.success(r.message);
      await this.load();
    } catch (e) {
      this.formError = errorMessage(e);
    } finally {
      this.saving = false;
    }
  }

  async reopen(e: any) {
    const ok = await this.ui.confirm('Abrir de nuevo', 'Se quita el gasto que se registró al cerrarlo para que puedas corregirlo.', 'Abrir de nuevo');
    if (!ok) return;
    try {
      await this.api.post('errands/reopen', { id: e.id });
      this.ui.success('Encargo abierto de nuevo');
      this.status = 'open';
      await this.load();
    } catch (err) {
      this.ui.error(errorMessage(err));
    }
  }

  abs(n: number): number {
    return Math.abs(n);
  }
}
