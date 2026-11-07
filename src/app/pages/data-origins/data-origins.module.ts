import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { DataOriginsPage } from './data-origins.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: DataOriginsPage }])],
  declarations: [DataOriginsPage],
})
export class DataOriginsPageModule {}
