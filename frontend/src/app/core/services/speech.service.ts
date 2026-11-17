import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { SPEECH_TAGS } from '../speech-tags';
import { LocaleService } from './locale.service';

/** The vendor-prefixed shape Chrome and Safari actually expose. */
interface SpeechRecognitionLike extends EventTarget {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  start(): void;
  stop(): void;
  abort(): void;
  onresult: ((event: SpeechRecognitionResultEvent) => void) | null;
  onerror: ((event: { error: string }) => void) | null;
  onend: (() => void) | null;
  onaudiostart: (() => void) | null;
}

interface SpeechRecognitionResultEvent {
  resultIndex: number;
  results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }>;
}

type SpeechWindow = Window & {
  SpeechRecognition?: new () => SpeechRecognitionLike;
  webkitSpeechRecognition?: new () => SpeechRecognitionLike;
};

/** One of environment.availableLocales. */
export type SpeechLang = string;

/** Recognisers put spaces at either end of a piece, inconsistently. */
const squeeze = (text: string): string => text.replace(/\s+/g, ' ').trim();

export const SPEECH_LANG_KEY = 'scrapless_speech_lang';

/** The recogniser tag for one of the app's languages; never another language's. */
export function speechTag(lang: string): string {
  return SPEECH_TAGS[lang] ?? lang;
}

/** What MediaRecorder actually wrote, named so the server can tell. */
export function audioFilename(mimeType: string, base: string): string {
  if (mimeType.includes('mp4')) return `${base}.mp4`;
  if (mimeType.includes('ogg')) return `${base}.ogg`;
  return `${base}.webm`;
}

export interface Recording {
  blob: Blob;
  seconds: number;
  mimeType: string;
}

/**
 * Not failures: nothing was said, or we stopped it ourselves. Both end the
 * session with whatever was heard so far, which may be nothing.
 */
const QUIET_ERRORS = new Set(['no-speech', 'aborted']);

/**
 * Voice input, cheapest path first.
 *
 * Chrome, Android, Safari (with Siri on) and Firefox desktop all have
 * SpeechRecognition, which costs us nothing. Where it is missing — Firefox on
 * Android, an iPhone with Siri off — we record audio and pay for a
 * transcription (doc 15 §15.2.4).
 *
 * One session is one utterance (`continuous` stays false): the mic is held for
 * an item or tapped for a short list, so nothing here keeps listening across
 * pauses (doc 15 §15.6).
 */
@Injectable({ providedIn: 'root' })
export class SpeechService {
  private readonly locale = inject(LocaleService);

  readonly interim = signal('');
  /** A session is open: between start() and the end event. */
  readonly listening = signal(false);
  /** The device has started capturing audio ("audiostart"), so speaking now is heard. */
  readonly capturing = signal(false);

  private readonly chosenLang = signal<SpeechLang | null>(this.readLang());
  /** The language the person speaks, which need not be the app's language. */
  readonly speechLang = computed<SpeechLang>(() => this.chosenLang() ?? this.locale.current());

  /** The open recognition session; `cancelled` is per session, so a late end event of one cannot leak into the next. */
  private session: { recognition: SpeechRecognitionLike; cancelled: boolean } | null = null;
  private recognitionRefused = false;
  private recorder: MediaRecorder | null = null;
  private startedAt = 0;
  private chunks: Blob[] = [];
  private stream: MediaStream | null = null;

  get recognitionSupported(): boolean {
    const w = window as SpeechWindow;
    return !this.recognitionRefused && Boolean(w.SpeechRecognition ?? w.webkitSpeechRecognition);
  }

  get recordingSupported(): boolean {
    return Boolean(navigator.mediaDevices?.getUserMedia) && typeof MediaRecorder !== 'undefined';
  }

  get supported(): boolean {
    return this.recognitionSupported || this.recordingSupported;
  }

  setSpeechLang(lang: SpeechLang): void {
    if (!environment.availableLocales.includes(lang)) return;
    this.chosenLang.set(lang);
    try {
      localStorage.setItem(SPEECH_LANG_KEY, lang);
    } catch {
      /* private mode: the choice lasts for this visit */
    }
  }

