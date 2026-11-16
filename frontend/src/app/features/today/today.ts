import {
  Component,
  DestroyRef,
  OnInit,
  computed,
  inject,
  signal,
  ChangeDetectionStrategy,
} from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { ItemsService } from '../../core/services/items.service';
import { InstallService } from '../../core/services/install.service';
import { LocaleService } from '../../core/services/locale.service';
import { NotificationsService } from '../../core/services/notifications.service';
import { ScoredItem } from '../../core/models';
import { ItemLine } from '../../shared/item-line/item-line';
import { lineFor } from '../../shared/item-line/line';

/**
 * The product. Answers exactly one question: what should I do about food today?
 *
 * Everything here is shaped by the 5-second glance budget in doc 2 §2.2 — three
 * cards at most. Those cards are the Kitchen line. The fine-for-now list and
 * the probably-gone note stay as they are.
 */
@Component({
  selector: 'app-today',
  imports: [TranslatePipe, ItemLine],
  templateUrl: './today.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './today.scss',
})
export class Today implements OnInit {
  private readonly items = inject(ItemsService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly notifications = inject(NotificationsService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly translate = inject(TranslateService);
  private readonly locale = inject(LocaleService);
  protected readonly install = inject(InstallService);

  protected readonly today = this.items.today;
  protected readonly loading = signal(true);
  /** "Sonntag", not "Sunday": DatePipe only knows the build's locale, not the app's. */
  protected readonly weekday = computed(() => {
    const day = this.today()?.as_of;
    return day
      ? new Date(`${day}T12:00:00`).toLocaleDateString(this.locale.current(), { weekday: 'long' })
      : '';
  });
  protected readonly error = signal('');
  protected readonly expandRest = signal(false);
  /** The filter already picked this pack. It is not grouped with its siblings. */
  protected readonly lineFor = lineFor;
  /** The foods the notification that opened this page was about. */
  protected readonly picked = signal<number[]>([]);

  protected readonly isEmpty = computed(() => {
    const today = this.today();
    return (
      !!today &&
      today.use_first.length === 0 &&
      today.fine_for_now.length === 0 &&
      today.probably_gone.length === 0
    );
  });

  /** True when there is food, and none of it needs anything. The good state. */
  protected readonly allCalm = computed(() => {
    const today = this.today();
    return !!today && today.use_first.length === 0 && today.fine_for_now.length > 0;
  });

  ngOnInit(): void {
    this.load();
    // Not the snapshot: tapping a notification in the bell while already on
    // Today reuses this page and only changes the query.
    this.route.queryParamMap
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((params) => void this.openNotification(params.get('n')));
  }

  /**
   * A tapped notification opens /today?n=<id>, from the lock screen or the bell:
   * count it read for the kitchen, point at its food, then drop the id.
   */
  private async openNotification(id: string | null): Promise<void> {
    if (!id || !/^\d+$/.test(id)) return;

    void this.router.navigate([], { relativeTo: this.route, queryParams: {}, replaceUrl: true });
    const n = Number(id);
    this.notifications.read(n);
    if (!this.notifications.find(n)) await this.notifications.load();
    this.picked.set(this.notifications.find(n)?.item_ids ?? []);
    this.scrollToPicked();
  }

  /** Once both the page and the notification are in, bring its first food into view. */
  private scrollToPicked(): void {
    const first = this.picked()[0];
    if (first === undefined || !this.today()) return;
    setTimeout(() =>
      document
        .getElementById(`line-${first}`)
        ?.scrollIntoView({ block: 'center', behavior: 'smooth' }),
    );
  }

  protected load(): void {
    this.loading.set(true);
    this.error.set(''); // a retry that works must not keep the old failure on screen
    this.items.load().subscribe({
      next: () => {
        this.loading.set(false);
        this.scrollToPicked();
      },
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? this.translate.instant('errors.generic'));
        this.loading.set(false);
      },
    });
  }

  protected capture(): void {
    void this.router.navigate(['/add']);
  }

  protected async installApp(): Promise<void> {
    await this.install.promptInstall();
  }

  /** Width of the decay bar. Position is the primary channel, not colour. */
  protected barWidth(item: ScoredItem): string {
    return `${Math.min(100, Math.round(item.life_fraction * 100))}%`;
  }
}
