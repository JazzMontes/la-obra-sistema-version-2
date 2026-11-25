// Pruebas de las reglas de contexto (Vitest: `npx ng test` o `npx vitest run`).
// No necesitan Angular: las reglas son funciones puras.

import { Contexto, clasificarHorario, clasificarRed, clasificarZona, evaluarReglas } from './context-rules';

const base: Contexto = { zona: 'dentro', red: 'buena', horario: 'laboral', accion: 'llegada' };

describe('Reglas de contexto', () => {
  it('Escenario 1 · dentro de la zona + internet → R1: registro en línea', () => {
    const d = evaluarReglas(base);
    expect(d.reglas).toEqual(['R1']);
    expect(d.registro).toBe('en-linea');
    expect(d.botonHabilitado).toBe(true);
    expect(d.mostrarMapa).toBe(true);
    expect(d.notaObligatoria).toBe(false);
  });

  it('Escenario 2 · dentro de la zona sin internet → R2 + R4: registro en espera y sin mapa', () => {
    const d = evaluarReglas({ ...base, red: 'sin-conexion' });
    expect(d.reglas).toEqual(['R2', 'R4']);
    expect(d.registro).toBe('al-volver-red');
    expect(d.botonHabilitado).toBe(true);
    expect(d.mostrarMapa).toBe(false);
  });

  it('Escenario 3 · fuera de la zona con internet → R3: registro bloqueado y "Cómo llegar"', () => {
    const d = evaluarReglas({ ...base, zona: 'fuera' });
    expect(d.reglas).toEqual(['R3']);
    expect(d.registro).toBe('bloqueado');
    expect(d.botonHabilitado).toBe(false);
    expect(d.mostrarComoLlegar).toBe(true);
  });

  it('Escenario 4 · dentro, red lenta, fuera de horario → R1 + R4 + R5', () => {
    const d = evaluarReglas({ ...base, red: 'lenta', horario: 'fuera' });
    expect(d.reglas).toEqual(['R1', 'R4', 'R5']);
    expect(d.registro).toBe('en-linea');
    expect(d.mostrarMapa).toBe(false);
    expect(d.notaObligatoria).toBe(true);
  });

  it('Escenario 5 · fuera de horario pero registrando SALIDA → R5 no aplica', () => {
    const d = evaluarReglas({ ...base, horario: 'fuera', accion: 'salida' });
    expect(d.reglas).toEqual(['R1']);
    expect(d.notaObligatoria).toBe(false);
  });

  it('Escenario 6 · sin ubicación → ninguna regla de registro: pide la ubicación', () => {
    const d = evaluarReglas({ ...base, zona: 'desconocida' });
    expect(d.reglas).toEqual([]);
    expect(d.registro).toBe('ubicar');
  });

  it('Escenario 7 · fuera de la zona y sin internet → no ofrece "Cómo llegar" (no cargaría)', () => {
    const d = evaluarReglas({ ...base, zona: 'fuera', red: 'sin-conexion' });
    expect(d.reglas).toEqual(['R3', 'R4']);
    expect(d.mostrarComoLlegar).toBe(false);
  });

  it('Ahorro de datos activa el modo ligero aunque la red sea buena', () => {
    expect(evaluarReglas({ ...base, ahorroDatos: true }).mostrarMapa).toBe(false);
  });

  it('R1, R2 y R3 nunca se cumplen a la vez', () => {
    for (const zona of ['dentro', 'fuera', 'desconocida'] as const)
      for (const red of ['buena', 'lenta', 'sin-conexion'] as const) {
        const d = evaluarReglas({ ...base, zona, red });
        expect(d.reglas.filter(id => ['R1', 'R2', 'R3'].includes(id)).length).toBeLessThanOrEqual(1);
      }
  });
});

describe('Clasificación de los sensores', () => {
  it('zona: dentro, fuera y desconocida (sin lectura o GPS impreciso)', () => {
    expect(clasificarZona(40, 100, 10)).toBe('dentro');
    expect(clasificarZona(100, 100, 10)).toBe('dentro');
    expect(clasificarZona(350, 100, 10)).toBe('fuera');
    expect(clasificarZona(null, 100, null)).toBe('desconocida');
    expect(clasificarZona(40, 100, 300)).toBe('desconocida');
  });

  it('red: usa la calidad del sensor de red', () => {
    expect(clasificarRed('good')).toBe('buena');
    expect(clasificarRed('weak')).toBe('lenta');
    expect(clasificarRed('offline')).toBe('sin-conexion');
  });

  it('horario: 07:00–22:00 es laboral', () => {
    expect(clasificarHorario(new Date(2026, 10, 24, 6, 59))).toBe('fuera');
    expect(clasificarHorario(new Date(2026, 10, 24, 7, 0))).toBe('laboral');
    expect(clasificarHorario(new Date(2026, 10, 24, 21, 59))).toBe('laboral');
    expect(clasificarHorario(new Date(2026, 10, 24, 22, 0))).toBe('fuera');
  });
});
