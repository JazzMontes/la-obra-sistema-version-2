// Lo que comparten todas las pantallas: Angular básico, formularios, la estructura
// de Ionic que se usa (encabezado, contenido, menú y ventanas), iconos y formatos.
import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import {
  IonButtons,
  IonContent,
  IonHeader,
  IonMenuButton,
  IonModal,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar,
} from '@ionic/angular';
import { IconComponent } from './icon.component';
import { DateMxPipe, MoneyPipe, QtyPipe } from './format.pipes';
import { InputFormComponent } from './input-form.component';
import { PhotoPickerComponent } from './photo-picker.component';
import { ApiImageDirective } from './api-image.directive';

const IONIC = [IonButtons, IonContent, IonHeader, IonMenuButton, IonModal, IonRefresher, IonRefresherContent, IonTitle, IonToolbar];

@NgModule({
  declarations: [IconComponent, MoneyPipe, QtyPipe, DateMxPipe, InputFormComponent, PhotoPickerComponent, ApiImageDirective],
  imports: [CommonModule, FormsModule, RouterModule, ...IONIC],
  exports: [CommonModule, FormsModule, RouterModule, ...IONIC, IconComponent, MoneyPipe, QtyPipe, DateMxPipe, InputFormComponent, PhotoPickerComponent, ApiImageDirective],
})
export class SharedModule {}
