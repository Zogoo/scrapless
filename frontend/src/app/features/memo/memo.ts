import {
  Component,
  OnDestroy,
  OnInit,
  computed,
  inject,
  signal,
  ChangeDetectionStrategy,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';
import {
  Subject,
  Subscription,
  debounceTime,
  distinctUntilChanged,
  switchMap,
  takeUntil,
} from 'rxjs';

import { environment } from '../../../environments/environment';
import { DictationGesture, MemoService } from '../../core/services/memo.service';
import {
  SpeechLang,
  SpeechService,
  audioFilename,
  speechTag,
} from '../../core/services/speech.service';
import { MemoItem, Suggestion } from '../../core/models';

/**
 * Shorter than this is a tap, longer is a hold. A heuristic, not a verified
 * figure: it fails for anyone who holds briefly for a one-word item. Every
 * dictation logs its press duration (`press_ms`), so the value is tuned from
 * real use (doc 15 §15.8.5).
 */
export const HOLD_MS = 350;
const MIC_USES_KEY = 'scrapless_mic_uses';
const HINT_UNTIL_USES = 3;

/**
 * The shopping memo.
 *
 * The suggestions are the point. A blank list is a chore; a list that already
 * knows you buy milk every four days and have not bought any for six is worth
 * opening. That signal comes free out of capture history — no extra input from
 * the user and no model call to produce it.
 */
@Component({
  selector: 'app-memo',
  imports: [FormsModule, TranslatePipe],
  templateUrl: './memo.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './memo.scss',
})
export class Memo implements OnInit, OnDestroy {
  private readonly memo = inject(MemoService);
  private readonly translate = inject(TranslateService);
  protected readonly speech = inject(SpeechService);

  protected readonly items = this.memo.items;
  protected readonly suggestions = this.memo.suggestions;
  protected readonly doneCount = computed(() => this.items().filter((item) => item.done).length);
  protected readonly typed = signal('');
  protected readonly matches = signal<Suggestion[]>([]);
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  /** idle; held down; or listening hands-free after a tap. */
  protected readonly micMode = signal<'idle' | 'hold' | 'toggle'>('idle');
  /** The lines the last dictation added, shown with an undo. */
  protected readonly justAdded = signal<MemoItem[]>([]);
  protected readonly micUses = signal(this.readMicUses());
  /** Every language the app speaks; the list is environment.availableLocales. */
  protected readonly speechLangs: readonly SpeechLang[] = environment.availableLocales;
  protected readonly showMicHint = computed(() => this.micUses() < HINT_UNTIL_USES);

  /** The just-added line being corrected, if any. */
  protected readonly editingId = signal<number | null>(null);

  private pressedAt = 0;
  /** How the mic was used, logged with each dictation (doc 15 §15.8.5). */
  private gesture: DictationGesture = { gesture: 'tap', press_ms: 0 };
  private swallowUp = false;
  private listening: Subscription | null = null;

  private readonly queries = new Subject<string>();
  private readonly destroyed = new Subject<void>();

  ngOnInit(): void {
    this.memo.load().subscribe({
      error: (err: { message?: string }) => this.error.set(err.message ?? ''),
    });

    // Autosuggest as you type, against the household's own history first.
    this.queries
      .pipe(
        debounceTime(180),
        distinctUntilChanged(),
        switchMap((query) => this.memo.suggest(query)),
        takeUntil(this.destroyed),
      )
      .subscribe({
        next: (found) => this.matches.set(found),
        error: () => this.matches.set([]),
      });
  }

  ngOnDestroy(): void {
    this.destroyed.next();
    this.destroyed.complete();
    this.listening?.unsubscribe();
    this.speech.cancel();
  }

  protected onType(value: string): void {
    this.typed.set(value);
    this.queries.next(value.trim());
  }

  protected add(name: string, source: 'text' | 'suggestion' = 'text'): void {
    const cleaned = name.trim();
    if (!cleaned) return;

    this.busy.set(true);
    this.memo.add(cleaned, source).subscribe({
      next: () => {
        this.typed.set('');
        this.matches.set([]);
        this.refresh();
      },
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? '');
        this.busy.set(false);
      },
    });
  }

  protected toggle(id: number, done: boolean): void {
    this.memo
      .setDone(id, done)
      .subscribe({ next: () => this.refresh(), error: (err) => this.fail(err) });
  }

  protected remove(id: number): void {
    this.memo.remove(id).subscribe({ next: () => this.refresh(), error: (err) => this.fail(err) });
  }

  protected dismiss(name: string): void {
    this.memo.dismiss(name).subscribe({ error: (err) => this.fail(err) });
  }

  protected clearDone(): void {
    this.memo.clearDone().subscribe({ next: () => this.refresh(), error: (err) => this.fail(err) });
  }

  /** Show what went wrong, and the list as it really is now. */
  private fail(err: { message?: string }): void {
    this.error.set(err.message ?? '');
    this.refresh();
  }

  /*
   * The mic (doc 15 §15.8.4). One button, two ways in, so neither gesture is
   * the only way:
   *
   * - press and hold: listen while held, add the lines on release. The
   *   voice-message gesture, and one held item is one short session;
   * - tap: listen until the recogniser ends by itself or the mic is tapped
   *   again. The dictation gesture, and the way in for anyone who cannot hold.
   *
   * Releasing outside the button, or the visible cancel, adds nothing.
   */

  protected onMicDown(event: PointerEvent): void {
    if (event.button !== 0 || this.busy()) return;
    event.preventDefault();

    // A second tap while listening hands-free ends the session.
    if (this.micMode() === 'toggle') {
      this.swallowUp = true;
      this.finishDictation();
      return;
    }
    // The previous session has not ended yet; starting another would throw.
    if (this.speech.listening()) return;

    // Keeps pointerup on the button while the finger drifts. Best effort: it
    // throws for a pointer the browser no longer tracks, and the mic must still work.
    try {
      (event.currentTarget as HTMLElement | null)?.setPointerCapture?.(event.pointerId);
    } catch {
      /* release outside is then detected from coordinates alone */
    }
    this.pressedAt = Date.now();
    this.micMode.set('hold');
    this.gesture = { gesture: 'hold', press_ms: 0 };
    this.startDictation();
  }

  protected onMicUp(event: PointerEvent): void {
    if (this.swallowUp) {
      this.swallowUp = false;
      return;
    }
    if (this.micMode() !== 'hold') return;

    if (!this.insideButton(event)) {
      this.cancelDictation();
      return;
    }
    const pressMs = Date.now() - this.pressedAt;
    if (pressMs < HOLD_MS) {
      this.gesture = { gesture: 'tap', press_ms: pressMs };
      this.micMode.set('toggle');
      return;
    }
    this.gesture = { gesture: 'hold', press_ms: pressMs };
    this.finishDictation();
  }

  /** The browser took the gesture over (a scroll, a system sheet): treat as cancel. */
  protected onMicPointerCancel(): void {
    if (this.micMode() === 'hold') this.cancelDictation();
  }

  /** Keyboard (Enter/Space) gives a click with no pointer: toggle. */
  protected onMicClick(event: MouseEvent): void {
    if (event.detail !== 0) return;
    if (this.micMode() !== 'idle') {
      this.finishDictation();
      return;
    }
    if (this.speech.listening() || this.busy()) return;
    this.micMode.set('toggle');
    this.gesture = { gesture: 'key', press_ms: 0 };
    this.startDictation();
  }

  protected cancelDictation(): void {
    this.micMode.set('idle');
    this.speech.cancel();
  }

  protected setSpeechLang(lang: SpeechLang): void {
    this.speech.setSpeechLang(lang);
  }

  /** Fix a line the mic got wrong; the server learns from the correction. */
  protected rename(item: MemoItem, name: string): void {
    this.editingId.set(null);
    const cleaned = name.trim();
    if (!cleaned || cleaned === item.name) return;

    this.memo.rename(item.id, cleaned).subscribe({
      next: (saved) => {
        this.justAdded.update((items) => items.map((i) => (i.id === saved.id ? saved : i)));
        this.refresh();
      },
      error: (err) => this.fail(err),
    });
  }

  /** Take back one line that was just dictated. */
  protected undo(item: MemoItem): void {
    this.justAdded.update((items) => items.filter((i) => i.id !== item.id));
    this.remove(item.id);
  }

  private startDictation(): void {
    this.error.set('');
    this.justAdded.set([]);

    if (this.speech.recognitionSupported) {
      this.listening = this.speech.listen(speechTag(this.speech.speechLang())).subscribe({
        next: (text) => {
          if (text) this.sendDictation(text);
        },
        error: (err: Error) => {
          this.micMode.set('idle');
          // The recogniser exists but may not be used here: record instead
          // (SpeechService has stopped offering recognition by now).
          if (
            ['service-not-allowed', 'deaf'].includes(err.message) &&
            this.speech.recordingSupported
          ) {
            this.error.set(this.translate.instant('memo.try_again'));
            return;
          }
          this.error.set(this.translate.instant('capture.no_mic'));
        },
        complete: () => this.micMode.set('idle'),
      });
      return;
    }

    void this.speech.startRecording().catch(() => {
      this.micMode.set('idle');
      this.error.set(this.translate.instant('capture.no_mic'));
    });
  }

  private finishDictation(): void {
    this.micMode.set('idle');

    if (this.speech.recognitionSupported) {
      // stop(), not abort(): abort throws away what was just said (doc 15 §15.2.1).
      this.speech.finish();
      return;
    }

    this.busy.set(true);
    void this.speech
      .stopRecording()
      .then((recording) => {
        const lang = this.speech.speechLang();
        this.memo
          .dictateAudio(
            recording.blob,
            recording.seconds,
            lang,
            audioFilename(recording.mimeType, 'memo'),
            this.gesture,
          )
          .subscribe({
            next: (result) => this.dictated(result.items),
            error: (err) => this.failDictation(err),
          });
      })
      .catch(() => this.busy.set(false));
  }

  private sendDictation(text: string): void {
    this.busy.set(true);
    this.memo.dictate(text, this.speech.speechLang(), this.gesture).subscribe({
      next: (result) => this.dictated(result.items),
      error: (err) => this.failDictation(err),
    });
  }

  private dictated(items: MemoItem[]): void {
    this.justAdded.set(items);
    this.countMicUse();
    this.refresh();
  }

  private failDictation(err: { message?: string }): void {
    this.error.set(err.message ?? '');
    this.busy.set(false);
  }

  private insideButton(event: PointerEvent): boolean {
    const target = event.currentTarget as HTMLElement | null;
    if (!target?.getBoundingClientRect) return true;
    const box = target.getBoundingClientRect();
    return (
      event.clientX >= box.left &&
      event.clientX <= box.right &&
      event.clientY >= box.top &&
      event.clientY <= box.bottom
    );
  }

  /** The hold gesture is easy to miss (doc 15 §15.8.3), so the hint stays until it has been used a few times. */
  private countMicUse(): void {
    const uses = this.micUses() + 1;
    this.micUses.set(uses);
    try {
      localStorage.setItem(MIC_USES_KEY, String(uses));
    } catch {
      /* private mode: the hint just stays */
    }
  }

  private readMicUses(): number {
    try {
      return Number(localStorage.getItem(MIC_USES_KEY)) || 0;
    } catch {
      return 0;
    }
  }

  private refresh(): void {
    this.memo.load().subscribe({
      next: () => this.busy.set(false),
      error: () => this.busy.set(false),
    });
  }
}
