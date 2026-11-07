// Registra las solicitudes a la API y muestra sus errores.

import { Injectable, signal } from '@angular/core';
import axios from 'axios';

@Injectable({ providedIn: 'root' })
export class ApiDiagnosticsService {

  // Datos y estado
  last: any = null;
  private readonly modalOpenState = signal(false);

  // Estado del aviso de error
  get modalOpen(): boolean {
    return this.modalOpenState();
  }

  // Estado del aviso de error
  set modalOpen(value: boolean) {
    this.modalOpenState.set(value);
  }
  modalDetails = '';
  modalMessage = '';

  // Dependencias e inicio
  constructor() {
    // Ninguna solicitud se queda esperando para siempre si el servidor no responde.
    if (!axios.defaults.timeout) axios.defaults.timeout = 15000;

    axios.interceptors.request.use((config) => {
      this.last = this.describe(
        config,
        0,
        null,
        {},
        'Enviando solicitud',
        'pending'
      );
      return config;
    });
    axios.interceptors.response.use(
      (response) => {
        const payload = response.data;
        const applicationError =
          payload &&
          typeof payload === 'object' &&
          (payload.success === false ||
            payload.ok === false ||
            (payload.error !== undefined &&
              payload.error !== null &&
              payload.error !== false &&
              payload.error !== ''));
        const invalidLogin =
          this.isLogin(response.config) &&
          (!payload ||
            payload.success !== true ||
            !payload.token ||
            !payload.user);

        if (applicationError || invalidLogin) {
          const message =
            typeof payload?.message === 'string'
              ? payload.message
              : typeof payload?.error === 'string'
                ? payload.error
                : invalidLogin
                  ? 'La API no devolvió una sesión válida'
                  : 'La API informó un error';
          this.last = this.describe(
            response.config,
            response.status,
            payload,
            response.headers,
            message,
            'error'
          );

          // Los errores de validación los muestra cada pantalla como aviso breve.
          const error: any = new Error(message);
          error.config = response.config;
          error.response = response;
          error.code = 'API_PAYLOAD_ERROR';
          return Promise.reject(error);
        }

        this.last = this.describe(
          response.config,
          response.status,
          payload,
          response.headers,
          this.isLogin(response.config)
            ? 'Acceso correcto'
            : 'Solicitud completada',
          'success'
        );
        return response;
      },
      (error) => {
        const message =
          typeof error.response?.data?.message === 'string'
            ? error.response.data.message
            : error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT'
              ? 'El servidor tardó demasiado en responder'
              : error.code === 'ERR_NETWORK'
                ? 'No hay conexión con el servidor'
                : error.message;
        this.last = this.describe(
          error.config,
          error.response?.status || 0,
          error.response?.data,
          error.response?.headers,
          message,
          'error'
        );

        // La ventana de diagnóstico solo se abre cuando no hubo respuesta del servidor
        // (red caída, servidor apagado, CORS o tiempo agotado).
        if (!this.isLogin(error.config) && !error.response) this.showError();

        return Promise.reject(error);
      }
    );
  }

  // Identificar solicitud de inicio de sesión
  private isLogin(config: any): boolean {
    return String(config?.url || '')
      .split('?')[0]
      .endsWith('/auth/login.php');
  }

  // Ocultar datos sensibles
  private scrub(data: any): any {
    if (data === null || data === undefined) return null;

    if (typeof data !== 'object') return data;

    if (Array.isArray(data)) return data.map((v) => this.scrub(v));

    return Object.fromEntries(
      Object.entries(data).map(([k, v]) => [
        k,
        /password|token|authorization|cookie|secret|clave/i.test(k)
          ? '[OCULTO]'
          : this.scrub(v),
      ])
    );
  }

  // Preparar detalles de la solicitud
  private describe(
    config: any,
    status: number,
    payload: any,
    headers?: any,
    message?: string,
    outcome = 'error'
  ) {
    const url = config?.url || '(Solicitud no enviada)';
    let destinationIp = '';

    try {
      destinationIp = new URL(url).hostname;
    } catch {
      /* sin URL válida */
    }

    let sent: any = config?.data;

    try {
      sent = JSON.parse(sent);
    } catch {
      /* objeto o payload no JSON */
    }

    return {
      outcome,
      url,
      destinationIp,
      method: (config?.method || 'GET').toUpperCase(),
      status,
      network: status
        ? 'Servidor respondió'
        : typeof navigator !== 'undefined' && !navigator.onLine
          ? 'Dispositivo sin conexión'
          : outcome === 'pending'
            ? 'Esperando respuesta'
            : /tardó demasiado/.test(message || '')
              ? 'Tiempo de espera agotado'
            : 'Sin respuesta del servidor (revisar red, CORS o servidor)',
      message: message || 'Error en la solicitud',
      requestHeaders: this.scrub(
        config?.headers?.toJSON?.() || config?.headers || {}
      ),
      responseHeaders: this.scrub(headers?.toJSON?.() || headers || {}),
      requestParams: this.scrub(config?.params),
      requestPayload: this.scrub(sent),
      responsePayload: this.scrub(payload),
    };
  }

  // Registrar error local
  reportLocalError(message: string, config?: any): void {
    this.last = this.describe(config, 0, null, {}, message, 'error');
    this.last.network = 'Solicitud no enviada';
  }

  // Mostrar diagnóstico en texto
  asText(): string {
    return JSON.stringify(
      this.last || { message: 'Sin solicitudes registradas' },
      null,
      2
    );
  }

  // Abrir aviso de error
  private showError(): void {
    // Mantiene la información del primer error mientras el modal está abierto.
    if (this.modalOpen) return;

    this.modalDetails = this.asText();
    this.modalMessage =
      this.last?.message || 'No se pudo completar la solicitud';
    this.modalOpen = true;
  }

  // Cerrar aviso de error
  closeModal(): void {
    this.modalOpen = false;
  }
}
