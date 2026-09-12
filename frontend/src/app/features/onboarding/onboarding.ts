import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';

import { FridgeService } from '../../core/services/fridge.service';

/**
 * The whole account system, in one question you are allowed to ignore.
 *
 * Doc 2 §2.7: no account wall before value, and the onboarding budget is 180
 * seconds with zero required typing. So there is one optional field and a Skip
 * that is exactly as prominent as the confirm — because most people will skip,
 * and making them feel they got it wrong is a bad first second.
 */
@Component({
  selector: 'app-onboarding',
  imports: [FormsModule, TranslatePipe],
  styleUrl: './onboarding.scss',
  template: `
    <div class="onboarding">
      <div class="hero">
        <span class="mark" aria-hidden="true">🧊</span>
        <h1>{{ 'onboarding.title' | translate }}</h1>
        <p class="lede">{{ 'onboarding.lede' | translate }}</p>
      </div>

      <label class="field">
        <span>{{ 'onboarding.question' | translate }}</span>
        <input
          type="text"
          name="name"
          autocomplete="off"
          enterkeyhint="go"
          maxlength="60"
          [placeholder]="'onboarding.placeholder' | translate"
          [(ngModel)]="name"
          (keyup.enter)="start()"
        />
      </label>

      @if (error()) {
        <p class="error">{{ error() }}</p>
      }

      <div class="actions">
        <button type="button" class="primary" [disabled]="busy()" (click)="start()">
          {{ (name.trim() ? 'onboarding.name_it' : 'onboarding.skip') | translate }}
        </button>
      </div>

      <p class="footnote">{{ 'onboarding.footnote' | translate }}</p>
    </div>
  `,
})
export class Onboarding {
  private readonly fridge = inject(FridgeService);
  private readonly router = inject(Router);

  protected name = '';
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected start(): void {
    if (this.busy()) return;

    this.busy.set(true);
    this.error.set('');

    this.fridge.create(this.name).subscribe({
      next: () => void this.router.navigate(['/today']),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? 'That did not go through.');
        this.busy.set(false);
      },
    });
  }
}
