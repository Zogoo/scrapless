import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  effect,
  inject,
  input,
  output,
  signal,
  viewChild,
} from '@angular/core';
import { TranslatePipe } from '@ngx-translate/core';

import { Outcome, ScoredItem, Storage } from '../../core/models';
import { ItemsService } from '../../core/services/items.service';
import { UndoService } from '../../core/services/undo.service';
import {
  KitchenLine,
  TrackDraw,
  levelFromPercent,
  levelPercent,
  packAmount,
  stepLevel,
  trackBars,
} from './line';

/**
 * One food line: the percentage slider, Move, and Gone.
 *
 * Kitchen groups every pack of a food into the line it passes in. Home passes
 * the single pack its filter already chose. The slider behaviour is the same
 * either way.
 */
@Component({
  selector: 'app-item-line',
  imports: [TranslatePipe],
  templateUrl: './item-line.html',
  styleUrl: './item-line.scss',
  changeDetection: ChangeDetectionStrategy.Eager,
  host: {
    class: 'card',
    '[class.high-risk]': 'line().first.high_risk',
  },
})
export class ItemLine {
  readonly line = input.required<KitchenLine>();
  /** Kitchen renames from the name. Home does not. */
  readonly renamable = input(false);
  readonly rename = output<void>();
  readonly failed = output<string>();

  private readonly items = inject(ItemsService);
  private readonly undo = inject(UndoService);

  protected readonly moving = signal<ScoredItem | null>(null);
  /**
   * Set when a release undoes an open this slider made, so the pack is
   * unopened again. That includes an open already saved earlier in the sitting.
   */
  protected readonly accidental = signal(false);
  private readonly moveSheet = viewChild<ElementRef<HTMLDialogElement>>('moveSheet');
  private readonly preview = signal<{ key: string; percent: number } | null>(null);
  /**
   * One drag. `dates` is the window before the first move. Releasing at the
   * percent that opened the pack undoes that open, including one already
   * saved. A pack that was open before this drag only changes its amount.
   */
  private gesture: Gesture | null = null;
  private openingId: number | null = null;
  private openInFlight = false;
  private afterOpen: (() => void) | null = null;
  /**
   * What this sitting has decided, and the `opened_on` on the line at that
   * moment. Once the list's date moves on, the latch is dropped: a restored
   * unopened pack closes the radish.
   */
  private readonly openedNow = signal<{
    id: number;
    open: boolean;
    seen: string | null;
  } | null>(null);

  constructor() {
    // The list caught up, or caught up and was restored. Either way the latch
    // was about an older date, so it must not keep the bitten face.
    effect(() => {
      const pack = this.line().first;
      const now = this.openedNow();
      if (!now || now.id !== pack.id || pack.opened_on === now.seen) return;
      this.openedNow.set(null);
    });
  }

  protected readonly storages: Storage[] = ['fridge', 'freezer', 'pantry'];

  /** Ignores a second commit of the same stop, from keyup and change together. */
  private lastCommit: number | null = null;

  /** The bars, in packs: "2", "¼", "1½". The translation adds Pck. / pk. */
  protected packsLabel(): string {
    return packAmount(levelFromPercent(this.percent(), this.line().packs.length));
  }

  protected percent(): number {
    const line = this.line();
    const preview = this.preview();
    return preview?.key === line.key
      ? preview.percent
      : levelPercent(line.level, line.packs.length);
  }

  protected level(): number {
    const line = this.line();
    const preview = this.preview();
    return preview?.key === line.key
      ? levelFromPercent(preview.percent, line.packs.length)
      : line.level;
  }

  protected bars(): TrackDraw {
    return trackBars(this.line(), this.level());
  }

  /**
   * Where the thumb sits. A full line stays at the end. A partial line centers
   * on the bar. Nothing left leaves the thumb empty.
   */
  protected bites(): number {
    if (!this.opened()) return 0;
    const left = this.level();
    if (left <= 0) return 4;
    if (left >= this.line().packs.length) return 0;
    return 1;
  }

