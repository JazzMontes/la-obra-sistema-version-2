// Selector con buscador: escribe parte del nombre y elige de la lista (sin acentos ni mayúsculas).
// Sustituye a los <select> largos de insumos y preparaciones. Opcionalmente ofrece
// "+ Registrar …" para crear lo que no existe (emite el texto que se escribió).
//
// <app-search-select [items]="inputs" [(value)]="line.input_id" placeholder="Buscar insumo"
//                    createLabel="Registrar insumo" (create)="newInput($event)"></app-search-select>
import { ChangeDetectionStrategy, Component, ElementRef, EventEmitter, Input, OnChanges, Output, ViewChild } from '@angular/core';
import { RenderService, autoRefresh } from '../services/render';

export interface SearchOption {
  id: any;
  name: string;
  sub?: string;    // texto secundario (unidad, existencia…)
  group?: string;  // encabezado de grupo (Preparaciones, Insumos…)
}

let uid = 0;

export function normalize(s: any): string {
  return String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-search-select',
  template: `
    <div class="ss" [class.open]="open" [class.up]="up">
      <span class="ss-icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" width="16" height="16"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>
      </span>
      <input
        #box
        class="input ss-input"
        type="text"
        autocomplete="off"
        [attr.id]="inputId"
        [attr.aria-label]="ariaLabel || placeholder"
        [attr.aria-expanded]="open"
        [attr.aria-controls]="listId"
        role="combobox"
        aria-autocomplete="list"
        [placeholder]="open && selected ? selected.name : placeholder"
        [value]="open ? query : selected?.name || ''"
        [disabled]="disabled"
        (focus)="onFocus()"
        (input)="onInput($event)"
        (keydown)="onKey($event)"
        (blur)="onBlur()"
      />
      <span class="ss-sub" *ngIf="!open && selected?.sub">{{ selected.sub }}</span>
      <button type="button" class="ss-caret" tabindex="-1" (mousedown)="$event.preventDefault()" (click)="toggle()" [disabled]="disabled" aria-label="Ver lista">
        <svg viewBox="0 0 24 24" width="14" height="14"><path d="m6 9 6 6 6-6"/></svg>
      </button>

      <div class="ss-list" *ngIf="open" [attr.id]="listId" role="listbox" (mousedown)="$event.preventDefault()">
        <ng-container *ngFor="let o of filtered; let i = index">
          <div class="ss-group" *ngIf="o.group && (i === 0 || filtered[i - 1].group !== o.group)">{{ o.group }}</div>
          <button
            type="button"
            class="ss-opt"
            role="option"
            [class.active]="i === active"
            [class.selected]="o.id === value"
            [attr.aria-selected]="o.id === value"
            (click)="pick(o)"
            (mouseenter)="active = i"
          >
            <span class="ss-name">{{ o.name }}</span>
            <span class="ss-opt-sub" *ngIf="o.sub">{{ o.sub }}</span>
          </button>
        </ng-container>
        <div class="ss-empty" *ngIf="!filtered.length">{{ query ? 'Sin resultados para "' + query + '"' : 'No hay opciones' }}</div>
        <button type="button" class="ss-opt ss-create" *ngIf="createLabel" [class.active]="active === filtered.length" (click)="doCreate()" (mouseenter)="active = filtered.length">
          + {{ createLabel }}{{ query ? ' "' + query + '"' : '' }}
        </button>
      </div>
    </div>
  `,
  styles: [`
    :host { display: block; min-width: 0; }
    .ss { position: relative; }
    .ss-icon { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); color: var(--faint); display: flex; pointer-events: none; }
    .ss-icon svg, .ss-caret svg { fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
    .ss-input { width: 100%; padding-left: 32px !important; padding-right: 34px !important; text-overflow: ellipsis; }
    .ss-sub { position: absolute; right: 34px; top: 50%; transform: translateY(-50%); font-size: 12px; color: var(--muted); pointer-events: none; background: var(--surface); padding-left: 4px; }
    .ss-caret { position: absolute; right: 4px; top: 50%; transform: translateY(-50%); width: 28px; height: 28px; border: 0; background: none; color: var(--muted); cursor: pointer; display: grid; place-items: center; padding: 0; }
    .ss.open .ss-caret svg { transform: rotate(180deg); }
    .ss.up .ss-list { top: auto; bottom: calc(100% + 4px); }
    .ss-list {
      position: absolute; left: 0; right: 0; top: calc(100% + 4px); z-index: 60; max-height: 260px; overflow-y: auto;
      background: var(--surface); border: 1px solid var(--border-strong); border-radius: var(--radius-sm, 8px);
      box-shadow: var(--shadow-lg); padding: 4px; min-width: 220px;
    }
    .ss-group { padding: 8px 10px 4px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; color: var(--faint); }
    .ss-opt {
      display: flex; align-items: center; gap: 8px; width: 100%; padding: 9px 10px; border: 0; border-radius: 6px;
      background: none; text-align: left; font: inherit; font-size: 14px; color: var(--text); cursor: pointer;
    }
    .ss-opt.active { background: var(--surface-2, #f3f2ee); }
    .ss-opt.selected .ss-name { font-weight: 700; }
    .ss-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .ss-opt-sub { font-size: 12px; color: var(--muted); white-space: nowrap; }
    .ss-empty { padding: 10px; font-size: 13px; color: var(--muted); }
    .ss-create { color: var(--info, #2457c5); font-weight: 600; border-top: 1px solid var(--border); border-radius: 0 0 6px 6px; margin-top: 2px; }
  `],
  standalone: false,
})
export class SearchSelectComponent implements OnChanges {
  private readonly refresher = autoRefresh();

