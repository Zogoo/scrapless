import {
  Component,
  OnInit,
  computed,
  inject,
  signal,
  ChangeDetectionStrategy,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { DecimalPipe } from '@angular/common';
import { TranslatePipe } from '@ngx-translate/core';

import { FridgeService, kitchenShareUrl } from '../../core/services/fridge.service';
import { ActorService } from '../../core/services/actor.service';
import { CaptureService } from '../../core/services/capture.service';
import { InstallService } from '../../core/services/install.service';
import { LocaleService } from '../../core/services/locale.service';
import { PushService } from '../../core/services/push.service';
import { qrImageSrc } from '../../core/qr-image';
import {
  BROTBOX_CHOICES,
  COMMON_EXCLUSIONS,
  DIETS,
  Diet,
  brotboxChip,
  sameFood,
} from '../../core/food-settings';
import { CostReport } from '../../core/models';

@Component({
  selector: 'app-settings',
  imports: [FormsModule, DecimalPipe, TranslatePipe],
  templateUrl: './settings.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './settings.scss',
})
export class Settings implements OnInit {
  protected readonly fridge = inject(FridgeService);
  protected readonly actor = inject(ActorService);
  protected readonly install = inject(InstallService);
  protected readonly locale = inject(LocaleService);
  protected readonly push = inject(PushService);
  private readonly captures = inject(CaptureService);
  private readonly router = inject(Router);

  protected readonly name = signal('');
  protected readonly saved = signal(false);
  protected readonly actorName = signal('');
  protected readonly actorSaved = signal(false);
  protected readonly copied = signal(false);
  protected readonly costs = signal<CostReport | null>(null);
  protected readonly confirmingForget = signal(false);
  protected readonly brotboxChoices = BROTBOX_CHOICES;
  protected readonly diets = DIETS;
  protected readonly commonExclusions = COMMON_EXCLUSIONS;
  protected readonly exclusionDraft = signal('');
  protected readonly foodSaved = signal(false);
  private foodSavedTimer: ReturnType<typeof setTimeout> | null = null;

  protected readonly brotboxChosen = computed(() =>
    brotboxChip(this.fridge.fridge()?.brotbox_count),
  );
  private readonly excluded = computed(() => this.fridge.fridge()?.excluded_foods ?? []);
  /** What the household typed itself, shown as removable chips after the quick ones. */
  protected readonly ownExclusions = computed(() =>
    this.excluded().filter((food) => !COMMON_EXCLUSIONS.some((c) => sameFood(c.value, food))),
  );

  protected readonly shareLink = computed(() => {
    const code = this.fridge.fridge()?.join_code;
    return code ? kitchenShareUrl(location.origin, code) : '';
  });

  protected readonly qrSrc = computed(() => {
    const link = this.shareLink();
    return link ? qrImageSrc(link) : '';
  });

  ngOnInit(): void {
    this.name.set(this.fridge.fridge()?.name ?? '');
    this.actorName.set(this.actor.name());
    this.captures.costs().subscribe({ next: (report) => this.costs.set(report) });
  }

  protected rename(): void {
    const name = this.name().trim();
    if (!name) return;

    this.fridge.rename(name).subscribe({
      next: () => {
        this.saved.set(true);
        setTimeout(() => this.saved.set(false), 2000);
      },
    });
  }

  /** Each language named in itself, as language pickers do. */
  protected readonly languageNames: Record<string, string> = { en: 'English', de: 'Deutsch' };

  protected readonly previous = signal(this.fridge.previous());
  /** Why the switch did not happen, when it did not. */
  protected readonly switchNote = signal('');

  protected switchBack(): void {
    this.switchNote.set('');
    this.fridge.switchBack().subscribe({
      next: (fridge) => {
        if (fridge) {
          void this.router.navigate(['/today']);
          return;
        }
        // Forgotten from another phone: this one stays where it is.
        this.previous.set(null);
        this.switchNote.set('settings.switch_gone');
      },
      error: () => this.switchNote.set('settings.switch_failed'),
    });
  }

  protected chooseLocale(code: string): void {
    this.locale.use(code);
    this.fridge.setLocale(code).subscribe();
  }

  /** At most this many a week; the server enforces it, this only chooses it. */
  protected readonly budgets = [1, 2, 3];

  protected toggleNotifications(): void {
    // Straight from the tap: Safari only shows the prompt inside one.
    void (this.push.state() === 'on' ? this.push.disable() : this.push.enable());
  }

  /** Tapping the chosen count again clears it back to "not answered". */
  protected chooseBrotbox(count: number): void {
    this.saveFood({ brotbox_count: this.brotboxChosen() === count ? null : count });
  }

  protected chooseDiet(diet: Diet): void {
    this.saveFood({ diet });
  }

  protected isExcluded(food: string): boolean {
    return this.excluded().some((entry) => sameFood(entry, food));
  }

  protected toggleExclusion(food: string): void {
    const list = this.excluded();
    const next = this.isExcluded(food)
      ? list.filter((entry) => !sameFood(entry, food))
      : [...list, food];
    this.saveFood({ excluded_foods: next });
  }

  protected addExclusion(): void {
    const food = this.exclusionDraft().trim();
    if (!food) return;
    this.exclusionDraft.set('');
    if (!this.isExcluded(food)) this.saveFood({ excluded_foods: [...this.excluded(), food] });
  }

  private saveFood(changes: Parameters<FridgeService['setFoodSettings']>[0]): void {
    this.fridge.setFoodSettings(changes).subscribe({
      next: () => {
        this.foodSaved.set(true);
        if (this.foodSavedTimer !== null) clearTimeout(this.foodSavedTimer);
        this.foodSavedTimer = setTimeout(() => this.foodSaved.set(false), 2000);
      },
    });
  }

  protected chooseBudget(count: number): void {
    this.fridge.setAlertsPerWeek(count).subscribe();
  }

  protected saveActor(): void {
    this.actor.setName(this.actorName());
    this.actorSaved.set(true);
    setTimeout(() => this.actorSaved.set(false), 2000);
  }

  protected selectLink(event: Event): void {
    (event.target as HTMLInputElement).select();
  }

  protected async copyLink(link: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(link);
      this.copied.set(true);
      setTimeout(() => this.copied.set(false), 2000);
    } catch {
      this.copied.set(false);
    }
  }

  protected async installApp(): Promise<void> {
    await this.install.promptInstall();
  }

  /** Erasure is a plain delete: there is no immutable log to shred. */
  protected forget(): void {
    this.fridge.forget().subscribe({ next: () => void this.router.navigate(['/welcome']) });
  }

  /** Cost per capture, which is the number the whole model rests on. */
  protected costPerCapture(report: CostReport): number {
    const receipts = report.by_purpose.find((row) => row.purpose === 'receipt_extract');
    return receipts?.usd_per_call ?? 0;
  }
}
