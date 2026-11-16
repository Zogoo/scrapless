import {
  Component,
  ElementRef,
  OnInit,
  computed,
  inject,
  signal,
  viewChild,
  ChangeDetectionStrategy,
} from '@angular/core';
import { Router } from '@angular/router';
import { forkJoin } from 'rxjs';
import { TranslatePipe } from '@ngx-translate/core';

import { ItemsService } from '../../core/services/items.service';
import { UndoService } from '../../core/services/undo.service';
import { Outcome, ScoredItem, Storage } from '../../core/models';
import {
  KitchenLine,
  levelFromPercent,
  levelPercent,
  toLines,
  trackBackground,
} from './kitchen-line';

/**
 * The full inventory, deliberately demoted to a tab you may visit twice a month.
 * Sorted by time left, never alphabetically: this is a triage queue, not a
 * database.
 */
@Component({
  selector: 'app-kitchen',
  imports: [TranslatePipe],
  templateUrl: './kitchen.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './kitchen.scss',
})
export class Kitchen implements OnInit {
  private readonly items = inject(ItemsService);
  private readonly router = inject(Router);
  private readonly undo = inject(UndoService);

  protected readonly loading = signal(true);
  protected readonly error = signal('');
  /** The food whose place is being changed, while the sheet is up. */
  protected readonly moving = signal<ScoredItem | null>(null);
  private readonly moveSheet = viewChild<ElementRef<HTMLDialogElement>>('moveSheet');
  protected readonly editingKey = signal<string | null>(null);
  protected readonly draftName = signal('');
  /** The line being dragged and where its thumb is, before the server agrees. */
  private readonly preview = signal<{ key: string; percent: number } | null>(null);
  /**
   * One drag. `dates` is the window before the first move. A release back at
   * the starting percent undoes the open, which writes that window back. An
   * already-open pack is not reopened: the drag may change its amount only.
   */
  private gesture: Gesture | null = null;
  /** The pack a slider move is already opening, so a drag does not ask twice. */
  private openingId: number | null = null;
  /** True while that open request is still out, so a cancel waits for it. */
  private openInFlight = false;
  private afterOpen: (() => void) | null = null;

  private readonly all = computed<ScoredItem[]>(() => {
    const today = this.items.today();
    return today ? [...today.use_first, ...today.fine_for_now] : [];
  });

  /** One line per food per place, however many packs of it there are. */
  protected readonly groups = computed(() => {
    const by: Record<Storage, KitchenLine[]> = { fridge: [], freezer: [], pantry: [] };
    for (const line of toLines(this.all())) by[line.first.storage].push(line);
    return by;
  });

  protected readonly storages: Storage[] = ['fridge', 'freezer', 'pantry'];

  protected capture(): void {
    void this.router.navigate(['/add']);
  }

