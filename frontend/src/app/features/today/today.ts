import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { ItemsService } from '../../core/services/items.service';
import { InstallService } from '../../core/services/install.service';
import { UndoService } from '../../core/services/undo.service';
import { LocaleService } from '../../core/services/locale.service';
import { Outcome, ScoredItem } from '../../core/models';

/**
 * The product. Answers exactly one question: what should I do about food today?
 *
 * Everything here is shaped by the 5-second glance budget in doc 2 §2.2 — three
 * cards at most, the decay read from a bar rather than a colour, and both
 * actions inside thumb reach.
 */
@Component({
  selector: 'app-today',
  imports: [TranslatePipe],
  templateUrl: './today.html',
  styleUrl: './today.scss',
})
export class Today implements OnInit {
  private readonly items = inject(ItemsService);
  private readonly router = inject(Router);
  private readonly undo = inject(UndoService);
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
  protected readonly busyId = signal<number | null>(null);

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
  }

  protected load(): void {
    this.loading.set(true);
    this.error.set(''); // a retry that works must not keep the old failure on screen
    this.items.load().subscribe({
      next: () => this.loading.set(false),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? this.translate.instant('errors.generic'));
        this.loading.set(false);
      },
    });
  }

  protected resolve(item: ScoredItem, outcome: Outcome): void {
    this.busyId.set(item.id);
    this.items.resolve(item.id, outcome).subscribe({
      next: () => {
        this.busyId.set(null);
        this.undo.showOutcome(item, outcome);
        this.load();
      },
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? this.translate.instant('errors.generic'));
        this.busyId.set(null);
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
