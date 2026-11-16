import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { ReportsPage } from './reports.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: ReportsPage }])],
  declarations: [ReportsPage],
})
export class ReportsPageModule {}