  /**
   * Emits the final transcript once (possibly empty), then completes. A
   * cancelled session completes without emitting. Errors only for a real
   * failure, with the recogniser's error code as the message.
   */
  listen(lang: string): Observable<string> {
    return new Observable<string>((subscriber) => {
      const w = window as SpeechWindow;
      const Ctor = w.SpeechRecognition ?? w.webkitSpeechRecognition;
      if (!Ctor) {
        subscriber.error(new Error('unavailable'));
        return;
      }

      const recognition = new Ctor();
      const session = { recognition, cancelled: false };
      this.session = session;
      recognition.lang = lang;
      recognition.continuous = false;
      recognition.interimResults = true;

      let finalText = '';
      this.interim.set('');
      this.listening.set(true);
      this.capturing.set(false);

      recognition.onaudiostart = () => this.capturing.set(true);

      // Rebuilt from the whole list every time rather than appended to, so a
      // result reported twice cannot be counted twice.
      recognition.onresult = (event) => {
        let done = '';
        let pending = '';
        for (let i = 0; i < event.results.length; i++) {
          const result = event.results[i];
          if (result.isFinal) done += result[0].transcript;
          else pending += result[0].transcript;
        }
        finalText = squeeze(done);
        this.interim.set(squeeze(`${done} ${pending}`));
      };

      recognition.onerror = (event) => {
        if (QUIET_ERRORS.has(event.error)) return;
        // The API exists but may not be used here (reported for iOS home-screen
        // apps, doc 15 §15.2.4): from now on, record instead.
        if (event.error === 'service-not-allowed') this.recognitionRefused = true;
        this.endSession(session);
        subscriber.error(new Error(event.error));
      };

      recognition.onend = () => {
        this.endSession(session);
        if (!session.cancelled) subscriber.next(finalText.trim());
        subscriber.complete();
      };

      recognition.start();

      return () => {
        if (this.session === session) {
          session.cancelled = true;
          recognition.abort();
        }
      };
    });
  }

  /** Stop listening and keep what was heard: the spec's stop(), not abort(). */
  finish(): void {
    this.session?.recognition.stop();
  }

  async startRecording(): Promise<void> {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const chunks: Blob[] = [];
    const recorder = new MediaRecorder(stream);

    recorder.ondataavailable = (event) => {
      if (event.data.size > 0) chunks.push(event.data);
    };
    recorder.onstart = () => this.capturing.set(true);
    this.chunks = chunks;
    this.stream = stream;
    this.recorder = recorder;
    this.startedAt = Date.now();
    this.listening.set(true);
    recorder.start();
  }

  stopRecording(): Promise<Recording> {
    return new Promise((resolve, reject) => {
      const recorder = this.recorder;
      if (!recorder) {
        reject(new Error('not recording'));
        return;
      }

      recorder.onstop = () => {
        const seconds = (Date.now() - this.startedAt) / 1000;
        this.stream?.getTracks().forEach((track) => track.stop());
        this.reset();
        this.recorder = null;
        // Safari records MP4/AAC, Chrome WebM: label it as what it is.
        const mimeType = recorder.mimeType || 'audio/webm';
        resolve({ blob: new Blob(this.chunks, { type: mimeType }), seconds, mimeType });
      };

      recorder.stop();
    });
  }

  /** Throw away whatever is being heard: nothing is emitted or uploaded. */
  cancel(): void {
    if (this.session) {
      this.session.cancelled = true;
      this.session.recognition.abort();
      this.session = null;
    }
    if (this.recorder?.state === 'recording') {
      this.recorder.onstop = null;
      this.recorder.stop();
    }
    this.recorder = null;
    this.stream?.getTracks().forEach((track) => track.stop());
    this.reset();
  }

  private endSession(session: { recognition: SpeechRecognitionLike }): void {
    if (this.session !== session) return;
    this.session = null;
    this.reset();
  }

  private reset(): void {
    this.listening.set(false);
    this.capturing.set(false);
    this.interim.set('');
  }

  private readLang(): SpeechLang | null {
    try {
      const saved = localStorage.getItem(SPEECH_LANG_KEY);
      return saved && environment.availableLocales.includes(saved) ? saved : null;
    } catch {
      return null;
    }
  }
}
