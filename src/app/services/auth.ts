// Gestiona la sesión, el perfil y la contraseña mediante la API.
// Versión 2: usa ApiService (Supabase) con las mismas rutas auth/*.php de antes.

import { Injectable } from '@angular/core';
import { ApiService } from './api';
import { TOKEN_KEY, USER_KEY } from './storage-keys';

@Injectable({
  providedIn: 'root',
})
export class Auth {

  // Dependencias e inicio
  constructor(private api: ApiService) {}

  // Iniciar sesión
  async login(username: string, password: string) {
    const data = await this.api.post('auth/login.php', {
      username: username.trim(),
      password: password,
    });

    if (data.success && data.token) {
      localStorage.setItem(TOKEN_KEY, data.token);
      localStorage.setItem(USER_KEY, JSON.stringify(data.user));
    }

    return data;
  }

  // Registrar usuario
  async register(
    name: string,
    username: string,
    email: string,
    password: string
  ) {
    return this.api.post('auth/register.php', {
      name: name.trim(),
      username: username.trim(),
      email: email.trim(),
      password: password,
    });
  }

  // Obtener token guardado
  getToken(): string | null {
    return localStorage.getItem(TOKEN_KEY);
  }

  // Obtener usuario guardado
  getStoredUser() {
    const user = localStorage.getItem(USER_KEY);

    if (!user) {
      return null;
    }

    try {
      return JSON.parse(user);
    } catch {
      return null;
    }
  }

  // Consultar perfil
  async getMe() {
    const data = await this.api.get('auth/me.php');

    if (data.success && data.user) {
      localStorage.setItem(USER_KEY, JSON.stringify(data.user));
    }

    return data;
  }

  // Actualizar perfil
  async updateProfile(name: string, username: string, email: string) {
    const data = await this.api.put('auth/me.php', {
      name: name.trim(),
      username: username.trim(),
      email: email.trim(),
    });

    if (data.success && data.user) {
      const current = this.getStoredUser() || {};
      localStorage.setItem(USER_KEY, JSON.stringify({ ...current, ...data.user }));
    }

    return data;
  }

  // Cambiar contraseña
  async changePassword(currentPassword: string, newPassword: string) {
    return this.api.patch('auth/password.php', {
      current_password: currentPassword,
      new_password: newPassword,
    });
  }

  // Cerrar sesión
  async logout() {
    try {
      return await this.api.post('auth/logout.php', {});
    } finally {
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(USER_KEY);
    }
  }

  // Comprobar sesión guardada
  isLoggedIn(): boolean {
    return this.getToken() !== null;
  }
}
