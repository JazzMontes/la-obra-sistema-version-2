// Rutas de la aplicación. Las de configuración y análisis son solo para administradores.
// Versión 2: se usan rutas con # (…/#/pos) porque GitHub Pages no sabe redirigir
// las rutas internas de Angular; así recargar la página nunca da error 404.
import { NgModule } from '@angular/core';
import { PreloadAllModules, RouterModule, Routes } from '@angular/router';
import { adminGuard, authGuard } from './services/guards';

const page = (path: string, load: () => Promise<any>, admin = false) => ({
  path,
  loadChildren: load,
  canActivate: [admin ? adminGuard : authGuard],
});

const routes: Routes = [
  { path: 'login', loadChildren: () => import('./pages/login/login.module').then(m => m.LoginPageModule) },
  { path: 'data-origins', loadChildren: () => import('./pages/data-origins/data-origins.module').then(m => m.DataOriginsPageModule) },
  { path: 'change-password', loadChildren: () => import('./pages/change-password/change-password.module').then(m => m.ChangePasswordPageModule) },

  page('home', () => import('./home/home.module').then(m => m.HomePageModule)),
  page('pos', () => import('./pages/pos/pos.module').then(m => m.PosPageModule)),
  page('orders', () => import('./pages/orders/orders.module').then(m => m.OrdersPageModule)),
  page('inventory', () => import('./pages/inventory/inventory.module').then(m => m.InventoryPageModule)),
  page('waste', () => import('./pages/waste/waste.module').then(m => m.WastePageModule)),
  page('expenses', () => import('./pages/expenses/expenses.module').then(m => m.ExpensesPageModule)),
  page('profile', () => import('./pages/profile/profile.module').then(m => m.ProfilePageModule)),
  page('student-validation', () => import('./pages/student-validation/student-validation.module').then(m => m.StudentValidationPageModule)),

  page('purchases', () => import('./pages/purchases/purchases.module').then(m => m.PurchasesPageModule), true),
  page('products', () => import('./pages/products/products.module').then(m => m.ProductsPageModule), true),
  page('preparations', () => import('./pages/preparations/preparations.module').then(m => m.PreparationsPageModule), true),
  page('inputs', () => import('./pages/inputs/inputs.module').then(m => m.InputsPageModule), true),
  page('categories', () => import('./pages/categories/categories.module').then(m => m.CategoriesPageModule), true),
  page('costs', () => import('./pages/costs/costs.module').then(m => m.CostsPageModule), true),
  page('reports', () => import('./pages/reports/reports.module').then(m => m.ReportsPageModule), true),
  page('users', () => import('./pages/users/users.module').then(m => m.UsersPageModule), true),
  page('payment-methods', () => import('./pages/payment-methods/payment-methods.module').then(m => m.PaymentMethodsPageModule), true),

  // Rutas anteriores
  { path: 'sales', redirectTo: 'pos', pathMatch: 'full' },
  { path: 'recipes', redirectTo: 'products', pathMatch: 'full' },

  // La app siempre abre en el inicio de sesión
  { path: '', redirectTo: 'login', pathMatch: 'full' },
  { path: '**', redirectTo: 'login' },
];

@NgModule({
  imports: [RouterModule.forRoot(routes, { preloadingStrategy: PreloadAllModules, useHash: true })],
  exports: [RouterModule],
})
export class AppRoutingModule {}
