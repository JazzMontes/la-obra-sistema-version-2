// Protege las rutas: sin sesión se va al login; las de administración piden rol admin;
// las de una función que el plan del negocio no tiene vigente llevan a Plan y créditos.
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { BillingService } from './billing';

function storedUser(): any {
  try {
    return JSON.parse(localStorage.getItem('user') || 'null');
  } catch {
    return null;
  }
}

export const authGuard: CanActivateFn = () => {
  const router = inject(Router);
  const user = storedUser();
  if (!localStorage.getItem('token') || !user) return router.parseUrl('/login');
  if (user.must_change_password) return router.parseUrl('/change-password');
  return true;
};

export const adminGuard: CanActivateFn = () => {
  const router = inject(Router);
  const user = storedUser();
  if (!localStorage.getItem('token') || !user) return router.parseUrl('/login');
  return user.role === 'admin' ? true : router.parseUrl('/home');
};

// La función (ventas, inventario, reportes…) debe estar vigente para el negocio:
// incluida en su plan o desbloqueada con créditos. El servidor lo vuelve a revisar en cada petición.
// Varias separadas por "|": basta con tener una (ej. 'inventario|recetas').
export function featureGuard(feature: string): CanActivateFn {
  return () => {
    const router = inject(Router);
    const billing = inject(BillingService);
    const keys = feature.split('|');
    if (keys.some(k => billing.isActive(k))) return true;
    return router.createUrlTree(['/billing'], { queryParams: { feature: keys[0] } });
  };
}
