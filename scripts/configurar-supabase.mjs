// Escribe la dirección y la clave pública de Supabase en src/environments/*.ts
// Uso:  SUPABASE_URL=https://xxxx.supabase.co SUPABASE_KEY=sb_publishable_xxx node scripts/configurar-supabase.mjs
// Si las variables están vacías no cambia nada (la app pedirá la conexión en la pantalla "Servidor").
import { readFileSync, writeFileSync } from 'node:fs';

const url = String(process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '').replace(/\/rest\/v1$/, '');
const key = String(process.env.SUPABASE_KEY || '').trim();

if (!url && !key) {
  console.log('SUPABASE_URL y SUPABASE_KEY vacías: se compila sin conexión fija (se configura desde la pantalla Servidor).');
  process.exit(0);
}
if (!/^https:\/\/[^/]+$/.test(url)) {
  console.error('SUPABASE_URL debe verse así: https://xxxxxxxx.supabase.co');
  process.exit(1);
}
if (!key || key.startsWith('sb_secret_') || /service_role/.test(Buffer.from(key.split('.')[1] || '', 'base64').toString())) {
  console.error('SUPABASE_KEY debe ser la clave PÚBLICA (sb_publishable_… o anon). Nunca la secret / service_role.');
  process.exit(1);
}

for (const file of ['src/environments/environment.prod.ts', 'src/environments/environment.ts']) {
  let s = readFileSync(file, 'utf8');
  s = s.replace(/supabaseUrl:\s*'[^']*'/, `supabaseUrl: '${url}'`).replace(/supabaseKey:\s*'[^']*'/, `supabaseKey: '${key}'`);
  writeFileSync(file, s);
  console.log('Configurado', file, '→', new URL(url).host);
}
