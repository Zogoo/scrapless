import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { TranslateService, provideTranslateService } from '@ngx-translate/core';
import { Subject } from 'rxjs';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { environment } from '../../../environments/environment';
import { MemoItem } from '../../core/models';
import { SpeechService } from '../../core/services/speech.service';
import { HOLD_MS, Memo } from './memo';

/** A recogniser the test controls: what was heard, and whether it was stopped or thrown away. */
class FakeSpeech {
  readonly listening = signal(false);
  readonly capturing = signal(false);
  readonly interim = signal('');
  readonly speechLang = signal('de');
  readonly recognitionSupported = true;
  readonly recordingSupported = true;
  readonly supported = true;
  heard = new Subject<string>();
  finish = vi.fn(() => {
    this.listening.set(false);
    this.heard.next('Milch');
    this.heard.complete();
  });
  cancel = vi.fn(() => {
    this.listening.set(false);
    this.heard.complete();
  });
  listen = vi.fn(() => {
    this.heard = new Subject<string>();
    this.listening.set(true);
    return this.heard;
  });
  setSpeechLang = vi.fn((lang: string) => this.speechLang.set(lang));
}

/** The surface the test drives; these members are protected on the component. */
interface MicSurface {
  onMicDown(event: PointerEvent): void;
  onMicUp(event: PointerEvent): void;
  onMicPointerCancel(): void;
  onMicClick(event: MouseEvent): void;
  cancelDictation(): void;
  undo(item: MemoItem): void;
  rename(item: MemoItem, name: string): void;
  micMode(): 'idle' | 'hold' | 'toggle';
  justAdded(): MemoItem[];
}

function pointer(type: string, x = 10, y = 10): PointerEvent {
  const button = {
    getBoundingClientRect: () => ({ left: 0, right: 48, top: 0, bottom: 48 }),
    setPointerCapture: () => undefined,
  };
  return {
    type,
    button: 0,
    pointerId: 1,
    clientX: x,
    clientY: y,
    currentTarget: button,
    preventDefault: () => undefined,
  } as unknown as PointerEvent;
}

const milch: MemoItem = {
  id: 7,
  name: 'Milch',
  note: null,
  done: false,
  source: 'voice',
  position: 1,
  created_at: '',
  added_by_name: null,
};

describe('Memo mic', () => {
  let http: HttpTestingController;
  let speech: FakeSpeech;
  let mic: MicSurface;
  let now = 1_000;

  beforeEach(() => {
    localStorage.clear();
    speech = new FakeSpeech();
    vi.spyOn(Date, 'now').mockImplementation(() => now);
    TestBed.configureTestingModule({
      imports: [Memo],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideTranslateService(),
        { provide: SpeechService, useValue: speech },
      ],
    });
    mic = TestBed.createComponent(Memo).componentInstance as unknown as MicSurface;
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    vi.restoreAllMocks();
    TestBed.resetTestingModule();
  });

  function hold(ms: number, release = pointer('pointerup')): void {
    mic.onMicDown(pointer('pointerdown'));
    now += ms;
    mic.onMicUp(release);
  }

  it('adds what was said when a hold is released, in the language chosen', () => {
    hold(HOLD_MS + 200);

    expect(speech.finish).toHaveBeenCalled();
    const req = http.expectOne(`${environment.apiUrl}/memo/dictate`);
    expect(req.request.body).toEqual({
      transcript: 'Milch',
      lang: 'de',
      gesture: 'hold',
      press_ms: HOLD_MS + 200,
    });
    req.flush({ transcript: 'Milch', items: [milch] });
    http.expectOne(`${environment.apiUrl}/memo`).flush({ items: [milch], suggestions: [] });

    expect(mic.justAdded()).toEqual([milch]);
  });

  it('keeps listening after a tap, until the mic is tapped again', () => {
    hold(HOLD_MS - 200);

    expect(mic.micMode()).toBe('toggle');
    expect(speech.finish).not.toHaveBeenCalled();

    mic.onMicDown(pointer('pointerdown'));
    mic.onMicUp(pointer('pointerup'));

    expect(speech.finish).toHaveBeenCalledTimes(1);
    expect(mic.micMode()).toBe('idle');
    http.expectOne(`${environment.apiUrl}/memo/dictate`);
  });

  it('adds nothing when the hold is released outside the button', () => {
    hold(HOLD_MS + 200, pointer('pointerup', 200, 200));

    expect(speech.cancel).toHaveBeenCalled();
    expect(speech.finish).not.toHaveBeenCalled();
    http.expectNone(`${environment.apiUrl}/memo/dictate`);
  });

  it('adds nothing when the browser takes the gesture over', () => {
    mic.onMicDown(pointer('pointerdown'));

    mic.onMicPointerCancel();

    expect(speech.cancel).toHaveBeenCalled();
  });

  it('cancels from the visible button too, so sliding is never the only way', () => {
    hold(HOLD_MS - 200);

    mic.cancelDictation();

    expect(speech.cancel).toHaveBeenCalled();
    expect(mic.micMode()).toBe('idle');
  });

  it('works from the keyboard, as a toggle', () => {
    const keyboard = { detail: 0 } as MouseEvent;

    mic.onMicClick(keyboard);
    expect(speech.listen).toHaveBeenCalled();

    mic.onMicClick(keyboard);
    expect(speech.finish).toHaveBeenCalled();
    http.expectOne(`${environment.apiUrl}/memo/dictate`);
  });

  it('takes back a line that was just dictated', () => {
    hold(HOLD_MS + 200);
    http
      .expectOne(`${environment.apiUrl}/memo/dictate`)
      .flush({ transcript: 'Milch', items: [milch] });
    http.expectOne(`${environment.apiUrl}/memo`).flush({ items: [milch], suggestions: [] });

    mic.undo(milch);

    expect(http.expectOne(`${environment.apiUrl}/memo/7`).request.method).toBe('DELETE');
    expect(mic.justAdded()).toEqual([]);
  });
  // The correction is what the server learns from.
  it('renames a line that was just dictated', () => {
    hold(HOLD_MS + 200);
    http
      .expectOne(`${environment.apiUrl}/memo/dictate`)
      .flush({ transcript: 'Milch', items: [milch] });
    http.expectOne(`${environment.apiUrl}/memo`).flush({ items: [milch], suggestions: [] });

    mic.rename(milch, 'Hafermilch');

    const req = http.expectOne(`${environment.apiUrl}/memo/7`);
    expect(req.request.method).toBe('PATCH');
    expect(req.request.body).toEqual({ memo_item: { name: 'Hafermilch' } });
    req.flush({ ...milch, name: 'Hafermilch' });
    http.expectOne(`${environment.apiUrl}/memo`).flush({ items: [], suggestions: [] });

    expect(mic.justAdded().map((item) => item.name)).toEqual(['Hafermilch']);
  });
});

