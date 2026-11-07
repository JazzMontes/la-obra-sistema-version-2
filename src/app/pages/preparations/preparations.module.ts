import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { PreparationsPage } from './preparations.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: PreparationsPage }])],
  declarations: [PreparationsPage],
})
export class PreparationsPageModule {}
