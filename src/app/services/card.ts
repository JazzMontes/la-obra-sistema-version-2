// Validación de una tarjeta para el cobro de planes y créditos (modo de prueba).
// El número completo y el CVV solo se revisan aquí, en el dispositivo: al servidor se mandan
// únicamente la marca, los últimos 4 dígitos, el vencimiento y el titular.
//
// Tarjetas de prueba:
//   4242 4242 4242 4242  Visa        → aprobada
//   5555 5555 5555 4444  Mastercard  → aprobada
//   3782 822463 10005    Amex        → aprobada (CVV de 4 dígitos)
//   4000 0000 0000 0002  Visa        → rechazada por el banco

export type CardBrand = 'Visa' | 'Mastercard' | 'American Express';

export interface CardForm {
  number: string;
  holder: string;
  exp: string; // MM/AA
  cvv: string;
}

export interface CardErrors {
  number?: string;
  holder?: string;
  exp?: string;
  cvv?: string;
}

export function emptyCard(): CardForm {
  return { number: '', holder: '', exp: '', cvv: '' };
}

export function digits(v: string): string {
  return String(v || '').replace(/\D/g, '');
}

export function cardBrand(num: string): CardBrand | null {
  const d = digits(num);
  if (/^4/.test(d)) return 'Visa';
  if (/^(5[1-5]|2(22[1-9]|2[3-9]\d|[3-6]\d\d|7[01]\d|720))/.test(d)) return 'Mastercard';
  if (/^3[47]/.test(d)) return 'American Express';
  return null;
}

function cardLength(brand: CardBrand | null): number {
  return brand === 'American Express' ? 15 : 16;
}

export function cvvLength(brand: CardBrand | null): number {
  return brand === 'American Express' ? 4 : 3;
}

// Algoritmo de Luhn: detecta números mal escritos
export function luhn(num: string): boolean {
  const d = digits(num);
  if (!d) return false;
  let sum = 0;
  for (let i = 0; i < d.length; i++) {
    let n = +d[d.length - 1 - i];
    if (i % 2 === 1) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
  }
  return sum % 10 === 0;
}

// "4242424242424242" → "4242 4242 4242 4242" (Amex: 4-6-5)
export function formatCardNumber(v: string): string {
  const brand = cardBrand(v);
  const d = digits(v).slice(0, cardLength(brand));
  if (brand === 'American Express') {
    return [d.slice(0, 4), d.slice(4, 10), d.slice(10, 15)].filter(Boolean).join(' ');
  }
  return d.replace(/(\d{4})(?=\d)/g, '$1 ');
}

// "1228" → "12/28"
export function formatExp(v: string): string {
  const d = digits(v).slice(0, 4);
  return d.length > 2 ? `${d.slice(0, 2)}/${d.slice(2)}` : d;
}

export function parseExp(v: string): { month: number; year: number } | null {
  const m = /^(\d{2})\/(\d{2})$/.exec(String(v || '').trim());
  if (!m) return null;
  const month = +m[1];
  const year = 2000 + +m[2];
  if (month < 1 || month > 12) return null;
  return { month, year };
}

export function validateCard(c: CardForm, now = new Date()): CardErrors {
  const e: CardErrors = {};
  const brand = cardBrand(c.number);
  const d = digits(c.number);
  if (!d) e.number = 'Escribe el número de la tarjeta';
  else if (!brand) e.number = 'Solo se aceptan Visa, Mastercard o American Express';
  else if (d.length !== cardLength(brand) || !luhn(d)) e.number = 'El número de tarjeta no es válido';

  if (String(c.holder || '').trim().length < 3) e.holder = 'Escribe el nombre como aparece en la tarjeta';

  const exp = parseExp(c.exp);
  if (!exp) e.exp = /^\d{2}\/\d{2}$/.test(String(c.exp || '').trim()) ? 'El mes debe ser de 01 a 12' : 'Usa el formato MM/AA';
  else {
    // La tarjeta sirve hasta el último día del mes que trae impreso
    const end = new Date(exp.year, exp.month, 1);
    if (end.getTime() <= now.getTime()) e.exp = 'La tarjeta está vencida';
    else if (exp.year > now.getFullYear() + 20) e.exp = 'La fecha de vencimiento no es válida';
  }

  const cv = digits(c.cvv);
  if (cv.length !== cvvLength(brand) || cv !== String(c.cvv).trim()) {
    e.cvv = `El CVV son ${cvvLength(brand)} dígitos`;
  }
  return e;
}

// Lo único que sale del dispositivo
export function cardPayload(c: CardForm) {
  const exp = parseExp(c.exp)!;
  const d = digits(c.number);
  return {
    brand: cardBrand(d),
    last4: d.slice(-4),
    exp_month: exp.month,
    exp_year: exp.year,
    holder: String(c.holder).trim().replace(/\s+/g, ' '),
  };
}
