import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { PaymentMethodsPage } from './payment-methods.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: PaymentMethodsPage }])],
  declarations: [PaymentMethodsPage],
})
export class PaymentMethodsPageModule {}
