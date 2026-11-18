import type { ObjectDetector } from '@mediapipe/tasks-vision';

/**
 * Live outlines in the viewfinder — an EXPERIMENT, off unless `?detect=1`.
 *
 * ⚠️ Doc 13 §13.2 says the camera is "deliberately not object detection". This
 * tests whether outlines while aiming are worth their cost; it does not reverse
 * that decision. If it ships, doc 13 is updated with the measured numbers.
 *
 * What it does and does not do:
 * - Draws outlines only, never names. MediaPipe's EfficientDet knows the 80
 *   COCO classes; about ten are food, and none is Milch, Gouda or Joghurt, so
 *   any name it gave would mostly be wrong. Names come from the one GPT call
 *   after the shot (Ai::ImageReader returns a box per item).
 * - Runs on the phone. Frames never leave it, and it costs nothing per frame.
 * - Loads only when the camera opens and the flag is on: the library is a lazy
 *   chunk, the WASM and model come from a CDN.
 * - Switches itself off when the phone is too slow, rather than make the
 *   viewfinder stutter.
 */

/** A box as fractions (0..1) of whatever it is relative to. */
export interface NormBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

export type OutlinerState = 'off' | 'loading' | 'on' | 'too_slow' | 'failed';

const VERSION = '1.2.2'; // keep in step with package.json
const WASM = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VERSION}/wasm`;
const MODEL =
  'https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/float16/1/efficientdet_lite0.tflite';

/** Average detection time past which outlines turn off. ~12 fps of headroom. */
export const TOO_SLOW_MS = 80;
const SAMPLE = 6;
const FLAG = 'scrapless_detect';

/**
 * `?detect=1` turns the experiment on for this browser, `?detect=0` off.
 * Remembered, so a phone on the home screen keeps it without the parameter.
 */
export function detectionEnabled(search = location.search): boolean {
  const param = new URLSearchParams(search).get('detect');
  try {
    if (param === '1') localStorage.setItem(FLAG, '1');
    if (param === '0') localStorage.removeItem(FLAG);
    return localStorage.getItem(FLAG) === '1';
  } catch {
    return param === '1';
  }
}

export class ObjectOutliner {
  private readonly timings: number[] = [];
  private lastTimestamp = 0;

  private constructor(private readonly detector: ObjectDetector) {}

  static async create(): Promise<ObjectOutliner> {
    const { FilesetResolver, ObjectDetector } = await import('@mediapipe/tasks-vision');
    const fileset = await FilesetResolver.forVisionTasks(WASM);
    const detector = await ObjectDetector.createFromOptions(fileset, {
      baseOptions: { modelAssetPath: MODEL, delegate: 'GPU' },
      runningMode: 'VIDEO',
      scoreThreshold: 0.35,
      maxResults: 8,
    });
    return new ObjectOutliner(detector);
  }

  /** Boxes as fractions of the video frame, or null once it is too slow. */
  detect(video: HTMLVideoElement): NormBox[] | null {
    if (this.tooSlow()) return null;

    // VIDEO mode needs strictly increasing timestamps.
    const now = Math.max(performance.now(), this.lastTimestamp + 1);
    this.lastTimestamp = now;

    const started = performance.now();
    const result = this.detector.detectForVideo(video, now);
    this.timings.push(performance.now() - started);
    if (this.timings.length > SAMPLE) this.timings.shift();

    const vw = video.videoWidth || 1;
    const vh = video.videoHeight || 1;
    return result.detections
      .map((d) => d.boundingBox)
      .filter((b): b is NonNullable<typeof b> => !!b)
      .map((b) => ({ x: b.originX / vw, y: b.originY / vh, w: b.width / vw, h: b.height / vh }));
  }

  tooSlow(): boolean {
    return this.timings.length >= SAMPLE && averageMs(this.timings) > TOO_SLOW_MS;
  }

  averageMs(): number {
    return averageMs(this.timings);
  }

  close(): void {
    this.detector.close();
  }
}

function averageMs(values: number[]): number {
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0;
}

/**
 * Maps a box on the video frame to the element showing it with
 * `object-fit: cover`, which crops the frame to fill the element. Returns
 * fractions of the element; parts cropped off are clamped away.
 */
export function coverBox(
  box: NormBox,
  video: { w: number; h: number },
  element: { w: number; h: number },
): NormBox | null {
  const scale = Math.max(element.w / video.w, element.h / video.h);
  const offsetX = (video.w * scale - element.w) / 2;
  const offsetY = (video.h * scale - element.h) / 2;

  const left = (box.x * video.w * scale - offsetX) / element.w;
  const top = (box.y * video.h * scale - offsetY) / element.h;
  const right = left + (box.w * video.w * scale) / element.w;
  const bottom = top + (box.h * video.h * scale) / element.h;

  const x = Math.max(0, left);
  const y = Math.max(0, top);
  const w = Math.min(1, right) - x;
  const h = Math.min(1, bottom) - y;
  return w > 0.02 && h > 0.02 ? { x, y, w, h } : null;
}
