import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { ProductsPage } from './products.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: ProductsPage }])],
  declarations: [ProductsPage],
})
export class ProductsPageModule {}
