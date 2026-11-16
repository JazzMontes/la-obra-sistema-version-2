// Consulta el estado de un estudiante en la API de Control Escolar.

import { Injectable } from '@angular/core';
import axios from 'axios';
import { environment } from '../../environments/environment';

export interface ValidacionAlumno {
  success: boolean;
  exists: boolean;
  active: boolean;
}

@Injectable({
  providedIn: 'root'
})
export class ControlEscolar {

  // Dirección del servicio de Control Escolar (environment.controlEscolarUrl).
  private readonly apiUrl = String(environment.controlEscolarUrl || '').trim();

  // Verificar una matrícula sin modificar sus datos.
  async validarAlumno(matricula: string): Promise<ValidacionAlumno> {
    const valor = matricula.trim();

    if (!valor) {
      throw new Error('Ingresa la matrícula del estudiante');
    }

    if (!this.apiUrl) {
      throw new Error('La validación de estudiantes no está disponible en este servidor');
    }

    const response = await axios.get<ValidacionAlumno & {
      message?: string;
    }>(this.apiUrl, {
      params: { matricula: valor },
      timeout: 10000
    });

    const data = response.data;

    if (!data.success) {
      throw new Error(data.message || 'No se pudo verificar la matrícula');
    }

    if (
      typeof data.exists !== 'boolean' ||
      typeof data.active !== 'boolean'
    ) {
      throw new Error('Control Escolar devolvió una respuesta inválida');
    }

    return data;
  }
}