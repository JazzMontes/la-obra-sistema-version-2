import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.laobra.sistema.v2',
  appName: 'La Obra v2',
  webDir: 'www',

  android: {
    allowMixedContent: true
  },

  server: {
    cleartext: true
  }
};

export default config;