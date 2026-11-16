// Reduce y convierte a JPEG las fotos tomadas con la cámara o elegidas de la galería.
// Así se suben más rápido y la copia sin conexión cabe en el almacenamiento local.

export const MAX_IMAGE_SIDE = 1024;

// Leer un archivo como data URL
function readAsDataUrl(file: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error('No se pudo leer la imagen'));
    reader.readAsDataURL(file);
  });
}

// Cargar una imagen en memoria
function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('El archivo no es una imagen válida'));
    img.src = src;
  });
}

// Redimensionar y comprimir; devuelve un data URL JPEG
export async function compressImage(
  file: File,
  maxSide = MAX_IMAGE_SIDE,
  quality = 0.8
): Promise<string> {
  if (!file.type.startsWith('image/')) {
    throw new Error('Selecciona un archivo de imagen');
  }
  if (file.size > 20 * 1024 * 1024) {
    throw new Error('La imagen es demasiado grande');
  }

  const img = await loadImage(await readAsDataUrl(file));
  const scale = Math.min(1, maxSide / Math.max(img.width, img.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(img.width * scale);
  canvas.height = Math.round(img.height * scale);

  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('No se pudo procesar la imagen');

  // Fondo blanco para PNG con transparencia
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL('image/jpeg', quality);
}

// Convertir data URL a Blob para enviarlo con FormData
export function dataUrlToBlob(dataUrl: string): Blob {
  const [header, base64] = dataUrl.split(',');
  const mime = /data:([^;]+)/.exec(header)?.[1] || 'image/jpeg';
  const bytes = atob(base64);
  const buffer = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) buffer[i] = bytes.charCodeAt(i);
  return new Blob([buffer], { type: mime });
}
