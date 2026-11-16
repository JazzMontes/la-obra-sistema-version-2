import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { SharedModule } from '../../shared/shared.module';
import { StudentValidationPage } from './student-validation.page';

@NgModule({
  imports: [SharedModule, RouterModule.forChild([{ path: '', component: StudentValidationPage }])],
  declarations: [StudentValidationPage],
})
export class StudentValidationPageModule {}
