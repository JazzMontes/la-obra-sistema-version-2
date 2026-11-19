// Ícono de conexión en el encabezado de cada pantalla. Cambia según el sensor de red
// (Wi-Fi, datos móviles, conexión lenta o sin conexión) y al tocarlo abre el panel
// "Estado de conexión" (está en app.component.html).
import { ChangeDetectionStrategy, Component } from '@angular/core';
import { NetworkService } from '../services/network';
import { autoRefresh } from '../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-network-button',
  template: `
    <button
      type="button"
      class="net-btn"
      [class.net-good]="net.quality === 'good'"
      [class.net-weak]="net.quality === 'weak'"
      [class.net-offline]="net.quality === 'offline'"
      [attr.aria-label]="'Estado de conexión: ' + net.title"
      [attr.title]="net.title"
      (click)="net.open()"
    >
      <app-icon [name]="net.icon"></app-icon>
      <span class="dot"></span>
    </button>
  `,
  styles: [`
    :host { display: inline-flex; margin: 0 4px; }
    .net-btn { position: relative; width: 38px; height: 38px; border-radius: 10px; border: 1px solid transparent;
      background: transparent; color: var(--text); display: grid; place-items: center; cursor: pointer; padding: 0;
      -webkit-tap-highlight-color: transparent; transition: background .12s; }
    .net-btn:hover { background: var(--surface-3); }
    .net-btn app-icon { width: 21px; height: 21px; }
    .dot { position: absolute; right: 6px; bottom: 6px; width: 8px; height: 8px; border-radius: 50%;
      border: 2px solid var(--surface); background: var(--success); }
    .net-weak { color: var(--warning); }
    .net-weak .dot { background: var(--warning); }
    .net-offline { color: var(--danger); background: var(--danger-soft); }
    .net-offline .dot { background: var(--danger); animation: pulse 1.4s ease-in-out infinite; }
    @keyframes pulse { 50% { transform: scale(1.35); } }
  `],
  standalone: false,
})
export class NetworkButtonComponent {
  private readonly refresher = autoRefresh();
  constructor(public net: NetworkService) {}
}
