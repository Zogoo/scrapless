import {
  Component,
  ElementRef,
  OnDestroy,
  inject,
  signal,
  viewChild,
  ChangeDetectionStrategy,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { CaptureService } from '../../core/services/capture.service';
import { ItemsService } from '../../core/services/items.service';
import { SpeechService, audioFilename, speechTag } from '../../core/services/speech.service';
import { NotifyAsk } from '../../shared/notify-ask/notify-ask';
import { CaptureReview } from '../../core/models';
import { AutoShutter, ShutterStatus } from '../../core/vision/auto-shutter';
import { analyseFrame, toLuma } from '../../core/vision/frame-analysis';
import {
  NormBox,
  ObjectOutliner,
  OutlinerState,
  coverBox,
  detectionEnabled,
} from '../../core/vision/object-outlines';

type Mode = 'choose' | 'camera' | 'reading' | 'voice' | 'manual' | 'review';

/**
 * How long the reading screen loops before it says so. A looping animation
 * suits a 2–10 second wait; past ten seconds it stops reassuring (Nielsen,
 * "Response Times: The 3 Important Limits"; NN/g, "Progress Indicators Make a
 * Slow System Less Insufferable"). Reading a photo measured 4–16 s.
 */
export const SLOW_READ_MS = 10_000;

/**
 * Twenty perishables, big buttons, no typing (doc 2 §2.7).
 *
 * What is sent is the label, in the UI's language: "Eggs" on an English phone,
 * "Eier" on a German one. Both are in the seeded dictionary under one product,
 * so a tap costs nothing and lands on the same Kitchen line as a Bon's "EIER"
 * (spec/db/seeds_spec.rb checks every label in every locale file).
 */
export const TAP_GRID: readonly { emoji: string; key: string }[] = [
  { emoji: '🥛', key: 'milk' },
  { emoji: '🥖', key: 'bread' },
  { emoji: '🥚', key: 'eggs' },
  { emoji: '🧈', key: 'butter' },
  { emoji: '🧀', key: 'cheese' },
  { emoji: '🥦', key: 'broccoli' },
  { emoji: '🥬', key: 'spinach' },
  { emoji: '🥕', key: 'carrots' },
  { emoji: '🍅', key: 'tomatoes' },
  { emoji: '🥔', key: 'potatoes' },
  { emoji: '🧅', key: 'onions' },
  { emoji: '🍌', key: 'bananas' },
  { emoji: '🍎', key: 'apples' },
  { emoji: '🍗', key: 'chicken' },
  { emoji: '🥩', key: 'mince' },
  { emoji: '🐟', key: 'fish' },
  { emoji: '🥣', key: 'yoghurt' },
  { emoji: '🥗', key: 'salad' },
  { emoji: '🍝', key: 'pasta' },
  { emoji: '☕', key: 'coffee' },
];

@Component({
  selector: 'app-capture',
  imports: [FormsModule, TranslatePipe, NotifyAsk],
  templateUrl: './capture.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrls: ['./capture.scss', './capture-detect.scss'],
})
export class Capture implements OnDestroy {
  private readonly captures = inject(CaptureService);
  private readonly items = inject(ItemsService);
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
  protected readonly removingId = signal<number | null>(null);
  /** The photo being read, kept on screen so the wait does not look frozen. */
  protected readonly shot = signal<string | null>(null);
  protected readonly slow = signal(false);
  private slowTimer: number | null = null;
  /** Live outlines while aiming — the `?detect=1` experiment. Names come after the shot. */
  protected readonly outlines = signal<NormBox[]>([]);
  protected readonly outlinerState = signal<OutlinerState>('off');
  protected readonly detectMs = signal(0);
  private outliner: ObjectOutliner | null = null;
  private tick = 0;
  protected readonly tapGrid = TAP_GRID;
  /** Hides the notification question as soon as it is answered either way. */

  private stream: MediaStream | null = null;
  private timer: number | null = null;
  private previousLuma: Uint8ClampedArray | null = null;
  private readonly auto = new AutoShutter();
  private readonly canvas = document.createElement('canvas');

  ngOnDestroy(): void {
    this.stopCamera();
    this.clearShot();
    this.speech.cancel();
    this.outliner?.close();
    this.outliner = null;
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
    this.startOutliner();
  }

  /**
   * Never makes the camera wait: the video is already live, and outlines fade
   * in whenever the model is ready. If it never is, nothing is missing.
   */
  private startOutliner(): void {
    if (!detectionEnabled() || this.outliner || this.outlinerState() === 'loading') {
      if (this.outliner && !this.outliner.tooSlow()) this.outlinerState.set('on');
      return;
    }

    this.outlinerState.set('loading');
    ObjectOutliner.create()
      .then((outliner) => {
        this.outliner = outliner;
        this.outlinerState.set('on');
      })
      .catch(() => this.outlinerState.set('failed'));
  }

  /** Half the frame rate of the shutter check: 4 outlines a second is plenty. */
  private updateOutlines(element: HTMLVideoElement): void {
    if (!this.outliner || this.outlinerState() !== 'on' || this.tick++ % 2) return;

    const boxes = this.outliner.detect(element);
    this.detectMs.set(Math.round(this.outliner.averageMs()));
    if (!boxes) {
      this.outlinerState.set('too_slow');
      this.outlines.set([]);
      return;
    }

    const video = { w: element.videoWidth, h: element.videoHeight };
    const shown = { w: element.clientWidth, h: element.clientHeight };
    this.outlines.set(
      boxes.map((box) => coverBox(box, video, shown)).filter((b): b is NormBox => !!b),
    );
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
    this.updateOutlines(element);

    if (state.capture && this.autoShutterOn()) {
      void this.shoot();
    }
  }

  protected async shoot(): Promise<void> {
    const element = this.video()?.nativeElement;
    if (!element || this.busy()) return;

    this.stopFrameLoop();
    this.busy.set(true);

    const blob = await this.downscale(element, element.videoWidth, element.videoHeight);
    if (!blob) {
      this.busy.set(false);
      this.error.set(this.translate.instant('capture.unreadable'));
      return;
    }

    this.readPhoto(blob);
  }

  /**
   * A photo the user already has.
   *
   * Not only a convenience: without it there is no photo path at all on a
   * desktop, or on any phone where camera permission was refused. On mobile the
   * `capture` attribute opens the camera straight from here, so this doubles as
   * the fallback when getUserMedia is blocked.
   */
  protected async onFilePicked(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = ''; // so picking the same file twice still fires
    if (!file || this.busy()) return;

    this.busy.set(true);
    this.error.set('');

    try {
      const bitmap = await createImageBitmap(file);
      const blob = await this.downscale(bitmap, bitmap.width, bitmap.height);
      bitmap.close();
      if (!blob) throw new Error('could not read that image');

      this.readPhoto(blob);
    } catch {
      this.busy.set(false);
      this.error.set(this.translate.instant('capture.unreadable'));
    }
  }

  /**
   * Long edge ~2048: enough for thermal print, and it keeps the image token
   * count — and therefore the bill — down. Doc 12's pipeline step 1, and the
   * single biggest cost lever on the receipt path.
   */
  private downscale(
    source: CanvasImageSource,
    width: number,
    height: number,
  ): Promise<Blob | null> {
    const canvas = document.createElement('canvas');
    const scale = Math.min(1, 2048 / Math.max(width, height));
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    canvas.getContext('2d')?.drawImage(source, 0, 0, canvas.width, canvas.height);

    return new Promise((resolve) => canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.8));
  }

  protected retakePhoto(): void {
    this.clearShot();
    this.review.set(null);
    void this.openCamera();
  }

  /**
   * Stopping the camera blacks the video out, and reading takes seconds: a
   * black screen with nothing moving read as frozen (WCAG 2.2.2 note 4 names
   * exactly this). So the photo stays up, with a lens moving over it.
   */
  private readPhoto(blob: Blob): void {
    this.stopCamera();
    this.clearShot();
    this.shot.set(URL.createObjectURL(blob));
    this.slowTimer = window.setTimeout(() => this.slow.set(true), SLOW_READ_MS);
    this.mode.set('reading');
    this.send(this.captures.photo(blob, 'receipt'));
  }

  private clearShot(keepPhoto = false): void {
    if (this.slowTimer !== null) clearTimeout(this.slowTimer);
    this.slowTimer = null;
    this.slow.set(false);
    if (keepPhoto) return;
    const url = this.shot();
    if (url) URL.revokeObjectURL(url);
    this.shot.set(null);
  }

  private stopFrameLoop(): void {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private stopCamera(): void {
    this.stopFrameLoop();
    this.outlines.set([]);
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
  }

  // --- voice ----------------------------------------------------------------

  /** A refused microphone is a setting to change, not silence. */
  private micError(err: Error): string {
    const blocked =
      ['not-allowed', 'service-not-allowed'].includes(err?.message) ||
      err?.name === 'NotAllowedError';
    return this.translate.instant(blocked ? 'capture.mic_blocked' : 'capture.no_mic');
  }

  protected startVoice(): void {
    this.mode.set('voice');
    this.error.set('');
    this.transcript.set('');

    if (this.speech.recognitionSupported) {
      // Free path: the device does the transcription.
      this.speech.listen(speechTag(this.speech.speechLang())).subscribe({
        next: (text) => {
          this.transcript.set(text);
          if (text) this.send(this.captures.spoken(text));
        },
        error: (err: Error) => this.error.set(this.micError(err)),
      });
      return;
    }

    // Safari: no SpeechRecognition, so record and pay for a transcription.
    void this.speech.startRecording().catch((err: Error) => {
      this.error.set(this.micError(err));
      this.mode.set('choose');
    });
  }

  protected async stopVoice(): Promise<void> {
    // stop(), not abort(): abort throws away what was just said (doc 15 §15.2.1).
    if (this.speech.recognitionSupported) {
      this.speech.finish();
      return;
    }

    const recording = await this.speech.stopRecording();
    this.send(
      this.captures.spokenAudio(
        recording.blob,
        recording.seconds,
        this.speech.speechLang(),
        audioFilename(recording.mimeType, 'note'),
      ),
    );
  }

  // --- manual ---------------------------------------------------------------

  protected toggleTap(key: string): void {
    const current = this.picked();
    this.picked.set(current.includes(key) ? current.filter((k) => k !== key) : [...current, key]);
  }

  /**
   * One field and a grid of the twenty things that actually rot. Typing is last
   * on purpose — every pixel of prominence given to manual entry is a step
   * toward the death spiral that killed this category.
   */
  protected submitManual(): void {
    const typed = this.manualText().trim();
    const tapped = this.picked().map((key) => this.translate.instant(`capture.grid.${key}`));
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
        // A food photo comes back with a box per item: keep the photo so the
        // review can show the names where the food is.
        this.clearShot(result.items.some((item) => item.box));
        this.review.set(result);
        this.mode.set('review');
        this.busy.set(false);
      },
      error: (err: { message?: string }) => {
        this.clearShot();
        // The camera is off by now, so the error goes where the next try starts.
        if (this.mode() === 'reading') this.mode.set('choose');
        this.error.set(err.message ?? this.translate.instant('capture.unreadable'));
        this.busy.set(false);
      },
    });
  }

  /**
   * The review is confirm-by-default, so the user's one job is to subtract
   * (doc 4 §4.4 rule 1). A line the model invented reads as correct and would
   * otherwise sit in the kitchen until it retired itself. Removing it is not
   * waste, so this deletes rather than resolving it as Gone.
   */
  protected reject(id: number): void {
    if (this.removingId() !== null) return;

    this.removingId.set(id);
    this.error.set('');
    this.items.remove(id).subscribe({
      next: () => {
        this.removingId.set(null);
        const current = this.review();
        if (!current) return;

        const items = current.items.filter((item) => item.id !== id);
        if (items.length === 0) return this.done();
        this.review.set({ ...current, items });
      },
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? this.translate.instant('capture.unreadable'));
        this.removingId.set(null);
      },
    });
  }

  protected labelled(result: CaptureReview): boolean {
    return !!this.shot() && result.items.some((item) => item.box);
  }

  protected done(): void {
    this.clearShot();
    void this.router.navigate(['/today']);
  }

  protected back(): void {
    this.clearShot();
    this.stopCamera();
    this.speech.cancel();
    this.error.set('');
    this.mode.set('choose');
  }

  protected shutterLabel(): string {
    return this.translate.instant(`capture.shutter.${this.shutter()}`);
  }
}
