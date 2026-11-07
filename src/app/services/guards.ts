// Protege las rutas: sin sesión se va al login; las de administración piden rol admin.
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { TOKEN_KEY, USER_KEY } from './storage-keys';

function storedUser(): any {
  try {
    return JSON.parse(localStorage.getItem(USER_KEY) || 'null');
  } catch {
    return null;
  }
}

export const authGuard: CanActivateFn = () => {
  const router = inject(Router);
  const user = storedUser();
  if (!localStorage.getItem(TOKEN_KEY) || !user) return router.parseUrl('/login');
  if (user.must_change_password) return router.parseUrl('/change-password');
  return true;
};

export const adminGuard: CanActivateFn = () => {
  const router = inject(Router);
  const user = storedUser();
  if (!localStorage.getItem(TOKEN_KEY) || !user) return router.parseUrl('/login');
  return user.role === 'admin' ? true : router.parseUrl('/home');
};
