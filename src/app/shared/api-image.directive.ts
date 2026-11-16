// <img [apiSrc]="ruta">: carga una foto subida (uploads/...) por medio de la API y la muestra.
// Funciona igual en el navegador y en el APK, donde Android puede bloquear <img src="http://IP/...">.
// Acepta también data URLs (fotos nuevas aún no subidas). Si la imagen no existe, dispara el
// evento (error) normal de <img>, así que los avisos de "foto no encontrada" siguen funcionando.
import { Directive, ElementRef, Input, OnChanges } from '@angular/core';
import { ApiService } from '../services/api';

const cache = new Map<string, Promise<string>>();

@Directive({ selector: 'img[apiSrc]', standalone: false })
export class ApiImageDirective implements OnChanges {
  @Input() apiSrc: string | null | undefined = null;

  constructor(private el: ElementRef<HTMLImageElement>, private api: ApiService) {}

  async ngOnChanges() {
    const img = this.el.nativeElement;
    const value = this.apiSrc ?? '';
    if (!value) {
      img.removeAttribute('src');
      return;
    }
    if (/^(data:|blob:)/.test(value)) {
      img.src = value;
      return;
    }
    // Normalizar a ruta relativa uploads/... (por si llega una URL completa)
    const m = /(uploads\/(?:products|tickets)\/[^?#]+)/.exec(value);
    const path = m ? m[1] : value.replace(/^\/+/, '');
    try {
      let p = cache.get(path);
      if (!p) {
        p = this.api.get('files/image.php', { path }).then(r => r.data_url as string);
        cache.set(path, p);
        p.catch(() => cache.delete(path));
      }
      const url = await p;
      if ((this.apiSrc ?? '') === value) img.src = url;
    } catch {
      // Imagen inexistente: provoca el evento (error) de la etiqueta
      if ((this.apiSrc ?? '') === value) img.src = 'data:image/gif;base64,invalid';
    }
  }
}
