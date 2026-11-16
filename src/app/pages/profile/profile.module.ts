import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { ProfilePage } from './profile.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: ProfilePage }])],
  declarations: [ProfilePage],
})
export class ProfilePageModule {}
