// Protege las rutas: sin sesión se va al login; las de administración piden rol admin.
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

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