// iPhone records: no words appear while speaking, so the status bar has to
// say it is recording, for how long, and then that it is sending.
describe('Memo mic, recording', () => {
  let http: HttpTestingController;
  let resolveStart: () => void;
  let now = 1_000;
  const capturing = signal(false);
  const listening = signal(false);
  const speech = {
    listening,
    capturing,
    interim: signal(''),
    speechLang: signal('de'),
    recognitionSupported: false,
    recordingSupported: true,
    supported: true,
    setSpeechLang: vi.fn(),
    cancel: vi.fn(() => listening.set(false)),
    startRecording: vi.fn(
      () =>
        new Promise<void>((resolve) => {
          listening.set(true);
          resolveStart = () => {
            capturing.set(true);
            resolve();
          };
        }),
    ),
    stopRecording: vi.fn(async () => {
      listening.set(false);
      capturing.set(false);
      return { blob: new Blob(['x'], { type: 'audio/mp4' }), seconds: 4, mimeType: 'audio/mp4' };
    }),
  };

  beforeEach(() => {
    localStorage.clear();
    vi.useFakeTimers();
    vi.spyOn(Date, 'now').mockImplementation(() => now);
    TestBed.configureTestingModule({
      imports: [Memo],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideTranslateService(),
        { provide: SpeechService, useValue: speech },
      ],
    });
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('de', {
      capture: { rec_on: 'Aufnahme läuft', rec_sending: 'Aufnahme wird übertragen…' },
      memo: { starting: 'Einen Moment…', listening: 'Ich höre…' },
    });
    translate.use('de');
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    TestBed.resetTestingModule();
  });

  it('shows starting, then recording with a timer, then sending until the lines arrive', async () => {
    const fixture = TestBed.createComponent(Memo);
    const mic = fixture.componentInstance as unknown as MicSurface;
    const root = fixture.nativeElement as HTMLElement;
    const status = () =>
      [...root.querySelectorAll('.interim span')]
        .map((s) => s.textContent!.replace(/\s+/g, ' ').trim())
        .find((t) => t.length > 0);

    mic.onMicDown(pointer('pointerdown'));
    fixture.detectChanges();
    expect(status()).toBe('Einen Moment…');

    resolveStart();
    await Promise.resolve();
    vi.advanceTimersByTime(5000);
    fixture.detectChanges();
    expect(root.querySelector('.interim .rec-dot')).not.toBeNull();
    expect(status()).toBe('Aufnahme läuft 0:05');

    now += HOLD_MS + 5000;
    mic.onMicUp(pointer('pointerup'));
    fixture.detectChanges();
    expect(status()).toBe('Aufnahme wird übertragen…');

    await Promise.resolve();
    await Promise.resolve();
    http
      .expectOne(`${environment.apiUrl}/memo/dictate`)
      .flush({ transcript: 'Milch', items: [milch] });
    fixture.detectChanges();
    expect(root.textContent).not.toContain('Aufnahme wird übertragen…');
  });
});

