// Reglas de contexto: el comportamiento de la app cambia según dónde está el usuario,
// cómo está su conexión y la hora.
//
// Este archivo NO depende de Angular ni del navegador: solo recibe el contexto ya medido
// y devuelve una decisión. Así las reglas se pueden probar con datos inventados
// (ver context-rules.spec.ts y pruebas/escenarios.ts) y la pantalla solo obedece la decisión.
//
//   Sensores (GPS, red, reloj) ──► clasificar*() ──► Contexto ──► evaluarReglas() ──► Decisión ──► Pantalla

// ---------------- Variables de contexto ----------------

/** Variable 1 · Zona: ¿el usuario está dentro del radio del negocio? (GPS + radio que configuró el admin) */
export type Zona = 'dentro' | 'fuera' | 'desconocida';

/** Variable 2 · Red: estado de la conexión a internet (sensor de red de La Obra) */
export type Red = 'buena' | 'lenta' | 'sin-conexion';

/** Variable 3 · Horario: ¿la hora actual está dentro del horario laboral? (reloj del dispositivo) */
export type Horario = 'laboral' | 'fuera';

/** Dato de apoyo: qué toca registrar ahora (entrada o salida) */
export type Accion = 'llegada' | 'salida';

export interface Contexto {
  zona: Zona;
  red: Red;
  horario: Horario;
  accion: Accion;
  /** El usuario activó "Ahorro de datos" en su teléfono (Network Information API) */
  ahorroDatos?: boolean;
}

// ---------------- Decisión (lo que la pantalla debe hacer) ----------------

/** Cómo se comporta el botón de registro */
export type ModoRegistro =
  | 'en-linea' // se registra al momento
  | 'al-volver-red' // queda "en espera" y se registra solo cuando vuelva internet
  | 'bloqueado' // no se permite (fuera de la zona)
  | 'ubicar'; // primero hay que obtener la ubicación

export type Tono = 'success' | 'warning' | 'danger' | 'info';

export interface Decision {
  registro: ModoRegistro;
  botonHabilitado: boolean;
  textoBoton: string;
  mensaje: string;
  tono: Tono;
  /** Mostrar el mapa de calles (descarga imágenes de OpenStreetMap) */
  mostrarMapa: boolean;
  /** Mostrar el enlace "Cómo llegar" en Google Maps */
  mostrarComoLlegar: boolean;
  /** La nota pasa de opcional a obligatoria */
  notaObligatoria: boolean;
  /** Reglas que se cumplieron, en orden (para el panel y para las pruebas) */
  reglas: string[];
}

export interface Regla {
  id: string;
  nombre: string;
  /** La condición escrita como en el diagrama */
  condicion: string;
  /** Lo que hace la regla, en palabras */
  efecto: string;
  si: (c: Contexto) => boolean;
  entonces: (d: Decision, c: Contexto) => void;
}

const verbo = (c: Contexto) => (c.accion === 'llegada' ? 'llegada' : 'salida');

// ---------------- Reglas de decisión ----------------
// R1, R2 y R3 deciden el registro y nunca se cumplen dos a la vez (la zona solo tiene un valor).
// R4 y R5 se suman a cualquiera de ellas.

