import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { UsersPage } from './users.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: UsersPage }])],
  declarations: [UsersPage],
})
export class UsersPageModule {}
