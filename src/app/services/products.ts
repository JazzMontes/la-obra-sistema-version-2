// Envía las solicitudes de productos a la API.

import { Injectable } from '@angular/core';
import axios from 'axios';
import { ApiConfigService } from './api-config';

@Injectable({ providedIn: 'root' })
export class Products {

  // Dependencias e inicio
  constructor(private apiConfig: ApiConfigService) {}

  // Obtener dirección de la API
  private get apiUrl(): string {
    return this.apiConfig.getApiUrl();
  }

  // Preparar encabezados
  private getHeaders() {
    const token = localStorage.getItem('token');
    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
  }

  // Consultar registros
  async getAll() {
    const response = await axios.get(`${this.apiUrl}/products/index.php`, {
      headers: this.getHeaders(),
    });
    return response.data;
  }

  // Consultar registro por ID
  async getById(id: number) {
    const response = await axios.get(`${this.apiUrl}/products/show.php`, {
      params: { id },
      headers: this.getHeaders(),
    });
    return response.data;
  }

  // Registrar datos
  async create(
    name: string,
    description: string,
    categoryId: number,
    type: 'prepared' | 'resale',
    price: number
  ) {
    const response = await axios.post(
      `${this.apiUrl}/products/create.php`,
      {
        name: name.trim(),
        description: description.trim(),
        category_id: categoryId,
        type,
        price,
      },
      { headers: this.getHeaders() }
    );
    return response.data;
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
    const response = await axios.patch(
      `${this.apiUrl}/products/update.php`,
      { id, ...changes },
      { headers: this.getHeaders() }
    );
    return response.data;
  }

  // Desactivar registro
  async deactivate(id: number) {
    const response = await axios.patch(
      `${this.apiUrl}/products/deactivate.php`,
      { id },
      { headers: this.getHeaders() }
    );
    return response.data;
  }

  // Activar registro
  async activate(id: number) {
    const response = await axios.patch(
      `${this.apiUrl}/products/activate.php`,
      { id },
      { headers: this.getHeaders() }
    );
    return response.data;
  }
  // Subir o reemplazar la foto del producto (multipart/form-data)
  async uploadImage(id: number, image: Blob) {
    const form = new FormData();
    form.append('id', String(id));
    form.append('image', image, `producto-${id}.jpg`);
    const response = await axios.post(`${this.apiUrl}/products/upload-image.php`, form, {
      headers: { Authorization: `Bearer ${localStorage.getItem('token')}` },
      timeout: 30000,
    });
    return response.data;
  }

  // Quitar la foto del producto
  async deleteImage(id: number) {
    return (await axios.delete(`${this.apiUrl}/products/delete-image.php`, {
      data: { id }, headers: this.getHeaders(),
    })).data;
  }

  // Dirección pública de la foto guardada en el servidor
  imageUrl(imagePath: string | null | undefined): string | null {
    if (!imagePath) return null;
    if (/^(data:|blob:|https?:)/.test(imagePath)) return imagePath;
    try {
      return `${this.apiUrl}/${imagePath.replace(/^\/+/, '')}`;
    } catch {
      return null;
    }
  }

  // Eliminar products de manera definitiva
  async delete(id: number) {
    return (await axios.delete(`${this.apiUrl}/products/delete.php`, {
      data: { id }, headers: this.getHeaders(),
    })).data;
  }
}
