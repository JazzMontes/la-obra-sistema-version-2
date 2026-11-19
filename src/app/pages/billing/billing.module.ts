import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { BillingPage } from './billing.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: BillingPage }])],
  declarations: [BillingPage],
})
export class BillingPageModule {}
