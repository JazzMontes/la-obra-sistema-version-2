// Inicia la aplicación Angular.

import { platformBrowserDynamic } from '@angular/platform-browser-dynamic';

import { AppModule } from './app/app.module';
import { installSupabaseBridge } from './app/services/supabase-bridge';

// Antes de cualquier petición: las rutas de la API se envían a Supabase (ver supabase-bridge.ts)
installSupabaseBridge();

platformBrowserDynamic()
  .bootstrapModule(AppModule)
  .catch((err) => console.log(err));
