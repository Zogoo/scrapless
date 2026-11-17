import { Injectable, inject, signal } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';
import { switchMap } from 'rxjs';

import { Outcome, ScoredItem, Storage } from '../models';

import { ItemsService } from './items.service';

/** What the toast shows: a sentence, and the food it can take back, if any. */
export interface Notice {
  message: string;
  itemId?: number;
}

/**
 * The toast after a one-tap outcome: it says what happened ("Danke — notiert",
 * doc 4 §4.13) and offers to take it back. Today and the Kitchen reorder
 * themselves after every tap, so the next tap can land on a different food;
 * without this, that mistake was permanent.
 *
 * Every notice goes by itself after SHOW_MS, so it never sits over the list.
 * The timer stops while a finger, pointer or keyboard focus is on the toast
 * (`hold`) and starts again in full when it leaves (`release`): an Undo that
 * runs away from someone reaching for it is one they can never use
 * (WCAG 2.2.1).
 */
@Injectable({ providedIn: 'root' })
export class UndoService {
  static readonly SHOW_MS = 5000;

  private readonly items = inject(ItemsService);
  private readonly translate = inject(TranslateService);
  private timer: ReturnType<typeof setTimeout> | null = null;

  readonly notice = signal<Notice | null>(null);

  show(notice: Notice): void {
    this.clearTimer();
    this.notice.set(notice);
    this.release();
  }

  /** Someone is on the toast: keep it until they leave. */
  hold(): void {
    this.clearTimer();
  }

  /** They left: give them the whole time again. */
  release(): void {
    this.clearTimer();
    if (this.notice() !== null) {
      this.timer = setTimeout(() => this.notice.set(null), UndoService.SHOW_MS);
    }
  }

  dismiss(): void {
    this.clearTimer();
    this.notice.set(null);
  }

  /** "Broccoli: used", "Brot ist jetzt im Vorrat" — after any one-tap outcome. */
  showOutcome(item: ScoredItem, outcome: Outcome, place?: Storage): void {
    const message = this.translate.instant(`undo.${outcome}`, {
      name: item.display_name,
      place: place ? this.translate.instant(`storage.${place}`) : '',
    });
    this.show({ itemId: item.id, message });
  }

  undo(): void {
    const id = this.notice()?.itemId;
    if (id === undefined) return;

    this.dismiss();
    this.items
      .undo(id)
      .pipe(switchMap(() => this.items.load()))
      .subscribe({
        error: (err: { message?: string }) => this.show({ message: err.message ?? '' }),
      });
  }

  private clearTimer(): void {
    if (this.timer !== null) clearTimeout(this.timer);
    this.timer = null;
  }
}
