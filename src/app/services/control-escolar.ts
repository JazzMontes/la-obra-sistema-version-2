// Consulta el estado de un estudiante en la API de Control Escolar.

import { Injectable } from '@angular/core';
import axios from 'axios';

export interface ValidacionAlumno {
  success: boolean;
  exists: boolean;
  active: boolean;
}

@Injectable({
  providedIn: 'root'
})
export class ControlEscolar {

  // Dirección del servicio alojado en la computadora de tu compañera.
  private readonly apiUrl =
    'http://192.168.1.158/control_escolar_api/api/integration/validar-alumno.php';

  // Verificar una matrícula sin modificar sus datos.
  async validarAlumno(matricula: string): Promise<ValidacionAlumno> {
    const valor = matricula.trim();

    if (!valor) {
      throw new Error('Ingresa la matrícula del estudiante');
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