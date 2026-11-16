import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { PosPage } from './pos.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: PosPage }])],
  declarations: [PosPage],
})
export class PosPageModule {}
