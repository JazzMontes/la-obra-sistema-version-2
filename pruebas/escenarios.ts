// Evidencia de escenarios de prueba de las reglas de contexto.
// Se ejecuta sin Angular:   npx tsx pruebas/escenarios.ts
// (o: npx tsc pruebas/escenarios.ts --outDir /tmp/esc && node /tmp/esc/pruebas/escenarios.js)
//
// Cada escenario parte de datos de sensores "crudos" (distancia GPS, calidad de red, hora),
// los clasifica en variables de contexto y muestra qué decide el motor de reglas.

import {
  Contexto,
  clasificarHorario,
  clasificarRed,
  clasificarZona,
  evaluarReglas,
} from '../src/app/services/context-rules';

interface Escenario {
  nombre: string;
  sensores: { distanciaM: number | null; radioM: number; precisionM: number | null; calidadRed: 'good' | 'weak' | 'offline'; hora: string; accion: 'llegada' | 'salida' };
  esperado: { reglas: string[]; registro: string };
}

const ESCENARIOS: Escenario[] = [
  {
    nombre: '1. Empleado en el local, Wi-Fi bueno, 9:15',
    sensores: { distanciaM: 35, radioM: 100, precisionM: 12, calidadRed: 'good', hora: '09:15', accion: 'llegada' },
    esperado: { reglas: ['R1'], registro: 'en-linea' },
  },
  {
    nombre: '2. Empleado en el local, modo avión, 9:20',
    sensores: { distanciaM: 40, radioM: 100, precisionM: 15, calidadRed: 'offline', hora: '09:20', accion: 'llegada' },
    esperado: { reglas: ['R2', 'R4'], registro: 'al-volver-red' },
  },
  {
    nombre: '3. Empleado a 1.2 km (en camino), datos móviles buenos, 8:50',
    sensores: { distanciaM: 1200, radioM: 100, precisionM: 20, calidadRed: 'good', hora: '08:50', accion: 'llegada' },
    esperado: { reglas: ['R3'], registro: 'bloqueado' },
  },
  {
    nombre: '4. Empleado en el local, 3G lento, 6:40 (antes de abrir)',
    sensores: { distanciaM: 20, radioM: 100, precisionM: 18, calidadRed: 'weak', hora: '06:40', accion: 'llegada' },
    esperado: { reglas: ['R1', 'R4', 'R5'], registro: 'en-linea' },
  },
  {
    nombre: '5. Empleado sale a las 22:30, Wi-Fi bueno',
    sensores: { distanciaM: 30, radioM: 100, precisionM: 10, calidadRed: 'good', hora: '22:30', accion: 'salida' },
    esperado: { reglas: ['R1'], registro: 'en-linea' },
  },
  {
    nombre: '6. GPS impreciso (±400 m) dentro de un edificio',
    sensores: { distanciaM: 50, radioM: 100, precisionM: 400, calidadRed: 'good', hora: '10:00', accion: 'llegada' },
    esperado: { reglas: [], registro: 'ubicar' },
  },
];

const hoyA = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number);
  return new Date(2026, 10, 24, h, m);
};

declare const process: { exit(code: number): never };
let fallas = 0;
console.log('Pruebas de reglas de contexto · La Obra v2 ·', new Date().toLocaleString('es-MX'));
console.log('='.repeat(78));
for (const e of ESCENARIOS) {
  const s = e.sensores;
  const ctx: Contexto = {
    zona: clasificarZona(s.distanciaM, s.radioM, s.precisionM),
    red: clasificarRed(s.calidadRed),
    horario: clasificarHorario(hoyA(s.hora)),
    accion: s.accion,
  };
  const d = evaluarReglas(ctx);
  const ok = d.registro === e.esperado.registro && d.reglas.join() === e.esperado.reglas.join();
  if (!ok) fallas++;
  console.log(`\n${e.nombre}`);
  console.log(`  Sensores : distancia=${s.distanciaM} m (radio ${s.radioM} m, ±${s.precisionM} m) · red=${s.calidadRed} · hora=${s.hora} · ${s.accion}`);
  console.log(`  Contexto : zona=${ctx.zona} · red=${ctx.red} · horario=${ctx.horario}`);
  console.log(`  Reglas   : ${d.reglas.join(' + ') || '(ninguna)'}`);
  console.log(`  Decisión : registro=${d.registro} · botón ${d.botonHabilitado ? 'habilitado' : 'DESHABILITADO'} "${d.textoBoton}"`);
  console.log(`             mapa=${d.mostrarMapa ? 'sí' : 'no (modo ligero)'} · nota ${d.notaObligatoria ? 'OBLIGATORIA' : 'opcional'} · cómo llegar=${d.mostrarComoLlegar ? 'sí' : 'no'}`);
  console.log(`  Esperado : ${e.esperado.reglas.join(' + ') || '(ninguna)'} / ${e.esperado.registro}  →  ${ok ? 'PASA ✔' : 'FALLA ✘'}`);
}
console.log('\n' + '='.repeat(78));
console.log(`${ESCENARIOS.length - fallas} de ${ESCENARIOS.length} escenarios pasan.`);
if (fallas) process.exit(1);
