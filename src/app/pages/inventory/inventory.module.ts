import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { InventoryPage } from './inventory.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: InventoryPage }])],
  declarations: [InventoryPage],
})
export class InventoryPageModule {}
