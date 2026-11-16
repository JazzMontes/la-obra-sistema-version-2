// Valida estudiantes con Control Escolar y demuestra un descuento del 10 %.

import { ChangeDetectionStrategy, Component, ChangeDetectorRef } from '@angular/core';
import axios from 'axios';
import { autoRefresh } from '../../services/render';
import {
  ControlEscolar,
  ValidacionAlumno
} from '../../services/control-escolar';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-student-validation',
  templateUrl: './student-validation.page.html',
  styleUrls: ['./student-validation.page.scss'],
  standalone: false,
})
export class StudentValidationPage {
  // Actualiza la vista al terminar peticiones y al entrar a la pantalla (Angular sin zone.js)
  private readonly refresher = autoRefresh();


  matricula = '';
  matriculaConsultada = '';
  monto: string | number | null = null;
  cargando = false;
  error = '';
  resultado: ValidacionAlumno | null = null;

  readonly porcentajeDescuento = 10;

  constructor(
    private controlEscolar: ControlEscolar,
    private cdr: ChangeDetectorRef
  ) {}

  // Comprobar que el monto sea válido.
  get montoValido(): boolean {
    const valor = Number(this.monto);

    return this.monto !== null
      && String(this.monto).trim() !== ''
      && Number.isFinite(valor)
      && valor > 0
      && Number.isSafeInteger(Math.round(valor * 100));
  }

  // Trabajar en centavos para redondear los importes.
  get consumoCentavos(): number {
    return this.montoValido
      ? Math.round(Number(this.monto) * 100)
      : 0;
  }

  // Aplicar el beneficio solo a la matrícula validada.
  get tieneDescuento(): boolean {
    return this.resultado?.exists === true
      && this.resultado.active === true
      && this.matricula.trim() === this.matriculaConsultada;
  }

  get descuentoCentavos(): number {
    return this.tieneDescuento
      ? Math.round(this.consumoCentavos * this.porcentajeDescuento / 100)
      : 0;
  }

  get consumo(): number {
    return this.consumoCentavos / 100;
  }

  get descuento(): number {
    return this.descuentoCentavos / 100;
  }

  get total(): number {
    return (this.consumoCentavos - this.descuentoCentavos) / 100;
  }

  // Borrar la validación anterior si cambia la matrícula.
  limpiarResultado(): void {
    this.resultado = null;
    this.matriculaConsultada = '';
    this.error = '';
  }

  // Consultar el estado actual del estudiante.
  async validarAlumno(): Promise<void> {
    if (this.cargando) return;

    this.limpiarResultado();

    const matricula = this.matricula.trim();

    if (!matricula) {
      this.error = 'Ingresa la matrícula del estudiante';
      return;
    }

    this.cargando = true;

    try {
      this.resultado =
        await this.controlEscolar.validarAlumno(matricula);

      this.matriculaConsultada = matricula;
    } catch (error: unknown) {
      if (axios.isAxiosError(error)) {
        this.error = error.response?.data?.message
          || 'No se pudo conectar con Control Escolar. Intenta verificar nuevamente.';
      } else {
        this.error = error instanceof Error
          ? error.message
          : 'No se pudo verificar la matrícula';
      }
    } finally {
      this.cargando = false;
      this.cdr.detectChanges();
    }
  }
}