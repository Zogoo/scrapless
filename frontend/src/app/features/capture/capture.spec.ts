import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { TranslateService, provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { environment } from '../../../environments/environment';
import { CaptureReview } from '../../core/models';
import { PushService } from '../../core/services/push.service';
import { SpeechService } from '../../core/services/speech.service';
import { Capture, SLOW_READ_MS } from './capture';

function reviewOf(...ids: number[]): CaptureReview {
  return {
    capture: { id: 1, source: 'receipt', kind: 'receipt', notes: null },
    items: ids.map((id) => ({
      id,
      display_name: `Item ${id}`,
      days_left: 5,
      needs_review: false,
      storage: 'fridge',
    })),
    suppressed: [],
  } as unknown as CaptureReview;
}

/** The surface the test drives; these members are protected on the component. */
interface ReviewSheet {
  review: { set(value: CaptureReview): void; (): CaptureReview | null };
  reject(id: number): void;
  place(item: CaptureReview['items'][number], storage: 'fridge' | 'freezer' | 'pantry'): void;
  startRename(item: CaptureReview['items'][number]): void;
  draftName: { set(value: string): void };
  saveName(item: CaptureReview['items'][number]): void;
}

describe('Capture review', () => {
  let http: HttpTestingController;
  let sheet: ReviewSheet;

  beforeEach(() => {
    // Before anything is created: PushService reads "already asked" from
    // storage when it is made (see today.spec.ts).
    localStorage.clear();
    TestBed.configureTestingModule({
      imports: [Capture],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
      ],
    });
    sheet = TestBed.createComponent(Capture).componentInstance as unknown as ReviewSheet;
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  it('deletes a line the user removes and keeps the rest', () => {
    sheet.review.set(reviewOf(1, 2));

    sheet.reject(2);
    const req = http.expectOne(`${environment.apiUrl}/items/2`);
    expect(req.request.method).toBe('DELETE');
    req.flush(null);

    expect(sheet.review()?.items.map((item) => item.id)).toEqual([1]);
  });

  it('leaves the review once the last line is removed', () => {
    const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);
    sheet.review.set(reviewOf(1));

    sheet.reject(1);
    http.expectOne(`${environment.apiUrl}/items/1`).flush(null);

    expect(navigate).toHaveBeenCalledWith(['/today']);
  });

  it('keeps the line when the delete fails', () => {
    sheet.review.set(reviewOf(1, 2));

    sheet.reject(2);
    http
      .expectOne(`${environment.apiUrl}/items/2`)
      .flush(null, { status: 503, statusText: 'Service Unavailable' });

    expect(sheet.review()?.items.map((item) => item.id)).toEqual([1, 2]);
  });

  // With the keyboard open, a button below the twenty chips was out of sight.
  it('puts the add button right under the field, above the chips', () => {
    const fixture = TestBed.createComponent(Capture);
    (fixture.componentInstance as unknown as { mode: { set(m: string): void } }).mode.set('manual');
    fixture.detectChanges();
    const root = fixture.nativeElement as HTMLElement;

    const field = root.querySelector('.field')!;
    const add = root.querySelector('button.primary.wide')!;
    const grid = root.querySelector('.grid')!;
    expect(field.compareDocumentPosition(add) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(add.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect((add as HTMLButtonElement).disabled).toBe(true);

    (root.querySelector('.grid .chip') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect((add as HTMLButtonElement).disabled).toBe(false);
  });

  describe('a variety merged into a product', () => {
    function render(items: Partial<CaptureReview['items'][number]>[]): HTMLElement {
      const fixture = TestBed.createComponent(Capture);
      const screen = fixture.componentInstance as unknown as ReviewSheet & {
        mode: { set(value: string): void };
      };
      screen.review.set({
        capture: { id: 1, source: 'text', kind: 'receipt', notes: null },
        items: items.map((item, i) => ({
          id: i + 1,
          days_left: 5,
          needs_review: false,
          storage: 'pantry',
          in_kitchen: 1,
          ...item,
        })),
        suppressed: [],
      } as unknown as CaptureReview);
      screen.mode.set('review');
      fixture.detectChanges();
      return fixture.nativeElement as HTMLElement;
    }

    it('shows the product as the title and the variety underneath', () => {
      const root = render([{ display_name: '🍚 Basmatireis', product_name: 'Reis', merged: true }]);

      expect(root.querySelector('.review-list .name .title')?.textContent?.trim()).toBe('🍚 Reis');
      expect(root.querySelector('.review-list .variety')?.textContent?.trim()).toBe('Basmatireis');
    });

    function notes(root: HTMLElement): string[] {
      return [...root.querySelectorAll('.review-list small')].map((n) => n.textContent!.trim());
    }

    beforeEach(() => {
      const translate = TestBed.inject(TranslateService);
      translate.setTranslation('de', {
        capture: {
          in_kitchen: 'jetzt {{count}} in der Küche',
          joins: 'kommt zu {{name}} · jetzt {{count}} in der Küche',
        },
      });
      translate.use('de');
    });

    // Tilsiter given the product of the Käse already there: say which line.
    it('names the line a pack joins in place of the count, not beside it', () => {
      const root = render([
        { display_name: '🧀 Tilsiter', merged: false, joins: 'Käse', in_kitchen: 2 },
      ]);

      expect(notes(root)).toEqual(['kommt zu Käse · jetzt 2 in der Küche']);
    });

    it('gives a merged variety its name and the count, and no "joins" line', () => {
      const root = render([
        {
          display_name: '🍚 Basmatireis',
          product_name: 'Reis',
          merged: true,
          joins: null,
          in_kitchen: 2,
        },
      ]);

      expect(notes(root)).toEqual(['Basmatireis', 'jetzt 2 in der Küche']);
    });

    it('shows a plain item as itself, with no second line', () => {
      const root = render([{ display_name: '🥛 Milch', product_name: null, merged: false }]);

      expect(root.querySelector('.review-list .name .title')?.textContent?.trim()).toBe('🥛 Milch');
      expect(root.querySelector('.review-list .variety')).toBeNull();
    });
  });

  // A misread is fixed where it is noticed; the server re-reads the food and
  // teaches the dictionary (Items::Correct).
  it('corrects a misread name on the review and shows what came back', () => {
    sheet.review.set(reviewOf(1, 2));
    const row = sheet.review()!.items[1];

    sheet.startRename(row);
    sheet.draftName.set('Tilsiter');
    sheet.saveName(row);

    const req = http.expectOne(`${environment.apiUrl}/items/2`);
    expect(req.request.method).toBe('PATCH');
    expect(req.request.body).toEqual({
      item: { display_name: 'Tilsiter', canonical_name: 'tilsiter' },
    });
    req.flush({ id: 2, display_name: '🧀 Tilsiter', storage: 'fridge', days_left: 21 });

    expect(sheet.review()!.items[1]).toMatchObject({
      display_name: '🧀 Tilsiter',
      days_left: 21,
      merged: false,
    });
  });

  it('sends nothing when the name did not change', () => {
    sheet.review.set(reviewOf(1));
    const row = sheet.review()!.items[0];

    sheet.startRename(row);
    sheet.saveName(row);

    http.expectNone(`${environment.apiUrl}/items/1`);
  });

  it('fixes where a line goes as a correction, and shows its new days', () => {
    sheet.review.set(reviewOf(1, 2));

    sheet.place(sheet.review()!.items[1], 'pantry');
    const req = http.expectOne(`${environment.apiUrl}/items/2`);
    expect(req.request.method).toBe('PATCH');
    expect(req.request.body).toEqual({ item: { storage: 'pantry' } });
    req.flush({ id: 2, storage: 'pantry', window_end: '2027-11-19', days_left: 364 });

    expect(sheet.review()!.items[1]).toMatchObject({ storage: 'pantry', days_left: 364 });
    expect(sheet.review()!.items[0].storage).toBe('fridge');
  });

  it('sends nothing when the place did not change', () => {
    sheet.review.set(reviewOf(1));

    sheet.place(sheet.review()!.items[0], 'fridge');

    http.expectNone(`${environment.apiUrl}/items/1`);
  });

  // Asked after the first foods land (doc 2 §2.7), never at onboarding.
  describe('the notification question', () => {
    function renderReview() {
      const fixture = TestBed.createComponent(Capture);
      const component = fixture.componentInstance as unknown as ReviewSheet & {
        mode: { set(value: string): void };
      };
      component.review.set(reviewOf(1));
      component.mode.set('review');
      fixture.detectChanges();
      return fixture;
    }

    beforeEach(() => localStorage.clear());

    it('is asked on the review when this phone could say yes', () => {
      TestBed.inject(PushService).state.set('off');

      expect(renderReview().nativeElement.querySelector('.notify-ask')).not.toBeNull();
    });

    it('is not asked where the answer is already known', () => {
      TestBed.inject(PushService).state.set('blocked');

      expect(renderReview().nativeElement.querySelector('.notify-ask')).toBeNull();
    });

    it('goes away on "Not now" and stays away', () => {
      const push = TestBed.inject(PushService);
      push.state.set('off');
      const fixture = renderReview();

      const buttons = fixture.nativeElement.querySelectorAll('.notify-actions button');
      (buttons[1] as HTMLButtonElement).click();
      fixture.detectChanges();

      expect(fixture.nativeElement.querySelector('.notify-ask')).toBeNull();
      expect(push.shouldAsk()).toBe(false);
    });
  });

  // A stopped camera is a black screen, and reading takes seconds: users took
  // that for a frozen app. The photo stays up with a lens moving over it.
  describe('while a photo is read', () => {
    interface Reader {
      readPhoto(blob: Blob): void;
      mode(): string;
      shot(): string | null;
      slow(): boolean;
      error(): string;
    }

    let fixture: ReturnType<typeof TestBed.createComponent<Capture>>;
    let reader: Reader;

    beforeEach(() => {
      vi.useFakeTimers();
      URL.createObjectURL = vi.fn(() => 'blob:photo');
      URL.revokeObjectURL = vi.fn();
      fixture = TestBed.createComponent(Capture);
      reader = fixture.componentInstance as unknown as Reader;
      reader.readPhoto(new Blob(['x'], { type: 'image/jpeg' }));
      fixture.detectChanges();
    });

    afterEach(() => vi.useRealTimers());

    it('shows the photo with a moving lens, not a black screen', () => {
      const screen = fixture.nativeElement.querySelector('.reading');
      expect(screen.querySelector('img').getAttribute('src')).toBe('blob:photo');
      expect(screen.querySelector('.lens')).not.toBeNull();
      expect(screen.getAttribute('role')).toBe('status');
      http.expectOne(`${environment.apiUrl}/captures`);
    });

    it('says it is still working once the wait passes ten seconds', () => {
      vi.advanceTimersByTime(SLOW_READ_MS - 1);
      expect(reader.slow()).toBe(false);

      vi.advanceTimersByTime(1);
      expect(reader.slow()).toBe(true);
      http.expectOne(`${environment.apiUrl}/captures`);
    });

    it('moves on to the review and lets the photo go', () => {
      http.expectOne(`${environment.apiUrl}/captures`).flush(reviewOf(1));

      expect(reader.mode()).toBe('review');
      expect(reader.shot()).toBeNull();
      expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:photo');
    });

    it('goes back to the start with the error when reading fails', () => {
      http
        .expectOne(`${environment.apiUrl}/captures`)
        .flush({ error: 'nope' }, { status: 503, statusText: 'Service Unavailable' });

      expect(reader.mode()).toBe('choose');
      expect(reader.shot()).toBeNull();
      expect(reader.error()).not.toBe('');
    });
  });
});

// The recording path (iPhone and others): no words appear while speaking, so
// the screen says it is recording, for how long, and then that it is sending.
describe('Capture voice, recording', () => {
  let http: HttpTestingController;
  let resolveStart: () => void;
  const capturing = signal(false);
  const speech = {
    recognitionSupported: false,
    recordingSupported: true,
    supported: true,
    interim: signal(''),
    listening: signal(false),
    capturing,
    speechLang: () => 'de',
    startRecording: vi.fn(
      () =>
        new Promise<void>((resolve) => {
          resolveStart = () => {
            capturing.set(true);
            resolve();
          };
        }),
    ),
    stopRecording: vi.fn(async () => ({
      blob: new Blob(['x'], { type: 'audio/mp4' }),
      seconds: 3,
      mimeType: 'audio/mp4',
    })),
    cancel: vi.fn(),
  };

  beforeEach(() => {
    vi.useFakeTimers();
    capturing.set(false);
    TestBed.configureTestingModule({
      imports: [Capture],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
        { provide: SpeechService, useValue: speech },
      ],
    });
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('de', {
      capture: {
        rec_starting: 'Mikrofon startet…',
        rec_on: 'Aufnahme läuft',
        rec_sending: 'Aufnahme wird übertragen…',
        reading: 'Wird gelesen…',
      },
    });
    translate.use('de');
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    vi.useRealTimers();
    TestBed.resetTestingModule();
  });

  it('says it is starting, then recording with a timer, then sending', async () => {
    const fixture = TestBed.createComponent(Capture);
    const screen = fixture.componentInstance as unknown as {
      startVoice(): void;
      stopVoice(): Promise<void>;
    };
    const root = fixture.nativeElement as HTMLElement;
    const state = () => root.querySelector('.rec-state')?.textContent?.replace(/\s+/g, ' ').trim();

    screen.startVoice();
    fixture.detectChanges();
    expect(state()).toBe('Mikrofon startet…');

    resolveStart();
    await Promise.resolve();
    vi.advanceTimersByTime(7000);
    fixture.detectChanges();
    expect(state()).toBe('Aufnahme läuft 0:07');
    expect(root.querySelector('.pulse.rec.live')).not.toBeNull();

    const stopping = screen.stopVoice();
    fixture.detectChanges();
    expect(state()).toBe('Aufnahme wird übertragen…');
    // "Tap Done" is no longer something to do.
    expect(root.querySelector('.voice .prompt')).toBeNull();
    await stopping;
    fixture.detectChanges();
    // One line about it, not "sending" and "reading" both.
    expect(root.textContent).not.toContain('Wird gelesen…');

    const upload = http.expectOne(`${environment.apiUrl}/captures`);
    expect(upload.request.method).toBe('POST');
  });
});
