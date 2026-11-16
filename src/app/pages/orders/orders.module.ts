import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { OrdersPage } from './orders.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: OrdersPage }])],
  declarations: [OrdersPage],
})
export class OrdersPageModule {}
