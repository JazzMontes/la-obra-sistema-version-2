// Define la configuración del entorno de desarrollo (ng serve / ionic serve).
//
// Pega aquí los datos de TU proyecto de Supabase "la-obra-sistema-version-2":
//   Supabase → Project Settings → API (o "Connect")
//   - supabaseUrl: Project URL, p. ej. https://abcdefghijkl.supabase.co
//   - supabaseKey: la clave "publishable" (sb_publishable_...) o la "anon public" (eyJ...)
// Esa clave es pública por diseño: solo permite llamar a la función la_obra_v2_api,
// que pide usuario y contraseña para todo lo demás. NUNCA pongas aquí la "service_role".

export const environment = {
  production: false,
  appName: 'La Obra · Sistema v2',
  supabaseUrl: 'https://TU-PROYECTO.supabase.co',
  supabaseKey: 'TU-CLAVE-PUBLICA',
};
