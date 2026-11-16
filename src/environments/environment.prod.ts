// Configuración de la app PUBLICADA (GitHub Pages y APK). `ng build` usa este archivo.
//
// Pega aquí tu proyecto de Supabase (Project Settings → API Keys):
//   supabaseUrl: la "Project URL"      → https://xxxxxxxx.supabase.co
//   supabaseKey: la "Publishable key"  → sb_publishable_...   (o la "anon public" eyJ...)
// La clave pública SÍ puede ir en el código. NUNCA pongas la "secret" / service_role.
//
// controlEscolarUrl: servicio externo para validar estudiantes (debe ser HTTPS). Vacío = desactivado.

export const environment = {
  production: true,
  supabaseUrl: 'https://kkltwnqsdrgyxyofnsul.supabase.co',
  supabaseKey: 'sb_publishable_gpW7NTQ79RfiaNwHzQ994A_4O15ogZx',
  controlEscolarUrl: '',
};
