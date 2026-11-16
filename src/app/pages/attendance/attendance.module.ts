import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { AttendancePage } from './attendance.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: AttendancePage }])],
  declarations: [AttendancePage],
})
export class AttendancePageModule {}
