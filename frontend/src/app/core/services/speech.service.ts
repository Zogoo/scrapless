import { Injectable, signal } from '@angular/core';
import { Observable } from 'rxjs';

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
}

interface SpeechRecognitionResultEvent {
  resultIndex: number;
  results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }>;
}

type SpeechWindow = Window & {
  SpeechRecognition?: new () => SpeechRecognitionLike;
  webkitSpeechRecognition?: new () => SpeechRecognitionLike;
};

/** Maps our two-letter locale onto the BCP-47 tag the recogniser wants. */
export function speechTag(lang: string | null | undefined): string {
  return lang === 'de' ? 'de-DE' : 'en-GB';
}

export interface Recording {
  blob: Blob;
  seconds: number;
}

/**
 * Voice input, cheapest path first.
 *
 * Chrome and Android have SpeechRecognition built in: it is instant, it runs on
 * the device, and it costs us nothing. Safari does not, so there we record audio
 * and pay for a transcription. Roughly speaking that means we pay for iOS and
 * not for Android — which is worth knowing before reading the cost report.
 */
@Injectable({ providedIn: 'root' })
export class SpeechService {
  readonly interim = signal('');
  readonly listening = signal(false);

  private recognition: SpeechRecognitionLike | null = null;
  private recorder: MediaRecorder | null = null;
  private startedAt = 0;

  get recognitionSupported(): boolean {
    const w = window as SpeechWindow;
    return Boolean(w.SpeechRecognition ?? w.webkitSpeechRecognition);
  }

  get recordingSupported(): boolean {
    return Boolean(navigator.mediaDevices?.getUserMedia) && typeof MediaRecorder !== 'undefined';
  }

  get supported(): boolean {
    return this.recognitionSupported || this.recordingSupported;
  }

  /** Emits the final transcript once, then completes. */
  listen(lang: string): Observable<string> {
    return new Observable<string>((subscriber) => {
      const w = window as SpeechWindow;
      const Ctor = w.SpeechRecognition ?? w.webkitSpeechRecognition;
      if (!Ctor) {
        subscriber.error(new Error('speech recognition unavailable'));
        return;
      }

      const recognition = new Ctor();
      this.recognition = recognition;
      recognition.lang = lang;
      recognition.continuous = false;
      recognition.interimResults = true;

      let finalText = '';
      this.interim.set('');
      this.listening.set(true);

      recognition.onresult = (event) => {
        let interim = '';
        for (let i = event.resultIndex; i < event.results.length; i++) {
          const result = event.results[i];
          const text = result[0].transcript;
          if (result.isFinal) {
            finalText += text;
          } else {
            interim += text;
          }
        }
        this.interim.set(interim);
      };

      recognition.onerror = (event) => {
        this.listening.set(false);
        subscriber.error(new Error(event.error));
      };

      recognition.onend = () => {
        this.listening.set(false);
        this.interim.set('');
        subscriber.next(finalText.trim());
        subscriber.complete();
      };

      recognition.start();

      return () => {
        this.listening.set(false);
        recognition.abort();
      };
    });
  }

  async startRecording(): Promise<void> {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const chunks: Blob[] = [];
    const recorder = new MediaRecorder(stream);

    recorder.ondataavailable = (event) => {
      if (event.data.size > 0) chunks.push(event.data);
    };
    // Held on the instance so stopRecording can resolve with them.
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
        this.listening.set(false);
        this.recorder = null;
        resolve({ blob: new Blob(this.chunks, { type: 'audio/webm' }), seconds });
      };

      recorder.stop();
    });
  }

  cancel(): void {
    this.recognition?.abort();
    if (this.recorder?.state === 'recording') this.recorder.stop();
    this.stream?.getTracks().forEach((track) => track.stop());
    this.listening.set(false);
    this.interim.set('');
  }

  private chunks: Blob[] = [];
  private stream: MediaStream | null = null;
}
