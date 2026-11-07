import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { CostsPage } from './costs.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: CostsPage }])],
  declarations: [CostsPage],
})
export class CostsPageModule {}
