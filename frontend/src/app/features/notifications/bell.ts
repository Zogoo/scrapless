import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { NavigationStart, Router } from '@angular/router';
import { filter } from 'rxjs/operators';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { InboxEntry, NotificationsService } from '../../core/services/notifications.service';
import { PushService } from '../../core/services/push.service';
import { LocaleService } from '../../core/services/locale.service';

/**
 * The bell in the app bar: the kitchen's notifications, for every phone,
 * whether or not it allowed push. The number counts the ones nobody has read
 * that are still about food to use — never food already gone.
 */
@Component({
  selector: 'app-bell',
  imports: [TranslatePipe],
  templateUrl: './bell.html',
  styleUrl: './bell.scss',
  changeDetection: ChangeDetectionStrategy.Eager,
  host: { '(document:keydown.escape)': 'close()', '[class.bell-open]': 'open()' },
})
export class Bell {
  protected readonly notifications = inject(NotificationsService);
  protected readonly push = inject(PushService);
  private readonly router = inject(Router);
  private readonly locale = inject(LocaleService);
  private readonly translate = inject(TranslateService);

  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  protected readonly open = signal(false);

  constructor() {
    // Back, a tab, a link: the panel belongs to the page it was opened on.
    this.router.events
      .pipe(
        filter((event) => event instanceof NavigationStart),
        takeUntilDestroyed(inject(DestroyRef)),
      )
      .subscribe(() => this.open.set(false));
  }

  protected toggle(): void {
    this.open.update((open) => !open);
    if (!this.open()) return;

    void this.notifications.load();
    // Into the panel, so a keyboard or screen reader lands where the list is.
    setTimeout(() => this.host.nativeElement.querySelector<HTMLElement>('#bell-panel')?.focus());
  }

  protected close(): void {
    if (!this.open()) return;
    this.open.set(false);
    this.host.nativeElement.querySelector<HTMLElement>('button.bell')?.focus();
  }

  protected choose(entry: InboxEntry): void {
    this.open.set(false);
    // Today marks it read when it opens, as it does for a tap on the lock screen.
    void this.router.navigateByUrl(entry.url);
  }

  protected turnOnPush(): void {
    // Straight from the tap: Safari only shows the prompt inside one.
    void this.push.enable();
  }

  /** "Today", "Yesterday", then the weekday: the bell holds two weeks. */
  protected when(entry: InboxEntry): string {
    const day = new Date(`${entry.sent_on}T12:00:00`);
    const today = new Date();
    today.setHours(12, 0, 0, 0);
    const daysAgo = Math.round((today.getTime() - day.getTime()) / 86_400_000);
    if (daysAgo <= 0) return this.translate.instant('bell.today');
    if (daysAgo === 1) return this.translate.instant('bell.yesterday');
    return day.toLocaleDateString(this.locale.current(), {
      weekday: 'long',
      ...(daysAgo >= 7 ? { day: 'numeric', month: 'short' } : {}),
    });
  }
}
