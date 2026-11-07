// Configuración del APK de Android (Capacitor).
// appId distinto al de la versión 1: así las dos apps pueden estar instaladas
// en el mismo teléfono sin reemplazarse ni compartir datos.
import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.laobra.sistema.v2',
  appName: 'La Obra v2',
  webDir: 'www',
  android: {
    // Supabase usa HTTPS: ya no hace falta permitir tráfico http como con XAMPP.
    allowMixedContent: false,
  },
};

export default config;
