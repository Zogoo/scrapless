import { describe, expect, it } from 'vitest';

import { brightnessOf, detailOf, motionBetween, toLuma } from './frame-analysis';

/** Builds an RGBA buffer from a grey-level grid. */
function frame(grid: number[][]): Uint8ClampedArray {
  const flat = grid.flat();
  const rgba = new Uint8ClampedArray(flat.length * 4);
  flat.forEach((value, i) => {
    rgba[i * 4] = value;
    rgba[i * 4 + 1] = value;
    rgba[i * 4 + 2] = value;
    rgba[i * 4 + 3] = 255;
  });
  return rgba;
}

const flat = [
  [128, 128, 128, 128],
  [128, 128, 128, 128],
  [128, 128, 128, 128],
  [128, 128, 128, 128],
];

const striped = [
  [0, 255, 0, 255],
  [255, 0, 255, 0],
  [0, 255, 0, 255],
  [255, 0, 255, 0],
];

describe('frame analysis', () => {
  it('collapses colour to a single luma plane', () => {
    expect(toLuma(frame(flat))).toHaveLength(16);
  });

  it('reports no motion between identical frames', () => {
    const luma = toLuma(frame(flat));
    expect(motionBetween(luma, luma)).toBe(0);
  });

  it('reports motion between different frames', () => {
    expect(motionBetween(toLuma(frame(flat)), toLuma(frame(striped)))).toBeGreaterThan(50);
  });

  // The distinction the auto-shutter is built on: printed text and packaging
  // score high here, an empty worktop scores near zero.
  it('separates a surface with print on it from a blank one', () => {
    const blank = detailOf(toLuma(frame(flat)), 4, 4);
    const printed = detailOf(toLuma(frame(striped)), 4, 4);

    expect(blank).toBeLessThan(1);
    expect(printed).toBeGreaterThan(100);
  });

  it('treats a first frame as maximum motion, so nothing fires on frame one', () => {
    expect(motionBetween(new Uint8ClampedArray(0), new Uint8ClampedArray(0))).toBe(255);
  });

  it('measures brightness', () => {
    // The luma weights sum to 256, so a uniform grey round-trips exactly.
    expect(brightnessOf(toLuma(frame(flat)))).toBe(128);
  });
});
