import { Component, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { FridgeService, joinCodeFromLocation } from '../../core/services/fridge.service';

/**
 * The other phone. One button, then this browser holds the shared kitchen the
 * same way a kitchen it created itself is held: token in localStorage, cookie
 * from the server.
 */
@Component({
  selector: 'app-join',
  imports: [TranslatePipe],
  styleUrl: './join.scss',
  template: `
    <div class="join">
      <div class="hero">
        <span class="mark" aria-hidden="true">🧊</span>
        <h1>
          @if (kitchenName(); as name) {
            {{ 'join.title_named' | translate: { name } }}
          } @else {
            {{ 'join.title' | translate }}
          }
        </h1>
        <p class="lede">{{ 'join.lede' | translate }}</p>
      </div>

      @if (switching) {
        <p class="lede">{{ 'join.switch' | translate }}</p>
      }

      @if (!code) {
        <p class="error">{{ 'join.invalid' | translate }}</p>
      } @else if (error()) {
        <p class="error">{{ error() }}</p>
      }

      @if (kitchenName()) {
        <button type="button" class="primary" [disabled]="busy()" (click)="open()">
          {{ (busy() ? 'join.opening' : 'join.open') | translate }}
        </button>
      }
    </div>
  `,
})
export class Join implements OnInit {
  private readonly fridge = inject(FridgeService);
  private readonly router = inject(Router);
  private readonly translate = inject(TranslateService);
  private readonly route = inject(ActivatedRoute);

  protected readonly code = joinCodeFromLocation(
    this.route.snapshot.fragment,
    typeof location === 'undefined' ? '' : location.hash,
  );
  protected readonly switching = this.fridge.isKnown();
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  /** Known only once the server recognised the code; until then, no button. */
  protected readonly kitchenName = signal('');

  ngOnInit(): void {
    if (!this.code) return;

    this.fridge.preview(this.code).subscribe({
      next: ({ name }) => this.kitchenName.set(name),
      error: (err: { status?: number }) => this.failed(err),
    });
  }

  protected open(): void {
    if (!this.code || this.busy()) return;

    this.busy.set(true);
    this.error.set('');

    this.fridge.join(this.code).subscribe({
      next: () => void this.router.navigate(['/today']),
      error: (err: { status?: number }) => {
        this.failed(err);
        this.busy.set(false);
      },
    });
  }

  private failed(err: { status?: number }): void {
    const key = err.status === 429 ? 'join.too_many' : 'join.invalid';
    this.error.set(this.translate.instant(key));
  }
}
