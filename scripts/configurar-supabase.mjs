// Escribe src/environments/environment.prod.ts con los datos de Supabase.
// Lo usa GitHub Actions con las variables del repositorio SUPABASE_URL y SUPABASE_KEY,
// y también se puede correr a mano:
//   SUPABASE_URL=https://xxxx.supabase.co SUPABASE_KEY=sb_publishable_xxx node scripts/configurar-supabase.mjs
import { writeFileSync } from 'node:fs';

const url = String(process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
const key = String(process.env.SUPABASE_KEY || '').trim();

if (!/^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+$/i.test(url)) {
  console.error('SUPABASE_URL no es válida (ejemplo: https://abcd1234.supabase.co)');
  process.exit(1);
}
if (!key) {
  console.error('Falta SUPABASE_KEY (clave publishable o anon)');
  process.exit(1);
}
let role = '';
try { role = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role; } catch { /* no es JWT */ }
if (role === 'service_role' || key.startsWith('sb_secret_')) {
  console.error('SUPABASE_KEY es la clave SECRETA. Usa la clave pública (publishable o anon).');
  process.exit(1);
}

const content = `// Generado por scripts/configurar-supabase.mjs — no lo edites a mano en GitHub Actions.
export const environment = {
  production: true,
  appName: 'La Obra · Sistema v2',
  supabaseUrl: ${JSON.stringify(url)},
  supabaseKey: ${JSON.stringify(key)},
};
`;
for (const file of ['src/environments/environment.prod.ts', 'src/environments/environment.ts']) {
  writeFileSync(file, content.replace('production: true', file.endsWith('prod.ts') ? 'production: true' : 'production: false'));
}
console.log('Supabase configurado:', url);