  /**
   * The thumb. Unopened is the whole radish, opened is the bitten one.
   * Freshness is the bar against the thumb: fresh, aging, then at risk or ghost.
   * Light and dark each have their own file. 0% has nothing to hold.
   */
  protected radishSrc(): { light: string; dark: string } | null {
    if (this.level() <= 0) return null;

    const bars = this.bars().bars;
    const phase = bars.length > 0 ? bars[bars.length - 1].phase : this.line().first.phase;
    const kind = phase === 'aging' ? 'soon' : phase === 'fresh' ? 'fresh' : 'today';
    const bitten = this.opened() ? '-opened' : '';
    const base = `/branding/rettich/mascot/rettich-${kind}${bitten}`;
    return { light: `${base}-light.svg`, dark: `${base}.svg` };
  }

  /** Closed until this slider opens the soonest pack. An undone open closes it. */
  protected opened(): boolean {
    const pack = this.line().first;
    const now = this.openedNow();
    const gesture = this.gesture;
    const preview = this.preview();
    // Back at the percent that opened it, the mouth closes before the reply.
    if (
      gesture?.openSent &&
      preview?.key === gesture.key &&
      preview.percent === gesture.startPercent
    ) {
      return false;
    }
    // Same date we latched against: the sitting still knows better than the line.
    // A newer date — the list came back unopened — is a closed radish.
    if (now && now.id === pack.id && pack.opened_on === now.seen) return now.open;
    return pack.opened_on != null;
  }

  /** Remember an open or a shut, against the date the line is showing now. */
  private rememberOpen(id: number, open: boolean): void {
    const pack = this.line().packs.find((item) => item.id === id) ?? this.line().first;
    this.openedNow.set({ id, open, seen: pack.opened_on });
  }