  @Input() items: SearchOption[] = [];
  @Input() value: any = null;
  @Output() valueChange = new EventEmitter<any>();
  @Input() placeholder = 'Buscar…';
  @Input() ariaLabel = '';
  @Input() inputId: string | null = null;
  @Input() disabled = false;
  // Texto del botón para crear algo nuevo con lo que se escribió (vacío = sin botón)
  @Input() createLabel = '';
  @Output() create = new EventEmitter<string>();

  @ViewChild('box') box?: ElementRef<HTMLInputElement>;

  readonly listId = `ss-list-${++uid}`;
  open = false;
  up = false;
  query = '';
  active = 0;
  filtered: SearchOption[] = [];
  selected: SearchOption | null = null;

  constructor(private render: RenderService) {}

  ngOnChanges() {
    this.selected = this.items?.find(o => o.id === this.value) ?? null;
    if (this.open) this.filter();
  }

  private filter() {
    const words = normalize(this.query).split(/\s+/).filter(Boolean);
    const list = this.items ?? [];
    this.filtered = !words.length
      ? list
      : list
          .filter(o => {
            const hay = normalize(o.name + ' ' + (o.sub ?? ''));
            return words.every(w => hay.includes(w));
          })
          // Primero los que empiezan con lo escrito
          .sort((a, b) => Number(!normalize(a.name).startsWith(words[0])) - Number(!normalize(b.name).startsWith(words[0])));
    const sel = this.filtered.findIndex(o => o.id === this.value);
    this.active = words.length ? 0 : Math.max(0, sel);
  }

  onFocus() {
    if (this.open) return;
    this.query = '';
    this.open = true;
    this.up = this.shouldOpenUp();
    this.filter();
    this.scrollToActive();
  }

  onInput(e: Event) {
    this.query = (e.target as HTMLInputElement).value;
    this.open = true;
    this.filter();
  }

  toggle() {
    if (this.open) {
      this.close();
      this.box?.nativeElement.blur();
    } else {
      this.box?.nativeElement.focus();
    }
  }

  onBlur() {
    // Se espera un momento por si el clic fue en una opción
    setTimeout(() => {
      this.close();
      this.render.schedule();
    }, 120);
  }

  private close() {
    this.open = false;
    this.query = '';
  }

  onKey(e: KeyboardEvent) {
    const max = this.filtered.length + (this.createLabel ? 1 : 0) - 1;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (!this.open) this.onFocus();
      else this.active = Math.min(max, this.active + 1);
      this.scrollToActive();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      this.active = Math.max(0, this.active - 1);
      this.scrollToActive();
    } else if (e.key === 'Enter') {
      if (!this.open) return;
      e.preventDefault();
      if (this.active < this.filtered.length) this.pick(this.filtered[this.active]);
      else if (this.createLabel) this.doCreate();
    } else if (e.key === 'Escape') {
      if (this.open) {
        e.preventDefault();
        e.stopPropagation();
        this.close();
      }
    } else if (e.key === 'Tab' && this.open && this.query && this.filtered.length) {
      // Tab elige la primera coincidencia, como en un buscador
      this.pick(this.filtered[this.active] ?? this.filtered[0]);
    }
  }

  pick(o: SearchOption) {
    this.value = o.id;
    this.selected = o;
    this.valueChange.emit(o.id);
    this.close();
    this.box?.nativeElement.blur();
  }

  doCreate() {
    const text = this.query.trim();
    this.close();
    this.box?.nativeElement.blur();
    this.create.emit(text);
  }

  // Si abajo no cabe la lista (final de una ventana), se abre hacia arriba
  private shouldOpenUp(): boolean {
    const el = this.box?.nativeElement;
    if (!el) return false;
    const r = el.getBoundingClientRect();
    const scroller = el.closest('.modal-body, ion-content') as HTMLElement | null;
    const limit = scroller && scroller.tagName !== 'ION-CONTENT' ? scroller.getBoundingClientRect() : { top: 0, bottom: window.innerHeight };
    const below = limit.bottom - r.bottom;
    const above = r.top - limit.top;
    return below < 270 && above > below;
  }

  private scrollToActive() {
    setTimeout(() => {
      const el = document.getElementById(this.listId)?.querySelectorAll('.ss-opt')[this.active] as HTMLElement | undefined;
      el?.scrollIntoView({ block: 'nearest' });
    }, 0);
  }
}
