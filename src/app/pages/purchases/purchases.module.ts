import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { PurchasesPage } from './purchases.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: PurchasesPage }])],
  declarations: [PurchasesPage],
})
export class PurchasesPageModule {}