  /** The thumb went down. Nothing is opened until the percent actually changes. */
  protected beginGesture(): void {
    const line = this.line();
    if (this.gesture?.key === line.key) return;

    const pack = line.first;
    this.accidental.set(false);
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
   * was already open. The server keeps the dates from just before that move
   * and only shortens them when the opened life is sooner.
   */
  private openOnFirstMove(): void {
    const gesture = this.gesture;
    const pack = this.line().first;
    if (!gesture || gesture.dates.opened_on || gesture.openSent || pack.id !== gesture.packId) {
      return;
    }
    if (pack.opened_on || this.openingId === pack.id) return;

    gesture.openSent = true;
    this.openingId = pack.id;
    this.rememberOpen(pack.id, true);
    this.openInFlight = true;
    this.items.openFromSlider(pack.id, gesture.startPercent).subscribe({
      next: () => this.settleOpen(),
      error: () => {
        gesture.openSent = false;
        if (this.openingId === pack.id) this.openingId = null;
        this.rememberOpen(pack.id, false);
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

  /** Arrow keys move one stop. The pointer still lands on the nearest stop. */
  protected nudge(event: KeyboardEvent): void {
    const direction = nudgeDirection(event.key);
    if (direction === 0) return;

    event.preventDefault();
    const count = this.line().packs.length;
    const percent = levelPercent(stepLevel(this.level(), count, direction), count);
    (event.target as HTMLInputElement).value = String(percent);
    this.slide(event);
  }

  protected releaseNudge(event: KeyboardEvent): void {
    if (nudgeDirection(event.key) === 0) return;
    this.commitLevel(event);
  }

  protected slide(event: Event): void {
    this.beginGesture();
    const percent = this.percentFromPointer(event);
    if (percent !== this.lastCommit) this.lastCommit = null;
    this.preview.set({ key: this.line().key, percent });
    if (this.gesture && percent !== this.gesture.startPercent) this.openOnFirstMove();
  }

  /**
   * Committed on release. If this slider is what opened the pack, releasing
   * at the percent that drag started from undoes the open, even when it was
   * already saved. Any other percent keeps the open and writes the amount.
   * A pack that was already open only changes its amount. 0% still uses the line.
   */
  protected commitLevel(event: Event): void {
    const percent = this.percentFromPointer(event);
    if (percent === this.lastCommit) return;
    this.lastCommit = percent;

    this.beginGesture();
    const gesture = this.gesture;
    if (!gesture) return;

    if (percent !== gesture.startPercent) this.openOnFirstMove();
    if (gesture.openSent && percent === gesture.startPercent) {
      this.rememberOpen(gesture.packId, false);
    }
    this.gesture = null;

    if (percent === gesture.startPercent) this.preview.set(null);
    // 0% has used the line. Take the card off the shared list now, before the
    // reply: a 0% preview is an empty card, and Home and the Kitchen both draw
    // this list. The toast puts the packs back.
    if (
      percent !== gesture.startPercent &&
      levelFromPercent(percent, this.line().packs.length) <= 0
    ) {
      this.useUp();
    }

    const run = () => this.finishRelease(gesture, percent);
    if (this.openInFlight) this.afterOpen = run;
    else run();
  }

  /**
   * Asks the server whenever the pack is open. The server puts the window
   * back only when this percent is the one that opened it. The amount is
   * written after that, so the two updates do not land on the row together.
   */
  private finishRelease(gesture: Gesture, percent: number): void {
    const opened = gesture.openSent || gesture.dates.opened_on != null;
    const writeAmount = () => {
      if (percent === gesture.startPercent) {
        this.preview.set(null);
        this.openingId = null;
        // The open was taken back, so the line has to be read again. A release
        // that never opened anything has nothing new to read.
        if (opened) this.items.load().subscribe();
        return;
      }

      this.setLevel(levelFromPercent(percent, this.line().packs.length));
    };

    if (!opened) {
      writeAmount();
      return;
    }

    this.items.revertSliderOpen(gesture.packId, percent).subscribe({
      next: (item) => {
        // The server clears opened_on only when this slider is what opened the
        // pack. A later release in the same sitting counts: the open is already
        // saved, so this drag did not send it. A pack that was open beforehand
        // comes back still open, and stays quiet.
        if (item.opened_on == null) {
          this.accidental.set(true);
          this.rememberOpen(gesture.packId, false);
        } else {
          this.rememberOpen(gesture.packId, true);
        }
        writeAmount();
      },
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  /** Every pack on the line is used. The card leaves both screens with the toast. */
  private useUp(): void {
    const ids = this.line().packs.map((pack) => pack.id);
    this.preview.set(null);
    this.undo.showUsedUp(ids);
    this.items.removeFromList(ids);
  }

  private setLevel(level: number): void {
    const line = this.line();
    const ids = line.packs.map((pack) => pack.id);
    // A used line is already off the list. Leaving the preview at 0% would
    // paint that same card empty if it were still here.
    if (level > 0) {
      this.preview.set({ key: line.key, percent: levelPercent(level, line.packs.length) });
    } else {
      this.preview.set(null);
    }

    this.items.level(ids, level).subscribe({
      next: () => {
        this.items.load().subscribe({
          next: () => {
            this.preview.set(null);
            this.openingId = null;
            this.lastCommit = null;
          },
        });
      },
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  protected startMove(item: ScoredItem): void {
    this.moving.set(item);
    this.moveSheet()?.nativeElement.showModal();
  }

  protected closeOnBackdrop(event: MouseEvent): void {
    if (event.target === event.currentTarget) (event.currentTarget as HTMLDialogElement).close();
  }

  protected move(item: ScoredItem, storage: Storage): void {
    this.moveSheet()?.nativeElement.close();
    this.items.move(item.id, storage).subscribe({
      next: () => {
        this.undo.showOutcome(item, 'moved', storage);
        this.items.load().subscribe();
      },
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  protected resolve(item: ScoredItem, outcome: Outcome): void {
    this.items.resolve(item.id, outcome).subscribe({
      next: () => {
        this.undo.showOutcome(item, outcome);
        this.items.load().subscribe();
      },
      error: (err: { message?: string }) => this.fail(err),
    });
  }

  private percentFromPointer(event: Event): number {
    const input = event.target as HTMLInputElement;
    const raw = Number(input.value);
    const count = this.line().packs.length;
    const percent = levelPercent(levelFromPercent(raw, count, this.percent()), count);
    input.value = String(percent);
    return percent;
  }

  private fail(err: { message?: string }): void {
    this.preview.set(null);
    this.openingId = null;
    this.lastCommit = null;
    this.failed.emit(err.message ?? '');
    this.items.load().subscribe();
  }
}

function nudgeDirection(key: string): -1 | 1 | 0 {
  if (key === 'ArrowLeft' || key === 'ArrowDown') return -1;
  if (key === 'ArrowRight' || key === 'ArrowUp') return 1;
  return 0;
}

/** Dates from before a drag's first move. A cancelled open puts these back. */
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
