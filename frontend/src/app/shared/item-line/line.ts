import { ScoredItem } from '../../core/models';

/**
 * Every pack of one food in one place, shown as a single Kitchen line.
 *
 * The server keeps a row per purchase — each has its own window, and the
 * presence model learns buying cadence from them — but nobody thinks "I have
 * milk #41 and milk #57". So the UI folds them into one line with one slider.
 */
export interface KitchenLine {
  key: string;
  /** Oldest added first (lowest id). The track paints this list in reverse. */
  packs: ScoredItem[];
  /** Soonest-dying pack: the headline, and the pack a slider touch marks opened. */
  first: ScoredItem;
  /** Total left across packs, 0..packs.length. */
  level: number;
}

export interface Segment {
  id: number;
  phase: ScoredItem['phase'];
  amount: number;
}

/** One row a screen already chose. Home's filter picks single packs; it does not regroup them. */
export function lineFor(item: ScoredItem): KitchenLine {
  return {
    key: `${item.storage}:${item.id}`,
    packs: [item],
    first: item,
    level: item.amount_left,
  };
}

export function lineKey(item: ScoredItem): string {
  return `${item.storage}:${item.canonical_name}`;
}

export function toLines(items: ScoredItem[]): KitchenLine[] {
  const byKey = new Map<string, ScoredItem[]>();
  for (const item of items) {
    // Nothing left is a used pack. It is not an empty card.
    if (item.amount_left <= 0) continue;
    const key = lineKey(item);
    byKey.set(key, [...(byKey.get(key) ?? []), item]);
  }

  return [...byKey.entries()]
    .map(([key, group]) => {
      const packs = [...group].sort((a, b) => a.id - b.id);
      const first = [...group].sort(
        (a, b) => a.window_end.localeCompare(b.window_end) || a.id - b.id,
      )[0];
      const level = packs.reduce((sum, pack) => sum + pack.amount_left, 0);
      return { key, packs, first, level };
    })
    .sort(
      (a, b) => a.first.window_end.localeCompare(b.first.window_end) || a.first.id - b.first.id,
    );
}

/**
 * How a level spreads over the packs. Newest added is filled first, so lowering
 * drains the older pack and raising refills that pack before any newer one.
 * Mirrors Inventory::SetLevel. Returned oldest → newest; the track draws the reverse.
 */
export function segments(line: KitchenLine, level = line.level): Segment[] {
  let remaining = Math.max(0, Math.min(level, line.packs.length));
  const newestFirst = [...line.packs].reverse().map((pack) => {
    const amount = Math.min(remaining, 1);
    remaining -= amount;
    return { id: pack.id, phase: pack.phase, amount };
  });
  return newestFirst.reverse();
}

export interface TrackBar {
  id: number;
  phase: ScoredItem['phase'];
  /** How much of this pack is left, 0..1. Its share of the filled track. */
  amount: number;
}

export interface TrackDraw {
  /** Width of the filled part, as a percent of the track. The rest stays empty. */
  fill: number;
  /** Newest first, so the last bar sits against the thumb. */
  bars: TrackBar[];
}

/**
 * The slider track: one bar per pack that still has some left. Newest sits at
 * the left edge, oldest flush against the thumb. A gap between bars is painted
 * by the stylesheet, so two packs of one colour stay separate. Lowering eats
 * that oldest bar. Colour is the pack's freshness, not its age.
 */
export function trackBars(line: KitchenLine, level = line.level): TrackDraw {
  const total = line.packs.length;
  const bars: TrackBar[] = [];
  let at = 0;

  if (total > 0) {
    // segments() is oldest → newest. Draw newest first so the first bite is the older pack.
    for (const segment of segments(line, level).reverse()) {
      if (segment.amount <= 0) continue;
      at += segment.amount;
      bars.push({ id: segment.id, phase: segment.phase, amount: segment.amount });
    }
  }

  return { fill: total > 0 ? (at / total) * 100 : 0, bars };
}

/**
 * Stops, in quarter-packs. Up to two packs, the line moves by 25%. Past that,
 * each step is one whole pack until two remain, and those two move by 25%.
 */
function quarterStops(packCount: number): number[] {
  if (packCount <= 0) return [0];
  if (packCount <= 2) return [0, 1, 2, 3, 4].map((step) => step * packCount);

  const stops = [0, 2, 4, 6, 8];
  for (let packs = 3; packs <= packCount; packs += 1) stops.push(packs * 4);
  return stops;
}

/** Levels the thumb can rest on, low to high. */
export function levelStops(packCount: number): number[] {
  return quarterStops(packCount).map((quarters) => quarters / 4);
}

function nearestQuarter(level: number, packCount: number, toward?: -1 | 1): number {
  const stops = quarterStops(packCount);
  const target = Math.min(packCount * 4, Math.max(0, level * 4));
  let best = stops[0];
  let bestDist = Math.abs(best - target);

  for (const stop of stops) {
    const dist = Math.abs(stop - target);
    const closer = dist < bestDist - 1e-9;
    const tie = Math.abs(dist - bestDist) <= 1e-9;
    const prefer = tie && ((toward === -1 && stop < best) || (toward !== -1 && stop > best));
    if (closer || prefer) {
      best = stop;
      bestDist = dist;
    }
  }

  return best;
}

/** Where the thumb sits, as a percent of the track. The label is not this. */
export function levelPercent(level: number, packCount: number): number {
  if (packCount <= 0) return 0;
  return (nearestQuarter(level, packCount) / 4 / packCount) * 100;
}

/**
 * The level a pointer position selects. A point halfway between two stops
 * follows the direction of the drag. 0 uses the line up.
 */
export function levelFromPercent(percent: number, packCount: number, fromPercent?: number): number {
  if (packCount <= 0) return 0;

  const clamped = Math.min(100, Math.max(0, percent));
  const toward: -1 | 1 | undefined =
    fromPercent === undefined || clamped === fromPercent
      ? undefined
      : clamped < fromPercent
        ? -1
        : 1;
  return nearestQuarter((clamped / 100) * packCount, packCount, toward) / 4;
}

/** One keyboard step: the next stop down or up. FIFO is unchanged. */
export function stepLevel(level: number, packCount: number, direction: -1 | 1): number {
  const stops = quarterStops(packCount);
  const index = stops.indexOf(nearestQuarter(level, packCount));
  const next = stops[index + direction];
  return (next ?? stops[index] ?? 0) / 4;
}

const QUARTERS = ['', '¼', '½', '¾'];

/**
 * What the bars add up to, on the same quarter stops as the slider.
 * Two full packs are "2". One pack at a quarter is "¼". One and a half is "1½".
 */
export function packAmount(level: number): string {
  const quarters = Math.max(0, Math.round(level * 4));
  const whole = Math.floor(quarters / 4);
  const fraction = QUARTERS[quarters % 4];
  if (whole === 0) return fraction || '0';

  return `${whole}${fraction}`;
}
