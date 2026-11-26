import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { MoneySettingsPage } from './money-settings.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: MoneySettingsPage }])],
  declarations: [MoneySettingsPage],
})
export class MoneySettingsPageModule {}
