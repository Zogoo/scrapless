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