describe('Memo list', () => {
  let http: HttpTestingController;

  const lines: MemoItem[] = [
    { ...milch, id: 1, name: 'Äpfel', category: 'produce', quantity: 2, added_by_name: 'Papa' },
    { ...milch, id: 2, name: 'Milch', category: 'dairy', quantity: 1 },
    { ...milch, id: 3, name: 'Brot', category: 'bakery', quantity: 1, done: true },
  ];
  const suggestions = [
    { name: 'Butter', category: 'dairy', reason: 'usually every 7 days' },
    { name: 'Eier', category: 'dairy', reason: 'bought 3 times' },
  ];

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      imports: [Memo],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideTranslateService(),
        { provide: SpeechService, useValue: new FakeSpeech() },
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    vi.useRealTimers();
    TestBed.resetTestingModule();
  });

  function render(items = lines, suggested = suggestions) {
    const fixture = TestBed.createComponent(Memo);
    fixture.detectChanges();
    http.expectOne(`${environment.apiUrl}/memo`).flush({ items, suggestions: suggested });
    fixture.detectChanges();
    const root = fixture.nativeElement as HTMLElement;
    const text = (selector: string) =>
      [...root.querySelectorAll(selector)].map((n) => n.textContent!.trim());
    return { fixture, root, text };
  }

  function reload(items: MemoItem[], suggested = suggestions) {
    http.expectOne(`${environment.apiUrl}/memo`).flush({ items, suggestions: suggested });
  }

  it('lists open lines by section, with "2×" only when there is more than one', () => {
    const { text } = render();

    expect(text('h2.section')).toContain('memo.section_produce');
    expect(text('.list:not(.done-lines) .what')).toEqual(['2× Äpfel', 'Milch']);
    expect(text('.list .by')).toEqual(['Papa']);
  });

  it('folds Erledigt away, opens it, reopens a line, and clears it', () => {
    const { fixture, root, text } = render();
    const toggleDone = () => root.querySelector('.done-toggle') as HTMLButtonElement;

    expect(toggleDone().getAttribute('aria-expanded')).toBe('false');
    expect(root.querySelector('.done-lines')).toBeNull();

    toggleDone().click();
    fixture.detectChanges();
    expect(toggleDone().getAttribute('aria-expanded')).toBe('true');
    expect(text('.done-lines .what')).toEqual(['Brot']);

    (root.querySelector('.done-lines .row') as HTMLButtonElement).click();
    const reopen = http.expectOne(`${environment.apiUrl}/memo/3`);
    expect(reopen.request.body).toEqual({ memo_item: { done: false } });
    reopen.flush({ ...lines[2], done: false });
    reload(lines.map((l) => ({ ...l, done: false })));
    fixture.detectChanges();
    expect(root.querySelector('.done-head')).toBeNull();
  });

  it('clears the done lines with Leeren', () => {
    const { root } = render();

    (root.querySelector('.done-head button:last-child') as HTMLButtonElement).click();

    http.expectOne(`${environment.apiUrl}/memo/clear_done`).flush(null);
    reload(lines.filter((l) => !l.done));
  });

  it('adds a "Bald leer" chip as a suggestion, and the chip goes', () => {
    const { fixture, root, text } = render();
    expect(text('.chips .chip')).toEqual(['+ Butter', '+ Eier']);
    expect(root.querySelector('.chips .chip')?.getAttribute('title')).toBe('usually every 7 days');

    (root.querySelector('.chips .chip') as HTMLButtonElement).click();
    const add = http.expectOne(`${environment.apiUrl}/memo`);
    expect(add.request.body).toEqual({ name: 'Butter', source: 'suggestion' });
    add.flush({ ...milch, id: 9, name: 'Butter' });
    reload([...lines, { ...milch, id: 9, name: 'Butter', category: 'dairy' }], [suggestions[1]]);
    fixture.detectChanges();

    expect(text('.chips .chip')).toEqual(['+ Eier']);
  });

  it('shows "Bald leer" as one short row, at most six chips', () => {
    const many = Array.from({ length: 9 }, (_, i) => ({
      name: `Ding ${i}`,
      category: 'other',
      reason: '',
    }));

    expect(render(lines, many).root.querySelectorAll('.chips .chip')).toHaveLength(6);
  });

  it('hides "Bald leer" with its × until tomorrow', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 10, 21, 18, 0));
    const first = render();
    (first.root.querySelector('.hide-low') as HTMLButtonElement).click();
    first.fixture.detectChanges();
    expect(first.root.querySelector('.chips')).toBeNull();

    expect(render().root.querySelector('.chips')).toBeNull(); // the same day

    vi.setSystemTime(new Date(2026, 10, 22, 8, 0));
    expect(render().root.querySelector('.chips')).not.toBeNull(); // the next day
  });

  it('says when an add landed on a line already there', () => {
    const { fixture, root } = render();
    const input = root.querySelector('.composer input') as HTMLInputElement;
    input.value = '1 Äpfel';
    input.dispatchEvent(new Event('input'));
    fixture.detectChanges();

    (root.querySelector('.composer button') as HTMLButtonElement).click();
    http.expectOne(`${environment.apiUrl}/memo`).flush({ ...lines[0], quantity: 3, merged: true });
    reload(lines);
    fixture.detectChanges();

    expect(root.querySelector('.status')?.textContent?.trim()).toBe('memo.merged_count');
  });
});