export const REGLAS: Regla[] = [
  {
    id: 'R1',
    nombre: 'Registro en línea',
    condicion: 'zona = dentro  Y  red ≠ sin conexión',
    efecto: 'Habilita “Registrar mi llegada/salida” y lo envía al momento.',
    si: c => c.zona === 'dentro' && c.red !== 'sin-conexion',
    entonces: (d, c) => {
      d.registro = 'en-linea';
      d.botonHabilitado = true;
      d.textoBoton = `Registrar mi ${verbo(c)}`;
      d.mensaje = 'Estás en el negocio y con internet: puedes registrar.';
      d.tono = 'success';
    },
  },
  {
    id: 'R2',
    nombre: 'Registro al volver la conexión',
    condicion: 'zona = dentro  Y  red = sin conexión',
    efecto: 'Cambia el botón a “Registrar al volver la conexión”: queda en espera y se envía solo cuando regresa internet.',
    si: c => c.zona === 'dentro' && c.red === 'sin-conexion',
    entonces: (d, c) => {
      d.registro = 'al-volver-red';
      d.botonHabilitado = true;
      d.textoBoton = `Registrar mi ${verbo(c)} al volver la conexión`;
      d.mensaje = 'Estás en el negocio pero sin internet. Deja el registro en espera: se enviará solo, con una ubicación nueva, en cuanto vuelva la conexión.';
      d.tono = 'warning';
    },
  },
  {
    id: 'R3',
    nombre: 'Fuera de la zona',
    condicion: 'zona = fuera',
    efecto: 'Deshabilita el registro y muestra “Cómo llegar”.',
    si: c => c.zona === 'fuera',
    entonces: (d, c) => {
      d.registro = 'bloqueado';
      d.botonHabilitado = false;
      d.textoBoton = `Acércate al negocio para registrar tu ${verbo(c)}`;
      d.mensaje = 'Estás fuera del área permitida. El registro se habilitará en cuanto entres al radio del negocio.';
      d.tono = 'danger';
      d.mostrarComoLlegar = c.red !== 'sin-conexion';
    },
  },
  {
    id: 'R4',
    nombre: 'Modo ligero',
    condicion: 'red = lenta  O  red = sin conexión  O  ahorro de datos',
    efecto: 'Oculta el mapa de calles (descarga imágenes) y muestra solo la distancia, para ahorrar datos.',
    si: c => c.red !== 'buena' || !!c.ahorroDatos,
    entonces: d => {
      d.mostrarMapa = false;
    },
  },
  {
    id: 'R5',
    nombre: 'Llegada fuera de horario',
    condicion: 'horario = fuera  Y  acción = llegada',
    efecto: 'La nota se vuelve obligatoria: hay que explicar por qué se llega fuera del horario laboral.',
    si: c => c.horario === 'fuera' && c.accion === 'llegada',
    entonces: d => {
      d.notaObligatoria = true;
    },
  },
];

/** Lo que pasa cuando ninguna regla de registro se cumple (todavía no hay ubicación) */
export function decisionInicial(): Decision {
  return {
    registro: 'ubicar',
    botonHabilitado: true,
    textoBoton: 'Obtener mi ubicación',
    mensaje: 'Aún no sabemos si estás en el negocio. Toca el botón para leer tu ubicación.',
    tono: 'info',
    mostrarMapa: true,
    mostrarComoLlegar: false,
    notaObligatoria: false,
    reglas: [],
  };
}

/** Motor: aplica en orden todas las reglas cuya condición se cumple */
export function evaluarReglas(c: Contexto, reglas: Regla[] = REGLAS): Decision {
  const d = decisionInicial();
  for (const r of reglas) {
    if (r.si(c)) {
      r.entonces(d, c);
      d.reglas.push(r.id);
    }
  }
  return d;
}

// ---------------- De los sensores a las variables ----------------

/** Más de esto (metros de margen del GPS) y no se puede asegurar si está dentro o fuera */
export const PRECISION_MAXIMA_M = 150;

export function clasificarZona(
  distanciaM: number | null,
  radioM: number | null,
  precisionM: number | null
): Zona {
  if (distanciaM === null || radioM === null || precisionM === null) return 'desconocida';
  if (precisionM > PRECISION_MAXIMA_M) return 'desconocida';
  return distanciaM <= radioM ? 'dentro' : 'fuera';
}

/** Recibe la calidad que calcula NetworkService ('offline' | 'weak' | 'good') */
export function clasificarRed(calidad: 'offline' | 'weak' | 'good'): Red {
  return calidad === 'offline' ? 'sin-conexion' : calidad === 'weak' ? 'lenta' : 'buena';
}

/** Horario laboral de La Obra (hora local del teléfono). Ajustable aquí. */
export const HORARIO_LABORAL = { inicio: '07:00', fin: '22:00' };

export function clasificarHorario(fecha: Date, horario = HORARIO_LABORAL): Horario {
  const min = (hhmm: string) => {
    const [h, m] = hhmm.split(':').map(Number);
    return h * 60 + m;
  };
  const ahora = fecha.getHours() * 60 + fecha.getMinutes();
  return ahora >= min(horario.inicio) && ahora < min(horario.fin) ? 'laboral' : 'fuera';
}

// Textos para mostrar las variables en pantalla
export const ETIQUETAS = {
  zona: { dentro: 'Dentro del negocio', fuera: 'Fuera del negocio', desconocida: 'Sin ubicación' } as Record<Zona, string>,
  red: { buena: 'Con internet', lenta: 'Internet lento', 'sin-conexion': 'Sin conexión' } as Record<Red, string>,
  horario: { laboral: 'Horario laboral', fuera: 'Fuera de horario' } as Record<Horario, string>,
};
