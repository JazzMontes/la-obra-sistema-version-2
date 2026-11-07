import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { WastePage } from './waste.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: WastePage }])],
  declarations: [WastePage],
})
export class WastePageModule {}