  ngOnInit(): void {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.error.set(''); // a retry that works must not keep the old failure on screen
    this.items.load().subscribe({
      next: () => this.loading.set(false),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? '');
        this.loading.set(false);
      },
    });
  }

  protected jump(storage: Storage): void {
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    document
      .getElementById(`place-${storage}`)
      ?.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
  }

  protected startMove(item: ScoredItem): void {
    this.moving.set(item);
    this.moveSheet()?.nativeElement.showModal();
  }

  /** A tap on the dimmed page around the sheet is a "never mind". */
  protected closeOnBackdrop(event: MouseEvent): void {
    if (event.target === event.currentTarget) (event.currentTarget as HTMLDialogElement).close();
  }

  /** One tap in the sheet; the toast names the new place and can take it back. */
  protected move(item: ScoredItem, storage: Storage): void {
    this.moveSheet()?.nativeElement.close();
    this.items.move(item.id, storage).subscribe({
      next: () => {
        this.undo.showOutcome(item, 'moved', storage);
        this.load();
      },
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  protected startEdit(line: KitchenLine): void {
    this.editingKey.set(line.key);
    this.draftName.set(line.first.display_name);
  }

  /**
   * Correction must be cheaper than capture, so it is one field and one tap —
   * and it pays for itself, because the server feeds the change back into the
   * receipt dictionary.
   */
  protected saveEdit(line: KitchenLine): void {
    const name = this.draftName().trim();
    if (!name) return;

    // A rename is about the food, not one carton of it, so every pack follows.
    const changes = { display_name: name, canonical_name: name.toLowerCase() };
    forkJoin(line.packs.map((pack) => this.items.correct(pack.id, changes))).subscribe({
      next: () => {
        this.editingKey.set(null);
        this.load();
      },
      error: (err: { message?: string }) => this.error.set(err.message ?? ''),
    });
  }

  protected percent(line: KitchenLine): number {
    const preview = this.preview();
    return preview?.key === line.key
      ? preview.percent
      : levelPercent(line.level, line.packs.length);
  }

  protected level(line: KitchenLine): number {
    const preview = this.preview();
    return preview?.key === line.key
      ? levelFromPercent(preview.percent, line.packs.length)
      : line.level;
  }

  protected track(line: KitchenLine): string {
    return trackBackground(line, this.level(line));
  }

  /** The thumb went down. Nothing is opened until the percent actually changes. */
  protected beginGesture(line: KitchenLine): void {
    if (this.gesture?.key === line.key) return;

    const pack = line.first;
    this.gesture = {
      key: line.key,
      packId: pack.id,
      startPercent: levelPercent(line.level, line.packs.length),
      dates: {
        window_start: pack.window_start,
        window_end: pack.window_end,
        opened_on: pack.opened_on,
      },
      openSent: false,
    };
  }

  /**
   * The first move off the starting percent opens the soonest pack, unless it
   * was already open. Resolve keeps the dates from just before that move.
   */
  private openOnFirstMove(line: KitchenLine): void {
    const gesture = this.gesture;
    const pack = line.first;
    // dates.opened_on is the window from before this drag. An open that was
    // already there is left alone; only the amount may change.
    if (!gesture || gesture.dates.opened_on || gesture.openSent || pack.id !== gesture.packId) {
      return;
    }
    if (pack.opened_on || this.openingId === pack.id) return;

    gesture.openSent = true;
    this.openingId = pack.id;
    this.openInFlight = true;
    this.items.resolve(pack.id, 'opened').subscribe({
      next: () => this.settleOpen(),
      error: () => {
        gesture.openSent = false;
        if (this.openingId === pack.id) this.openingId = null;
        this.settleOpen();
      },
    });
  }

  private settleOpen(): void {
    this.openInFlight = false;
    const resume = this.afterOpen;
    this.afterOpen = null;
    resume?.();
  }

  protected slide(line: KitchenLine, event: Event): void {
    this.beginGesture(line);
    const percent = Number((event.target as HTMLInputElement).value);
    this.preview.set({ key: line.key, percent });
    if (this.gesture && percent !== this.gesture.startPercent) this.openOnFirstMove(line);
  }

  /**
   * Committed on release. Back at the starting percent, the open is taken
   * back: the remembered dates return and opened clears. A new percent keeps
   * the open and writes the amount. 0% still uses the line.
   */
  protected commitLevel(line: KitchenLine, event: Event): void {
    this.beginGesture(line);
    const percent = Number((event.target as HTMLInputElement).value);
    const gesture = this.gesture;
    if (!gesture) return;

    if (percent !== gesture.startPercent) this.openOnFirstMove(line);
    this.gesture = null;

    if (percent === gesture.startPercent) {
      this.preview.set(null);
      this.restoreIfCancelled(gesture);
      return;
    }

    this.setLevel(line, levelFromPercent(percent, line.packs.length));
  }

  /** Undo writes back the window Resolve stored before the first move. */
  private restoreIfCancelled(gesture: Gesture): void {
    const run = () => {
      if (!gesture.openSent) return;

      this.items.undo(gesture.packId).subscribe({
        next: () =>
          this.items.load().subscribe({
            next: () => {
              this.preview.set(null);
              this.openingId = null;
            },
          }),
        error: (err: { message?: string }) => this.fail(err),
      });
    };

    if (this.openInFlight) this.afterOpen = run;
    else run();
  }

  private setLevel(line: KitchenLine, level: number): void {
    const ids = line.packs.map((pack) => pack.id);
    this.preview.set({ key: line.key, percent: levelPercent(level, line.packs.length) });

    this.items.level(ids, level).subscribe({
      next: () =>
        this.items.load().subscribe({
          next: () => {
            this.preview.set(null);
            this.openingId = null;
          },
        }),
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  protected resolve(item: ScoredItem, outcome: Outcome): void {
    this.items.resolve(item.id, outcome).subscribe({
      next: () => {
        this.undo.showOutcome(item, outcome);
        this.load();
      },
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  /** For a line read wrong, not eaten or binned: it is not waste, so it is deleted. */
  protected removeLine(line: KitchenLine): void {
    forkJoin(line.packs.map((pack) => this.items.remove(pack.id))).subscribe({
      next: () => {
        this.editingKey.set(null);
        this.load();
      },
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  /** Say what went wrong, then show what is true now — another phone may have won. */
  private fail(err: { message?: string }): void {
    this.preview.set(null);
    this.openingId = null;
    this.load();
    this.error.set(err.message ?? '');
  }
}

/** Dates from before a drag's first move. Undo puts these back if it is cancelled. */
interface Gesture {
  key: string;
  packId: number;
  startPercent: number;
  dates: {
    window_start: string;
    window_end: string;
    opened_on: string | null;
  };
  openSent: boolean;
}
