import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { MoneyPage } from './money.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: MoneyPage }])],
  declarations: [MoneyPage],
})
export class MoneyPageModule {}
