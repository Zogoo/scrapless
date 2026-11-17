import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideTranslateService } from '@ngx-translate/core';
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
  readonly speechLang = signal<'de' | 'en'>('de');
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
  setSpeechLang = vi.fn((lang: 'de' | 'en') => this.speechLang.set(lang));
}

/** The surface the test drives; these members are protected on the component. */
interface MicSurface {
  onMicDown(event: PointerEvent): void;
  onMicUp(event: PointerEvent): void;
  onMicPointerCancel(): void;
  onMicClick(event: MouseEvent): void;
  cancelDictation(): void;
  undo(item: MemoItem): void;
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
    expect(req.request.body).toEqual({ transcript: 'Milch', lang: 'de' });
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
});
