import { Component, ElementRef, OnDestroy, inject, signal, viewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { CaptureService } from '../../core/services/capture.service';
import { SpeechService, speechTag } from '../../core/services/speech.service';
import { CaptureReview } from '../../core/models';
import { AutoShutter, ShutterStatus } from '../../core/vision/auto-shutter';
import { analyseFrame, toLuma } from '../../core/vision/frame-analysis';

type Mode = 'choose' | 'camera' | 'voice' | 'manual' | 'review';

/** Twenty perishables, big buttons, no typing (doc 2 §2.7). */
const TAP_GRID = [
  '🥛 Milk',
  '🥖 Bread',
  '🥚 Eggs',
  '🧈 Butter',
  '🧀 Cheese',
  '🥦 Broccoli',
  '🥬 Spinach',
  '🥕 Carrots',
  '🍅 Tomatoes',
  '🥔 Potatoes',
  '🧅 Onions',
  '🍌 Bananas',
  '🍎 Apples',
  '🍗 Chicken',
  '🥩 Mince',
  '🐟 Fish',
  '🥣 Yoghurt',
  '🥗 Salad',
  '🍝 Pasta',
  '☕ Coffee',
];

@Component({
  selector: 'app-capture',
  imports: [FormsModule, TranslatePipe],
  templateUrl: './capture.html',
  styleUrl: './capture.scss',
})
export class Capture implements OnDestroy {
  private readonly captures = inject(CaptureService);
  private readonly router = inject(Router);
  private readonly translate = inject(TranslateService);
  protected readonly speech = inject(SpeechService);

  private readonly video = viewChild<ElementRef<HTMLVideoElement>>('video');

  protected readonly mode = signal<Mode>('choose');
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  protected readonly review = signal<CaptureReview | null>(null);
  protected readonly shutter = signal<ShutterStatus>('searching');
  protected readonly progress = signal(0);
  protected readonly autoShutterOn = signal(true);
  protected readonly transcript = signal('');
  protected readonly manualText = signal('');
  protected readonly picked = signal<string[]>([]);
  protected readonly tapGrid = TAP_GRID;

  private stream: MediaStream | null = null;
  private timer: number | null = null;
  private previousLuma: Uint8ClampedArray | null = null;
  private readonly auto = new AutoShutter();
  private readonly canvas = document.createElement('canvas');

  ngOnDestroy(): void {
    this.stopCamera();
    this.speech.cancel();
  }

  // --- camera ---------------------------------------------------------------

  protected async openCamera(): Promise<void> {
    this.mode.set('camera');
    this.error.set('');
    this.auto.reset();
    this.previousLuma = null;

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 } },
        audio: false,
      });
    } catch {
      this.error.set(this.translate.instant('capture.no_camera'));
      this.mode.set('choose');
      return;
    }

    const element = this.video()?.nativeElement;
    if (!element) return;

    element.srcObject = this.stream;
    await element.play();
    // 8fps is enough to notice a steady hand and cheap enough not to warm the
    // phone up while the user lines up a receipt.
    this.timer = window.setInterval(() => this.inspectFrame(), 125);
  }

  /**
   * Looks at the live frame and fires the shutter itself once something with
   * structure is held steady in front of the lens.
   *
   * The user never says whether it is a receipt or a shelf of food — the same
   * extraction call answers that, so asking would be friction for nothing.
   */
  private inspectFrame(): void {
    const element = this.video()?.nativeElement;
    if (!element || element.readyState < 2) return;

    const w = 128;
    const h = Math.max(2, Math.round((element.videoHeight / element.videoWidth) * w) || 96);
    this.canvas.width = w;
    this.canvas.height = h;

    const context = this.canvas.getContext('2d', { willReadFrequently: true });
    if (!context) return;

    context.drawImage(element, 0, 0, w, h);
    const luma = toLuma(context.getImageData(0, 0, w, h).data);
    const metrics = analyseFrame(luma, this.previousLuma, w, h);
    this.previousLuma = luma;

    const state = this.auto.feed(metrics);
    this.shutter.set(state.status);
    this.progress.set(state.progress);

    if (state.capture && this.autoShutterOn()) {
      void this.shoot();
    }
  }

  protected async shoot(): Promise<void> {
    const element = this.video()?.nativeElement;
    if (!element || this.busy()) return;

    this.stopFrameLoop();
    this.busy.set(true);

    const full = document.createElement('canvas');
    // Long edge ~2048: enough for thermal print, and it keeps the image token
    // count (and therefore the bill) down. Doc 12's pipeline step 1.
    const scale = Math.min(1, 2048 / Math.max(element.videoWidth, element.videoHeight));
    full.width = Math.round(element.videoWidth * scale);
    full.height = Math.round(element.videoHeight * scale);
    full.getContext('2d')?.drawImage(element, 0, 0, full.width, full.height);

    const blob = await new Promise<Blob | null>((resolve) =>
      full.toBlob((b) => resolve(b), 'image/jpeg', 0.8),
    );
    if (!blob) {
      this.busy.set(false);
      this.error.set(this.translate.instant('capture.unreadable'));
      return;
    }

    this.stopCamera();
    this.send(this.captures.photo(blob, 'receipt'));
  }

  protected retakePhoto(): void {
    this.review.set(null);
    void this.openCamera();
  }

  private stopFrameLoop(): void {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private stopCamera(): void {
    this.stopFrameLoop();
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
  }

  // --- voice ----------------------------------------------------------------

  protected startVoice(): void {
    this.mode.set('voice');
    this.error.set('');
    this.transcript.set('');

    if (this.speech.recognitionSupported) {
      // Free path: the device does the transcription.
      this.speech.listen(speechTag(this.translate.currentLang())).subscribe({
        next: (text) => {
          this.transcript.set(text);
          if (text) this.send(this.captures.spoken(text));
        },
        error: () => this.error.set(this.translate.instant('capture.no_mic')),
      });
      return;
    }

    // Safari: no SpeechRecognition, so record and pay for a transcription.
    void this.speech.startRecording().catch(() => {
      this.error.set(this.translate.instant('capture.no_mic'));
      this.mode.set('choose');
    });
  }

  protected async stopVoice(): Promise<void> {
    if (this.speech.recognitionSupported) {
      this.speech.cancel();
      return;
    }

    const recording = await this.speech.stopRecording();
    this.send(this.captures.spokenAudio(recording.blob, recording.seconds));
  }

  // --- manual ---------------------------------------------------------------

  protected toggleTap(name: string): void {
    const current = this.picked();
    this.picked.set(
      current.includes(name) ? current.filter((n) => n !== name) : [...current, name],
    );
  }

  /**
   * One field and a grid of the twenty things that actually rot. Typing is last
   * on purpose — every pixel of prominence given to manual entry is a step
   * toward the death spiral that killed this category.
   */
  protected submitManual(): void {
    const typed = this.manualText().trim();
    const tapped = this.picked().map((n) => n.replace(/^\P{L}+/u, '').trim());
    const all = [...tapped, ...(typed ? [typed] : [])].join(', ');

    if (!all) return;
    this.send(this.captures.typed(all, tapped.length && !typed ? 'grid' : 'text'));
  }

  // --- shared ---------------------------------------------------------------

  private send(request: ReturnType<CaptureService['typed']>): void {
    this.busy.set(true);
    this.error.set('');

    request.subscribe({
      next: (result) => {
        this.review.set(result);
        this.mode.set('review');
        this.busy.set(false);
      },
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? this.translate.instant('capture.unreadable'));
        this.busy.set(false);
      },
    });
  }

  protected done(): void {
    void this.router.navigate(['/today']);
  }

  protected back(): void {
    this.stopCamera();
    this.speech.cancel();
    this.error.set('');
    this.mode.set('choose');
  }

  protected shutterLabel(): string {
    return this.translate.instant(`capture.shutter.${this.shutter()}`);
  }
}
