import { FrameMetrics } from './frame-analysis';

export type ShutterStatus =
  | 'searching' // nothing worth photographing in frame
  | 'too_dark'
  | 'hold_still'
  | 'steady' // locked on, counting down
  | 'captured';

export interface ShutterState {
  status: ShutterStatus;
  /** 0-1, how close to firing. Drives the ring around the shutter button. */
  progress: number;
  capture: boolean;
}

export interface ShutterThresholds {
  minBrightness: number;
  minDetail: number;
  maxMotion: number;
  /** Consecutive good frames required before firing. */
  steadyFrames: number;
}

export const DEFAULT_THRESHOLDS: ShutterThresholds = {
  // Below this a thermal receipt is unreadable anyway, so firing wastes a call.
  minBrightness: 40,
  // A blank worktop scores ~2; a receipt or a packed shelf scores well above 8.
  minDetail: 8,
  // Hand-held steady is ~1-3; deliberate movement is 10+.
  maxMotion: 4.5,
  // ~0.75s at 8fps: long enough to reject a glance, short enough not to annoy.
  steadyFrames: 6,
};

/**
 * Decides when to take the photo so the user does not have to.
 *
 * The budget for post-shop capture is 30 seconds for a whole shop (doc 2 §2.2),
 * and a tap-to-shoot camera spends a surprising amount of that on framing,
 * missing, and retaking. Holding the phone over the receipt is the only gesture
 * that survives wet hands and a bag of shopping in the other arm.
 *
 * It stays overridable: there is always a manual shutter, because an auto
 * shutter that will not fire is worse than no auto shutter at all.
 */
export class AutoShutter {
  private steady = 0;
  private fired = false;

  constructor(private readonly thresholds: ShutterThresholds = DEFAULT_THRESHOLDS) {}

  feed(metrics: FrameMetrics): ShutterState {
    if (this.fired) return { status: 'captured', progress: 1, capture: false };

    if (metrics.brightness < this.thresholds.minBrightness) {
      this.steady = 0;
      return { status: 'too_dark', progress: 0, capture: false };
    }

    if (metrics.detail < this.thresholds.minDetail) {
      this.steady = 0;
      return { status: 'searching', progress: 0, capture: false };
    }

    if (metrics.motion > this.thresholds.maxMotion) {
      // Decay rather than reset: a small wobble mid-countdown should cost
      // progress, not start the whole thing again.
      this.steady = Math.max(0, this.steady - 2);
      return { status: 'hold_still', progress: this.progress(), capture: false };
    }

    this.steady++;
    if (this.steady >= this.thresholds.steadyFrames) {
      this.fired = true;
      return { status: 'captured', progress: 1, capture: true };
    }

    return { status: 'steady', progress: this.progress(), capture: false };
  }

  reset(): void {
    this.steady = 0;
    this.fired = false;
  }

  private progress(): number {
    return Math.min(1, this.steady / this.thresholds.steadyFrames);
  }
}
