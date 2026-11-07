// Avisos breves (toasts) y confirmaciones. Se dibujan en app.component.
import { Injectable, signal } from '@angular/core';

export interface Toast {
  id: number;
  text: string;
  kind: 'success' | 'error' | 'info';
}

export interface ConfirmRequest {
  title: string;
  message: string;
  confirmText: string;
  danger: boolean;
  resolve: (ok: boolean) => void;
}

@Injectable({ providedIn: 'root' })
export class UiService {
  readonly toasts = signal<Toast[]>([]);
  readonly confirmState = signal<ConfirmRequest | null>(null);
  private seq = 0;

  toast(text: string, kind: Toast['kind'] = 'success', ms = 3200) {
    const id = ++this.seq;
    this.toasts.update(list => [...list.slice(-2), { id, text, kind }]);
    setTimeout(() => this.dismiss(id), ms);
  }

  success(text: string) { this.toast(text, 'success'); }
  error(text: string) { this.toast(text, 'error', 5000); }
  info(text: string) { this.toast(text, 'info'); }

  dismiss(id: number) {
    this.toasts.update(list => list.filter(t => t.id !== id));
  }

  confirm(title: string, message: string, confirmText = 'Confirmar', danger = false): Promise<boolean> {
    return new Promise(resolve => {
      this.confirmState.set({ title, message, confirmText, danger, resolve });
    });
  }

  answer(ok: boolean) {
    const req = this.confirmState();
    this.confirmState.set(null);
    req?.resolve(ok);
  }
}
