import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { InputsPage } from './inputs.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: InputsPage }])],
  declarations: [InputsPage],
})
export class InputsPageModule {}
