import { Component, OnInit, inject, signal, ChangeDetectionStrategy } from '@angular/core';
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
  changeDetection: ChangeDetectionStrategy.Eager,
  template: `
    <div class="join">
      <div class="hero">
        <img
          class="mark"
          src="/branding/rettich/app-icon/favicon.svg"
          alt=""
          width="56"
          height="56"
        />
        <h1>
          @if (already) {
            {{ kitchenName() }}
          } @else if (kitchenName(); as name) {
            {{ 'join.title_named' | translate: { name } }}
          } @else {
            {{ 'join.title' | translate }}
          }
        </h1>
        @if (!already) {
          <p class="lede">{{ 'join.lede' | translate }}</p>
        }
      </div>

      @if (already) {
        <p class="lede">{{ 'join.already' | translate: { name: kitchenName() } }}</p>
      } @else if (switching) {
        <p class="lede">{{ 'join.switch' | translate }}</p>
      }

      @if (!code) {
        <p class="error">{{ 'join.invalid' | translate }}</p>
      } @else if (error()) {
        <p class="error">{{ error() }}</p>
      }

      @if (already) {
        <button type="button" class="primary" (click)="home()">
          {{ 'join.go_home' | translate }}
        </button>
      } @else if (kitchenName()) {
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
  /** The link to the kitchen this phone is already in: nothing to switch. */
  protected readonly already = !!this.code && this.fridge.fridge()?.join_code === this.code;
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

  protected home(): void {
    void this.router.navigate(['/today']);
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
