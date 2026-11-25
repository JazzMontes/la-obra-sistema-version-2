import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { NotesPage } from './notes.page';
import { ErrandsComponent } from './errands.component';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: NotesPage }])],
  declarations: [NotesPage, ErrandsComponent],
})
export class NotesPageModule {}
