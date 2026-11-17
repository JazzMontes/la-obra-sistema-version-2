import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { CashCutPage } from './cash-cut.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: CashCutPage }])],
  declarations: [CashCutPage],
})
export class CashCutPageModule {}
