// La app usa Angular sin zone.js: Angular no se entera solo de que terminó una petición
// al servidor o de que Ionic mostró una pantalla. Como hacía el código original con
// `cdr.detectChanges()`, cada pantalla se registra aquí (autoRefresh) y se actualiza:
//  - al terminar cualquier petición al servidor,
//  - al entrar o salir de una pantalla de Ionic,
//  - al escribir, hacer clic o cambiar un campo,
//  - al cambiar la conexión.
import { ApplicationRef, ChangeDetectorRef, DestroyRef, Injectable, inject } from '@angular/core';
import axios from 'axios';

@Injectable({ providedIn: 'root' })
export class RenderService {
  private pending = false;
  private views = new Set<ChangeDetectorRef>();

  constructor(private appRef: ApplicationRef) {
    axios.interceptors.response.use(
      response => {
        this.schedule();
        return response;
      },
      error => {
        this.schedule();
        return Promise.reject(error);
      }
    );
    for (const evt of ['ionViewWillEnter', 'ionViewDidEnter', 'ionViewWillLeave']) {
      document.addEventListener(evt, () => this.schedule(), true);
    }
    // Interacción del usuario: escribir, hacer clic, cambiar un select, enviar un formulario
    for (const evt of ['input', 'change', 'click', 'keyup', 'submit', 'focusout', 'ionChange']) {
      document.addEventListener(evt, () => this.schedule(), true);
    }
    window.addEventListener('online', () => this.schedule());
    window.addEventListener('offline', () => this.schedule());
  }

  attach(cdr: ChangeDetectorRef) {
    this.views.add(cdr);
  }

  detach(cdr: ChangeDetectorRef) {
    this.views.delete(cdr);
  }

  // Actualiza después de que el código que esperaba la respuesta terminó de asignar los datos
  schedule() {
    if (this.pending) return;
    this.pending = true;
    setTimeout(() => {
      this.pending = false;
      this.refreshNow();
    }, 0);
  }

  refreshNow() {
    for (const cdr of [...this.views]) {
      if ((cdr as any).destroyed) {
        this.views.delete(cdr);
        continue;
      }
      try {
        cdr.detectChanges();
      } catch (e: any) {
        // Solo se descarta si la vista ya no existe; cualquier otro error se muestra
        // en la consola y la pantalla se sigue actualizando.
        if (String(e?.message ?? '').includes('NG0911') || /destroyed/i.test(String(e?.message ?? ''))) {
          this.views.delete(cdr);
        } else {
          console.error('[La Obra] Error al dibujar la pantalla:', e);
        }
      }
    }
    try {
      this.appRef.tick();
    } catch (e) {
      console.warn('[render]', e);
    }
  }
}

// Usar como campo de la clase: `private readonly autoRefresh = autoRefresh();`
export function autoRefresh(): RenderService {
  const cdr = inject(ChangeDetectorRef);
  const render = inject(RenderService);
  render.attach(cdr);
  inject(DestroyRef).onDestroy(() => render.detach(cdr));
  return render;
}
