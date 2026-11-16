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
  /** Oldest added first (lowest id). The slider fills this order, left to right. */
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
 * How a level spreads over the packs. Oldest added is filled first, so lowering
 * drains the most recently added pack and raising refills that pack before any
 * older one. Mirrors Inventory::SetLevel. Returned oldest → newest, left → right.
 */
export function segments(line: KitchenLine, level = line.level): Segment[] {
  let remaining = Math.max(0, Math.min(level, line.packs.length));
  return line.packs.map((pack) => {
    const amount = Math.min(remaining, 1);
    remaining -= amount;
    return { id: pack.id, phase: pack.phase, amount };
  });
}

const PHASE_TOKEN: Record<ScoredItem['phase'], string> = {
  fresh: 'var(--fresh)',
  aging: 'var(--aging)',
  at_risk: 'var(--at-risk)',
  ghost: 'var(--ghost)',
};

/**
 * The slider track: one coloured band per pack. Left is the pack added first,
 * right is the one just added (the end lowering drains), then empty. Colour is
 * that pack's freshness, not its age. Length carries the meaning (see styles.scss).
 */
export function trackBackground(line: KitchenLine, level = line.level): string {
  const total = line.packs.length;
  const stops: string[] = [];
  let at = 0;

  for (const segment of segments(line, level)) {
    if (segment.amount <= 0) continue;
    const from = (at / total) * 100;
    at += segment.amount;
    const to = (at / total) * 100;
    stops.push(`${PHASE_TOKEN[segment.phase]} ${from}% ${to}%`);
  }
  stops.push(`var(--surface-sunken) ${(at / total) * 100}% 100%`);

  return `linear-gradient(to right, ${stops.join(', ')})`;
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
