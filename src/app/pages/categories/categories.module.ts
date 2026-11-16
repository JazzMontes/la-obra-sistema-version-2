import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { CategoriesPage } from './categories.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: CategoriesPage }])],
  declarations: [CategoriesPage],
})
export class CategoriesPageModule {}
