import { TestBed } from '@angular/core/testing';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { environment } from '../../../environments/environment';
import { SPEECH_TAGS } from '../speech-tags';
import { LocaleService } from './locale.service';
import {
  DEAF_AFTER_MS,
  isAppleMobile,
  SPEECH_LANG_KEY,
  SpeechService,
  audioFilename,
  speechTag,
} from './speech.service';

type Result = { 0: { transcript: string }; length: 1; isFinal: boolean };

/** Stands in for the browser recogniser and lets a test fire its events. */
class FakeRecognition extends EventTarget {
  static last: FakeRecognition | null = null;

  lang = '';
  continuous = true;
  interimResults = false;
  started = false;
  stopped = false;
  aborted = false;
  onresult: ((event: { resultIndex: number; results: Result[] }) => void) | null = null;
  onerror: ((event: { error: string }) => void) | null = null;
  onend: (() => void) | null = null;
  onaudiostart: (() => void) | null = null;

  constructor() {
    super();
    FakeRecognition.last = this;
  }

  start(): void {
    this.started = true;
  }

  stop(): void {
    this.stopped = true;
  }

  abort(): void {
    this.aborted = true;
  }

  hear(...results: [string, boolean][]): void {
    this.onresult?.({
      resultIndex: 0,
      results: results.map(([transcript, isFinal]) => ({ 0: { transcript }, length: 1, isFinal })),
    });
  }
}

