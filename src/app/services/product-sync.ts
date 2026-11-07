// Guarda productos localmente y sincroniza con la API las altas, ediciones,
// bajas y fotos hechas sin conexión.

import { Injectable } from '@angular/core';
import { ApiConfigService } from './api-config';
import { ApiService } from './api';
import { SYNC_PREFIX, TOKEN_KEY, USER_KEY } from './storage-keys';

export type SyncOperation = 'create' | 'update' | 'delete';

export interface PendingProductChange {
  op: SyncOperation;
  // En altas sin conexión es un id temporal negativo
  id: number;
  changes: Record<string, any>;
  // Foto pendiente de subir (data URL JPEG comprimido)
  image?: string | null;
  savedAt: string;
}

export interface FailedProductChange extends PendingProductChange {
  error: string;
  failedAt: string;
}

export interface SyncResult {
  sent: number;
  pending: number;
  failed: number;
}

@Injectable({ providedIn: 'root' })
export class ProductSync {

  private syncing = false;
  private readonly prefix = SYNC_PREFIX;

  constructor(private apiConfig: ApiConfigService, private api: ApiService) {}

  // Separar los datos por usuario y servidor
  private key(section: string): string {
    let userId = 'unknown';
    try { userId = String(JSON.parse(localStorage.getItem(USER_KEY) || '{}').id || 'unknown'); } catch {}
    let server = 'sin-conexion';
    try { server = this.apiConfig.getApiUrl(); } catch {}
    return `${this.prefix}:${server}:${userId}:${section}`;
  }

  private read<T>(section: string, fallback: T): T {
    try {
      const value = localStorage.getItem(this.key(section));
      return value ? JSON.parse(value) as T : fallback;
    } catch { return fallback; }
  }

  private write(section: string, value: unknown): void {
    try {
      localStorage.setItem(this.key(section), JSON.stringify(value));
    } catch (e: any) {
      // QuotaExceededError: el almacenamiento local está lleno
      throw new Error('No hay espacio en el almacenamiento local del dispositivo');
    }
  }

  // Guardar la última consulta remota exitosa
  saveProducts(products: any[]): void { this.write('products', products); }
  getProducts(): any[] { return this.read<any[]>('products', []); }
  hasProducts(): boolean { return this.read<any[] | null>('products', null) !== null; }
  saveCategories(categories: any[]): void { this.write('categories', categories); }
  getCategories(): any[] { return this.read<any[]>('categories', []); }

  // Consultar operaciones pendientes (convierte el formato anterior, que solo tenía ediciones)
  getPending(): PendingProductChange[] {
    return this.read<any[]>('pending', []).map(item => ({ op: 'update', ...item }));
  }
  get pendingCount(): number { return this.getPending().length; }

  // Operaciones que el servidor rechazó (validación, permisos, relación con otros datos)
  getFailed(): FailedProductChange[] { return this.read<FailedProductChange[]>('failed', []); }
  clearFailed(): void { this.write('failed', []); }

  private savePending(pending: PendingProductChange[]): void { this.write('pending', pending); }

  // Alta sin conexión: devuelve el id temporal
  queueCreate(changes: Record<string, any>, image?: string | null): number {
    const pending = this.getPending();
    const tempIds = pending.filter(p => p.id < 0).map(p => p.id);
    const tempId = Math.min(-1, ...tempIds.map(id => id - 1));
    pending.push({ op: 'create', id: tempId, changes: { ...changes }, image: image ?? null, savedAt: new Date().toISOString() });
    this.savePending(pending);
    return tempId;
  }

  // Edición sin conexión (se combina con la operación pendiente del mismo producto)
  queueUpdate(id: number, changes: Record<string, any>, image?: string | null): void {
    const pending = this.getPending();
    const existing = pending.find(item => item.id === id && item.op !== 'delete');
    if (existing) {
      existing.changes = { ...existing.changes, ...changes };
      if (image !== undefined) existing.image = image;
      existing.savedAt = new Date().toISOString();
    } else {
      pending.push({ op: 'update', id, changes: { ...changes }, image: image ?? undefined, savedAt: new Date().toISOString() });
    }
    this.savePending(pending);
  }

  // Baja sin conexión
  queueDelete(id: number): void {
    // Si el producto nunca llegó al servidor, basta con descartar su alta
    let pending = this.getPending().filter(item => item.id !== id);
    if (id > 0) {
      pending.push({ op: 'delete', id, changes: {}, savedAt: new Date().toISOString() });
    }
    this.savePending(pending);
  }

