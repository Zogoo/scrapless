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

/** The only stops the Kitchen slider has. */
export const PERCENT_STEP = 25;

function snapPercent(percent: number): number {
  const snapped = Math.round(percent / PERCENT_STEP) * PERCENT_STEP;
  return Math.min(100, Math.max(0, snapped));
}

/** Where the thumb sits: 0, 25, 50, 75, or 100, for the whole line. */
export function levelPercent(level: number, packCount: number): number {
  if (packCount <= 0) return 0;
  return snapPercent((level / packCount) * 100);
}

/** The level the server stores for one of those five stops. 0 uses the line up. */
export function levelFromPercent(percent: number, packCount: number): number {
  return (snapPercent(percent) / 100) * packCount;
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
