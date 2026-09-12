import { describe, expect, it } from 'vitest';

import { AutoShutter, DEFAULT_THRESHOLDS } from './auto-shutter';
import { FrameMetrics } from './frame-analysis';

const receiptHeldSteady: FrameMetrics = { motion: 1.2, detail: 22, brightness: 140 };
const wall: FrameMetrics = { motion: 1.0, detail: 2, brightness: 150 };
const movingHand: FrameMetrics = { motion: 18, detail: 22, brightness: 140 };
const dark: FrameMetrics = { motion: 1.0, detail: 22, brightness: 12 };

function feedMany(shutter: AutoShutter, metrics: FrameMetrics, times: number) {
  let last = shutter.feed(metrics);
  for (let i = 1; i < times; i++) last = shutter.feed(metrics);
  return last;
}

describe('AutoShutter', () => {
  it('fires by itself once something is held steady in front of the lens', () => {
    const shutter = new AutoShutter();
    const state = feedMany(shutter, receiptHeldSteady, DEFAULT_THRESHOLDS.steadyFrames);

    expect(state.capture).toBe(true);
    expect(state.status).toBe('captured');
  });

  // The failure that would cost real money: firing at a worktop and paying for
  // an extraction call that finds nothing.
  it('does not fire at a blank surface, however steadily it is held', () => {
    const shutter = new AutoShutter();
    const state = feedMany(shutter, wall, 40);

    expect(state.capture).toBe(false);
    expect(state.status).toBe('searching');
  });

  it('waits while the phone is still moving', () => {
    const shutter = new AutoShutter();
    const state = feedMany(shutter, movingHand, 20);

    expect(state.capture).toBe(false);
    expect(state.status).toBe('hold_still');
  });

  it('says it is too dark rather than taking an unreadable photo', () => {
    expect(new AutoShutter().feed(dark).status).toBe('too_dark');
  });

  // A wobble mid-countdown should cost progress, not restart the whole thing —
  // otherwise it never fires for anyone with unsteady hands.
  it('decays progress on a wobble instead of starting over', () => {
    const shutter = new AutoShutter();
    feedMany(shutter, receiptHeldSteady, 4);
    const wobbled = shutter.feed(movingHand);

    expect(wobbled.progress).toBeGreaterThan(0);
    expect(wobbled.progress).toBeLessThan(4 / DEFAULT_THRESHOLDS.steadyFrames);
  });

  it('only fires once until it is reset', () => {
    const shutter = new AutoShutter();
    feedMany(shutter, receiptHeldSteady, DEFAULT_THRESHOLDS.steadyFrames);

    expect(shutter.feed(receiptHeldSteady).capture).toBe(false);

    shutter.reset();
    expect(feedMany(shutter, receiptHeldSteady, DEFAULT_THRESHOLDS.steadyFrames).capture).toBe(
      true,
    );
  });
});
