// Comprueba el funcionamiento de autenticación.

import { TestBed } from '@angular/core/testing';
import { Auth } from './auth';

// Pruebas
describe('Auth', () => {
  let service: Auth;

  // Preparar prueba
  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(Auth);
  });

  // Comprobar resultado
  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
