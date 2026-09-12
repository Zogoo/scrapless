export interface FrameMetrics {
  /** Mean absolute luma change against the previous frame, 0-255. */
  motion: number;
  /** Mean edge energy, 0-255. High for print and packaging, near zero for a wall. */
  detail: number;
  /** Mean luma, 0-255. */
  brightness: number;
}

/**
 * Reduces an RGBA frame to a single luma plane.
 *
 * Everything downstream works on luma: colour tells us nothing about whether a
 * receipt is in shot, and dropping it makes the per-frame cost small enough to
 * run at 8fps on a mid-range phone without warming it up.
 */
export function toLuma(rgba: Uint8ClampedArray): Uint8ClampedArray {
  const luma = new Uint8ClampedArray(rgba.length / 4);
  for (let i = 0, p = 0; i < rgba.length; i += 4, p++) {
    luma[p] = (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
  }
  return luma;
}

/**
 * How much has changed since the last frame. This is the "hold still" signal,
 * and it is the reason the shutter can fire on its own: a phone held steady over
 * a receipt looks completely different, numerically, from a phone being waved
 * around on the way to the counter.
 */
export function motionBetween(current: Uint8ClampedArray, previous: Uint8ClampedArray): number {
  if (current.length !== previous.length || current.length === 0) return 255;

  let total = 0;
  for (let i = 0; i < current.length; i++) {
    total += Math.abs(current[i] - previous[i]);
  }
  return total / current.length;
}

/**
 * Mean gradient magnitude — a cheap stand-in for "is there something with
 * structure in frame".
 *
 * Deliberately not object detection. Shipping a model to the client to tell a
 * receipt from a worktop would cost megabytes of download and battery to answer
 * a question the extraction call has to answer anyway. All the client needs to
 * know is whether it is worth spending a request at all, and an edge count
 * answers that for free.
 */
export function detailOf(luma: Uint8ClampedArray, width: number, height: number): number {
  if (width < 2 || height < 2) return 0;

  let total = 0;
  let samples = 0;
  for (let y = 0; y < height - 1; y++) {
    for (let x = 0; x < width - 1; x++) {
      const i = y * width + x;
      total += Math.abs(luma[i] - luma[i + 1]) + Math.abs(luma[i] - luma[i + width]);
      samples++;
    }
  }
  return samples === 0 ? 0 : total / samples;
}

export function brightnessOf(luma: Uint8ClampedArray): number {
  if (luma.length === 0) return 0;

  let total = 0;
  for (let i = 0; i < luma.length; i++) total += luma[i];
  return total / luma.length;
}

export function analyseFrame(
  luma: Uint8ClampedArray,
  previous: Uint8ClampedArray | null,
  width: number,
  height: number,
): FrameMetrics {
  return {
    motion: previous ? motionBetween(luma, previous) : 255,
    detail: detailOf(luma, width, height),
    brightness: brightnessOf(luma),
  };
}