describe('SpeechService', () => {
  let speech: SpeechService;

  beforeEach(() => {
    localStorage.clear();
    (window as unknown as { webkitSpeechRecognition: unknown }).webkitSpeechRecognition =
      FakeRecognition;
    TestBed.configureTestingModule({
      providers: [provideTranslateService({ fallbackLang: 'en', lang: 'en' })],
    });
    speech = TestBed.inject(SpeechService);
  });

  afterEach(() => {
    delete (window as unknown as { webkitSpeechRecognition?: unknown }).webkitSpeechRecognition;
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  function listen(): { got: string[]; done: () => boolean; error: () => string } {
    const got: string[] = [];
    let completed = false;
    let failure = '';
    speech.listen('de-DE').subscribe({
      next: (text) => got.push(text),
      complete: () => (completed = true),
      error: (err: Error) => (failure = err.message),
    });
    return { got, done: () => completed, error: () => failure };
  }

  it('listens for one utterance, in the language asked for', () => {
    listen();

    expect(FakeRecognition.last?.lang).toBe('de-DE');
    expect(FakeRecognition.last?.continuous).toBe(false);
    expect(speech.listening()).toBe(true);
  });

  // Doc 15 §15.2.1: stop() keeps what was heard, abort() throws it away.
  it('finishes with stop() and keeps what was heard', () => {
    const run = listen();
    FakeRecognition.last?.hear(['Milch', true]);

    speech.finish();
    FakeRecognition.last?.onend?.();

    expect(FakeRecognition.last?.stopped).toBe(true);
    expect(FakeRecognition.last?.aborted).toBe(false);
    expect(run.got).toEqual(['Milch']);
    expect(run.done()).toBe(true);
  });

  // Observed: "it won't be added by microphone". Safari, and Chrome on some
  // Androids, show the words as interim results and end on stop() without
  // ever marking them final; only final text was kept, so nothing was sent.
  it('keeps the words on screen when stop() ends before they were final', () => {
    const run = listen();
    FakeRecognition.last?.hear(['Milch Brot', false]);

    speech.finish();
    FakeRecognition.last?.onend?.();

    expect(run.got).toEqual(['Milch Brot']);
  });

  it('prefers final text, then adds what was still being heard', () => {
    const run = listen();
    FakeRecognition.last?.hear(['Milch', true], [' Brot', false]);

    speech.finish();
    FakeRecognition.last?.onend?.();

    expect(run.got).toEqual(['Milch Brot']);
  });

  // Observed on iOS: the first session works, the second hears nothing until
  // a reload. Reported as the old recogniser keeping the microphone.
  describe('a second session in the same page', () => {
    afterEach(() => vi.useRealTimers());

    it('releases the previous recogniser before starting the next', () => {
      listen();
      const first = FakeRecognition.last!;
      first.hear(['Milch', true]);
      speech.finish();
      first.onend?.();

      listen();

      expect(first.aborted).toBe(true);
      expect(FakeRecognition.last).not.toBe(first);
    });

    it('records instead when a session shows no sign of hearing', () => {
      vi.useFakeTimers();
      const run = listen();

      vi.advanceTimersByTime(DEAF_AFTER_MS);

      expect(run.error()).toBe('deaf');
      expect(FakeRecognition.last?.aborted).toBe(true);
      expect(speech.listening()).toBe(false);
      expect(speech.recognitionSupported).toBe(false);
    });

    it('never gives up on a session that is hearing', () => {
      vi.useFakeTimers();
      const run = listen();
      FakeRecognition.last?.onaudiostart?.();

      vi.advanceTimersByTime(DEAF_AFTER_MS * 3);

      expect(run.error()).toBe('');
      expect(speech.recognitionSupported).toBe(true);
    });

    it('does not count a slow start as deaf once words arrive', () => {
      vi.useFakeTimers();
      const run = listen();
      vi.advanceTimersByTime(DEAF_AFTER_MS - 1);
      FakeRecognition.last?.hear(['Milch', false]);

      vi.advanceTimersByTime(DEAF_AFTER_MS);

      expect(run.error()).toBe('');
    });
  });

  // Observed on a real iPhone, in Safari and in Chrome: only the first
  // session in a page hears anything. Every iOS browser is WebKit.
  describe('on an iPhone or iPad', () => {
    const iphone =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0 Mobile/15E148 Safari/604.1';
    const mac =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36';

    it('is recognised in any browser, iPad included, and a Mac is not', () => {
      expect(isAppleMobile(iphone, 'iPhone', 5)).toBe(true);
      expect(isAppleMobile(mac, 'MacIntel', 5)).toBe(true); // iPadOS asks for the desktop site
      expect(isAppleMobile(mac, 'MacIntel', 0)).toBe(false);
    });

    it('records instead of using the recogniser', () => {
      const ua = vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(iphone);

      expect(speech.recognitionSupported).toBe(false);
      ua.mockRestore();
      expect(speech.recognitionSupported).toBe(true);
    });
  });

  it('emits nothing for a cancelled session', () => {
    const run = listen();
    FakeRecognition.last?.hear(['Milch', true]);

    speech.cancel();
    FakeRecognition.last?.onend?.();

    expect(FakeRecognition.last?.aborted).toBe(true);
    expect(run.got).toEqual([]);
    expect(speech.listening()).toBe(false);
  });

  it('treats silence as an empty result, not a broken microphone', () => {
    const run = listen();

    FakeRecognition.last?.onerror?.({ error: 'no-speech' });
    FakeRecognition.last?.onend?.();

    expect(run.error()).toBe('');
    expect(run.got).toEqual(['']);
  });

  // A result list reported twice must not double the text.
  it('rebuilds the transcript from the whole result list', () => {
    const run = listen();

    FakeRecognition.last?.hear(['Brot ', true]);
    FakeRecognition.last?.hear(['Brot ', true], ['Milch', false]);
    expect(speech.interim()).toBe('Brot Milch');

    FakeRecognition.last?.hear(['Brot ', true], ['Milch', true]);
    FakeRecognition.last?.onend?.();

    expect(run.got).toEqual(['Brot Milch']);
  });

  it('says it is capturing only once audio capture has started', () => {
    listen();
    expect(speech.capturing()).toBe(false);

    FakeRecognition.last?.onaudiostart?.();

    expect(speech.capturing()).toBe(true);
  });

  it('stops offering recognition where the browser refuses the service', () => {
    const run = listen();

    FakeRecognition.last?.onerror?.({ error: 'service-not-allowed' });

    expect(run.error()).toBe('service-not-allowed');
    expect(speech.recognitionSupported).toBe(false);
  });

  it('ignores the late end of a cancelled session once a new one has started', () => {
    const first = listen();
    const firstRecognition = FakeRecognition.last;
    speech.cancel();
    listen();

    firstRecognition?.onend?.();

    expect(first.got).toEqual([]);
    expect(speech.listening()).toBe(true);
  });

  describe('speech language', () => {
    it('follows the app language until the person picks one', () => {
      TestBed.inject(LocaleService).use('de');

      expect(speech.speechLang()).toBe('de');
    });

    // An English screen in a German supermarket.
    it('keeps a chosen language apart from the app language', () => {
      speech.setSpeechLang('de');
      TestBed.inject(LocaleService).use('en');

      expect(speech.speechLang()).toBe('de');
      expect(localStorage.getItem(SPEECH_LANG_KEY)).toBe('de');
    });
  });

  // A language added to the app must get a recogniser tag, not borrow another's.
  it('has a recogniser tag for every language the app offers', () => {
    for (const locale of environment.availableLocales) {
      expect(SPEECH_TAGS[locale], locale).toBeTruthy();
      expect(speechTag(locale).startsWith(locale)).toBe(true);
    }
  });

  it('never falls back to another language for a tag it lacks', () => {
    expect(speechTag('fr')).toBe('fr');
  });

  it('ignores a speech language the app does not offer', () => {
    speech.setSpeechLang('xx');

    expect(environment.availableLocales).toContain(speech.speechLang());
  });

  // Safari records MP4/AAC; naming it .webm mislabels it (doc 15 §15.2.4).
  it('names a recording after what was actually recorded', () => {
    expect(audioFilename('audio/mp4', 'memo')).toBe('memo.mp4');
    expect(audioFilename('audio/webm;codecs=opus', 'memo')).toBe('memo.webm');
  });
});
