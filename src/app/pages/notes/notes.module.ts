import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { NotesPage } from './notes.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: NotesPage }])],
  declarations: [NotesPage],
})
export class NotesPageModule {}
