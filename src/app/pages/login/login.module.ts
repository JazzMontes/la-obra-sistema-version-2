import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { LoginPage } from './login.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: LoginPage }])],
  declarations: [LoginPage],
})
export class LoginPageModule {}
