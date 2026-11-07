import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { ChangePasswordPage } from './change-password.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: ChangePasswordPage }])],
  declarations: [ChangePasswordPage],
})
export class ChangePasswordPageModule {}
