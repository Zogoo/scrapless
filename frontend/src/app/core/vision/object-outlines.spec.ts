import { describe, expect, it } from 'vitest';

import { coverBox, detectionEnabled } from './object-outlines';

describe('coverBox', () => {
  it('passes a box through when the element has the frame’s shape', () => {
    const box = coverBox(
      { x: 0.25, y: 0.25, w: 0.5, h: 0.5 },
      { w: 400, h: 300 },
      { w: 800, h: 600 },
    );

    expect(box).toEqual({ x: 0.25, y: 0.25, w: 0.5, h: 0.5 });
  });

  it('accounts for the sides a portrait viewfinder crops off a landscape frame', () => {
    // 4:3 landscape frame shown in a 3:4 portrait element: only the middle
    // 56.25% of the width is visible.
    const centred = coverBox(
      { x: 0.4, y: 0.1, w: 0.2, h: 0.8 },
      { w: 400, h: 300 },
      { w: 300, h: 400 },
    );

    expect(centred!.x).toBeCloseTo((0.4 - 0.21875) / 0.5625, 5);
    expect(centred!.w).toBeCloseTo(0.2 / 0.5625, 5);
  });

  it('drops a box that is entirely cropped off', () => {
    expect(
      coverBox({ x: 0, y: 0, w: 0.1, h: 0.5 }, { w: 400, h: 300 }, { w: 300, h: 400 }),
    ).toBeNull();
  });
});

describe('detectionEnabled', () => {
  it('is off by default and remembers ?detect=1 until ?detect=0', () => {
    localStorage.clear();
    expect(detectionEnabled('')).toBe(false);
    expect(detectionEnabled('?detect=1')).toBe(true);
    expect(detectionEnabled('')).toBe(true);
    expect(detectionEnabled('?detect=0')).toBe(false);
  });
});