  // Mostrar los cambios pendientes sobre la copia local
  applyPending(): any[] {
    const categories = this.getCategories();
    const pending = this.getPending();
    const deleted = new Set(pending.filter(p => p.op === 'delete').map(p => p.id));

    const withCategory = (product: any, changes: Record<string, any>) => {
      const merged = { ...product, ...changes };
      if (changes['category_id'] !== undefined) {
        const cat = categories.find(c => Number(c.id) === Number(changes['category_id']));
        merged.category = { id: Number(changes['category_id']), name: cat?.name ?? '' };
      }
      return merged;
    };

    const list = this.getProducts()
      .filter(product => !deleted.has(Number(product.id)))
      .map(product => {
        const item = pending.find(change => change.op === 'update' && change.id === Number(product.id));
        if (!item) return product;
        const merged = withCategory(product, item.changes);
        if (item.image) merged.image_path = item.image;
        return { ...merged, pending_sync: true };
      });

    for (const item of pending.filter(p => p.op === 'create')) {
      const created = withCategory({ id: item.id, status: 'active', is_available: true }, item.changes);
      if (item.image) created.image_path = item.image;
      list.push({ ...created, pending_sync: true });
    }
    return list;
  }

  // Detectar fallas de conectividad (no confundir con errores 401 o 422)
  isNetworkError(error: any): boolean {
    return !error?.response && (
      error?.code === 'ERR_NETWORK' ||
      error?.code === 'ECONNABORTED' ||
      error?.code === 'ETIMEDOUT' ||
      error?.message === 'Network Error' ||
      !navigator.onLine
    );
  }

  private same(a: PendingProductChange, b: PendingProductChange): boolean {
    return a.id === b.id && a.op === b.op && a.savedAt === b.savedAt;
  }

  // Alta remota; devuelve el id real asignado por la base de datos
  private async createRemote(item: PendingProductChange): Promise<number> {
    const c = item.changes;
    const res = await this.api.post('products/create.php', {
      name: String(c['name'] ?? '').trim(),
      description: String(c['description'] ?? '').trim(),
      category_id: Number(c['category_id']),
      type: c['type'],
      price: Number(c['price']),
    });
    const id = Number(res?.product?.id);
    if (!id) throw new Error('La API no devolvió el id del producto');
    return id;
  }

  // Edición remota y, si hay, subida de la foto
  private async updateRemote(item: PendingProductChange): Promise<void> {
    if (Object.keys(item.changes).length) {
      await this.api.patch('products/update.php', { id: item.id, ...item.changes });
    }
    if (item.image) {
      await this.api.upload('products/upload-image.php', { id: item.id }, item.image, `producto-${item.id}.jpg`);
    }
  }

  // Baja remota
  private async deleteRemote(item: PendingProductChange): Promise<void> {
    try {
      await this.api.delete('products/delete.php', { id: item.id });
    } catch (e: any) {
      // Si ya no existe en el servidor, el objetivo de la baja ya se cumplió
      if (e?.response?.status !== 404) throw e;
    }
  }

  // Enviar operaciones en orden, siempre la primera de la cola.
  // - Falla de red o sesión vencida: se detiene y conserva todo para reintentar.
  // - Rechazo del servidor (422, 403, 409…): mueve la operación a "fallidas" y sigue.
  // - Un alta exitosa se convierte en "edición" con el id real antes de subir la foto,
  //   así un corte de red a la mitad nunca duplica el producto.
  async synchronize(): Promise<SyncResult> {
    if (this.syncing || !navigator.onLine) {
      return { sent: 0, pending: this.pendingCount, failed: this.getFailed().length };
    }
    this.syncing = true;
    let sent = 0;
    try {
      for (let guard = 0; guard < 500; guard++) {
        const item = this.getPending()[0];
        if (!item || !localStorage.getItem(TOKEN_KEY)) break;
        try {
          if (item.op === 'create') {
            const realId = await this.createRemote(item);
            const remaining = this.getPending()
              .map(r => {
                if (r.id !== item.id) return r;
                if (r.op === 'create') {
                  // Si se editó mientras se enviaba, conservar esos cambios como edición
                  const changes = r.savedAt === item.savedAt ? {} : r.changes;
                  return { ...r, op: 'update' as SyncOperation, id: realId, changes };
                }
                return { ...r, id: realId };
              })
              .filter(r => !(r.op === 'update' && r.id === realId && !Object.keys(r.changes).length && !r.image));
            this.savePending(remaining);
          } else {
            if (item.op === 'update') await this.updateRemote(item);
            else await this.deleteRemote(item);
            // Quitar solamente la versión enviada; no borrar ediciones más recientes.
            this.savePending(this.getPending().filter(current => !this.same(current, item)));
          }
          sent++;
        } catch (e: any) {
          const status = e?.response?.status;
          if (this.isNetworkError(e) || status === 401 || !status) break;
          const failed = this.getFailed();
          failed.push({
            ...item,
            image: item.image ? '[foto omitida]' : item.image,
            error: e?.response?.data?.message || e?.message || `Error ${status}`,
            failedAt: new Date().toISOString(),
          });
          this.write('failed', failed);
          this.savePending(this.getPending().filter(current => !this.same(current, item)));
        }
      }
    } finally { this.syncing = false; }
    return { sent, pending: this.pendingCount, failed: this.getFailed().length };
  }
}
