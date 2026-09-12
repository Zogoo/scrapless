import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';
import { Subject, debounceTime, distinctUntilChanged, switchMap, takeUntil } from 'rxjs';

import { MemoService } from '../../core/services/memo.service';
import { SpeechService, speechTag } from '../../core/services/speech.service';
import { Suggestion } from '../../core/models';

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
  styleUrl: './memo.scss',
})
export class Memo implements OnInit, OnDestroy {
  private readonly memo = inject(MemoService);
  private readonly translate = inject(TranslateService);
  protected readonly speech = inject(SpeechService);

  protected readonly items = this.memo.items;
  protected readonly suggestions = this.memo.suggestions;
  protected readonly typed = signal('');
  protected readonly matches = signal<Suggestion[]>([]);
  protected readonly busy = signal(false);
  protected readonly error = signal('');

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
    this.memo.setDone(id, done).subscribe({ next: () => this.refresh() });
  }

  protected remove(id: number): void {
    this.memo.remove(id).subscribe({ next: () => this.refresh() });
  }

  /**
   * Speak the whole list at once on the way out of the door. The transcript is
   * split into lines server-side, and a memo line does not have to resolve to a
   * known product — "something for Sunday" is a legitimate entry — so this path
   * never reaches a model at all.
   */
  protected startDictation(): void {
    this.error.set('');

    if (this.speech.recognitionSupported) {
      this.speech.listen(speechTag(this.translate.currentLang())).subscribe({
        next: (text) => {
          if (text) this.sendDictation(text);
        },
        error: () => this.error.set(this.translate.instant('capture.no_mic')),
      });
      return;
    }

    void this.speech.startRecording().catch(() => {
      this.error.set(this.translate.instant('capture.no_mic'));
    });
  }

  protected async stopDictation(): Promise<void> {
    if (this.speech.recognitionSupported) {
      this.speech.cancel();
      return;
    }

    this.busy.set(true);
    const recording = await this.speech.stopRecording();
    this.memo.dictateAudio(recording.blob, recording.seconds).subscribe({
      next: () => this.refresh(),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? '');
        this.busy.set(false);
      },
    });
  }

  private sendDictation(text: string): void {
    this.busy.set(true);
    this.memo.dictate(text).subscribe({
      next: () => this.refresh(),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? '');
        this.busy.set(false);
      },
    });
  }

  private refresh(): void {
    this.memo.load().subscribe({
      next: () => this.busy.set(false),
      error: () => this.busy.set(false),
    });
  }
}
