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
  /** Soonest-dying first: the one to finish next, and the one actions act on. */
  packs: ScoredItem[];
  /** The pack whose headline and buttons the line shows. */
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
      const packs = [...group].sort(
        (a, b) => a.window_end.localeCompare(b.window_end) || a.id - b.id,
      );
      const level = packs.reduce((sum, pack) => sum + pack.amount_left, 0);
      return { key, packs, first: packs[0], level };
    })
    .sort(
      (a, b) => a.first.window_end.localeCompare(b.first.window_end) || a.first.id - b.first.id,
    );
}

/**
 * How a level spreads over the packs — freshest filled first, so the oldest
 * drains first. Mirrors Inventory::SetLevel so dragging previews exactly what
 * the server will store. Returned freshest → oldest, i.e. left → right.
 */
export function segments(line: KitchenLine, level = line.level): Segment[] {
  let remaining = Math.max(0, Math.min(level, line.packs.length));
  return [...line.packs].reverse().map((pack) => {
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
 * The slider track: one coloured band per pack, its length the amount left,
 * fresh (green) on the left and old (orange) on the right, then empty.
 * Length carries the meaning; colour only reinforces it (see styles.scss).
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

const FRACTIONS: Record<number, string> = { 0.25: '¼', 0.5: '½', 0.75: '¾' };

/** "1½", "¾", "2" — an amount, never a unit. */
export function formatLevel(level: number): string {
  const quarters = Math.round(level * 4) / 4;
  const whole = Math.floor(quarters);
  const fraction = FRACTIONS[quarters - whole] ?? '';
  if (!fraction) return String(whole);
  return whole === 0 ? fraction : `${whole}${fraction}`;
}
