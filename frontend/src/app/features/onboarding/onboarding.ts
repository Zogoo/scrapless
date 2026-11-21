import { Component, inject, signal, ChangeDetectionStrategy } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { BROTBOX_CHOICES } from '../../core/food-settings';
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
  changeDetection: ChangeDetectionStrategy.Eager,
  template: `
    <div class="onboarding">
      <div class="hero">
        <h1 class="logo-heading">
          <picture>
            <source
              srcset="/branding/rettich/logo/rettich-logo-dark.svg"
              media="(prefers-color-scheme: dark)"
            />
            <img
              src="/branding/rettich/logo/rettich-logo-light.svg"
              [attr.alt]="'brand.name' | translate"
              width="352"
              height="123"
            />
          </picture>
        </h1>
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

      <!-- Optional, like the name: nothing is preselected, tapping the chosen
           chip again unchooses it, and the one button below is still the way on. -->
      <div class="brotbox">
        <p id="brotbox-head">{{ 'food.brotbox_question' | translate }}</p>
        <div class="choices" role="group" aria-labelledby="brotbox-head">
          @for (count of brotboxChoices; track count) {
            <button
              type="button"
              [class.primary]="brotboxCount() === count"
              [attr.aria-pressed]="brotboxCount() === count"
              (click)="pickBrotbox(count)"
            >
              {{ 'food.brotbox_' + count | translate }}
            </button>
          }
        </div>
      </div>

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
  private readonly translate = inject(TranslateService);

  protected name = '';
  protected readonly brotboxChoices = BROTBOX_CHOICES;
  /** null: not answered, which is what skipping means. */
  protected readonly brotboxCount = signal<number | null>(null);
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected pickBrotbox(count: number): void {
    this.brotboxCount.set(this.brotboxCount() === count ? null : count);
  }

  protected start(): void {
    if (this.busy()) return;

    this.busy.set(true);
    this.error.set('');

    this.fridge.create(this.name, this.brotboxCount()).subscribe({
      next: () => void this.router.navigate(['/today']),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? this.translate.instant('errors.generic'));
        this.busy.set(false);
      },
    });
  }
}
