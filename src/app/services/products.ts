// Envía las solicitudes de productos a la API (versión 2: Supabase mediante ApiService).

import { Injectable } from '@angular/core';
import { ApiService } from './api';

@Injectable({ providedIn: 'root' })
export class Products {

  // Dependencias e inicio
  constructor(private api: ApiService) {}

  // Consultar registros
  async getAll() {
    return this.api.get('products/index.php');
  }

  // Consultar registro por ID
  async getById(id: number) {
    return this.api.get('products/show.php', { id });
  }

  // Registrar datos
  async create(
    name: string,
    description: string,
    categoryId: number,
    type: 'prepared' | 'resale',
    price: number
  ) {
    return this.api.post('products/create.php', {
      name: name.trim(),
      description: description.trim(),
      category_id: categoryId,
      type,
      price,
    });
  }

  // Actualizar datos
  async update(
    id: number,
    changes: {
      name?: string;
      description?: string;
      category_id?: number;
      type?: 'prepared' | 'resale';
      price?: number;
      is_available?: boolean;
    }
  ) {
    return this.api.patch('products/update.php', { id, ...changes });
  }

  // Desactivar registro
  async deactivate(id: number) {
    return this.api.patch('products/deactivate.php', { id });
  }

  // Activar registro
  async activate(id: number) {
    return this.api.patch('products/activate.php', { id });
  }

  // Subir o reemplazar la foto del producto (Blob o data URL)
  async uploadImage(id: number, image: Blob | string) {
    return this.api.upload('products/upload-image.php', { id }, image, `producto-${id}.jpg`);
  }

  // Quitar la foto del producto
  async deleteImage(id: number) {
    return this.api.delete('products/delete-image.php', { id });
  }

  // Ruta de la foto guardada (la muestra la directiva [apiSrc])
  imageUrl(imagePath: string | null | undefined): string | null {
    return this.api.fileUrl(imagePath);
  }

  // Eliminar products de manera definitiva
  async delete(id: number) {
    return this.api.delete('products/delete.php', { id });
  }
}
