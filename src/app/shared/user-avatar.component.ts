// Foto de perfil de un usuario; si no tiene foto (o no carga) muestra sus iniciales.
// <app-user-avatar [user]="u" class="avatar avatar-sm"></app-user-avatar>
import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { autoRefresh } from '../services/render';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  selector: 'app-user-avatar',
  template: `
    <img *ngIf="user?.avatar_path && failed !== user?.avatar_path" [apiSrc]="user.avatar_path" [alt]="user?.name || 'Foto de perfil'" (error)="failed = user?.avatar_path" />
    <ng-container *ngIf="!user?.avatar_path || failed === user?.avatar_path">{{ initials }}</ng-container>
  `,
  standalone: false,
})
export class UserAvatarComponent {
  private readonly refresher = autoRefresh();

  @Input() user: any = null;
  failed: string | null = null;

  get initials(): string {
    return String(this.user?.name || '?').split(/\s+/).filter(Boolean).map((w: string) => w[0]).slice(0, 2).join('');
  }
}
