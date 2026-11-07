import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { ExpensesPage } from './expenses.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: ExpensesPage }])],
  declarations: [ExpensesPage],
})
export class ExpensesPageModule {}
