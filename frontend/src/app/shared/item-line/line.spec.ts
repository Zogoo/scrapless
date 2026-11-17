import { describe, expect, it } from 'vitest';

import { ScoredItem } from '../../core/models';
import {
  levelFromPercent,
  levelPercent,
  lineFor,
  segments,
  toLines,
  trackBackground,
} from './line';

function pack(overrides: Partial<ScoredItem>): ScoredItem {
  return {
    id: 1,
    display_name: '🥛 Milk',
    canonical_name: 'milk',
    category: 'dairy',
    raw_text: null,
    quantity: null,
    unit: null,
    amount_left: 1,
    storage: 'fridge',
    acquired_on: '2026-11-10',
    window_start: '2026-11-14',
    window_end: '2026-11-18',
    days_left: 5,
    confidence: 0.6,
    state: 'active',
    opened_on: null,
    snoozed_until: null,
    high_risk: false,
    safety_date: false,
    added_by_name: null,
    presence: 0.5,
    spoilage: 0,
    risk: 0,
    phase: 'fresh',
    headline: '',
    alertable: false,
    life_fraction: 0.2,
    ...overrides,
  };
}

const old = pack({ id: 1, window_end: '2026-11-14', phase: 'at_risk', amount_left: 0.5 });
const fresh = pack({ id: 2, window_end: '2026-11-20', phase: 'fresh' });

describe('lineFor', () => {
  it('keeps the one pack the filter already selected', () => {
    const item = pack({ id: 9, amount_left: 0.5 });

    expect(lineFor(item)).toMatchObject({
      key: 'fridge:9',
      packs: [item],
      first: item,
      level: 0.5,
    });
  });
});

describe('toLines', () => {
  it('folds two packs into one line, oldest added first, actions on the soonest-dying', () => {
    const addedLaterButSooner = pack({
      id: 2,
      window_end: '2026-11-14',
      phase: 'at_risk',
      amount_left: 0.5,
    });
    const addedFirstButLater = pack({ id: 1, window_end: '2026-11-20', phase: 'fresh' });
    const lines = toLines([
      addedLaterButSooner,
      addedFirstButLater,
      pack({ id: 3, canonical_name: 'eggs' }),
    ]);

    expect(lines).toHaveLength(2);
    const milk = lines.find((l) => l.key === 'fridge:milk')!;
    expect(milk.packs.map((p) => p.id)).toEqual([1, 2]);
    expect(milk.first.id).toBe(2);
    expect(milk.level).toBe(1.5);
  });

  it('keeps frozen milk apart from fridge milk', () => {
    expect(toLines([fresh, pack({ id: 4, storage: 'freezer' })])).toHaveLength(2);
  });
});

describe('segments', () => {
  it('drains the older pack before the newer one', () => {
    const [line] = toLines([old, fresh]);

    expect(segments(line, 1.25).map((s) => [s.id, s.amount])).toEqual([
      [1, 0.25],
      [2, 1],
    ]);
  });

  it('refills the older not-yet-full pack before the newer one', () => {
    const [line] = toLines([
      pack({ id: 1, amount_left: 0.25, phase: 'at_risk' }),
      pack({ id: 2, amount_left: 1, phase: 'fresh' }),
    ]);

    expect(segments(line, 1.75).map((s) => [s.id, s.amount])).toEqual([
      [1, 0.75],
      [2, 1],
    ]);
  });
});

describe('trackBackground', () => {
  it('paints the newest pack at the left edge and the oldest against the thumb', () => {
    const [line] = toLines([old, fresh]);

    expect(trackBackground(line)).toBe(
      'linear-gradient(to right, var(--fresh) 0% 50%, var(--at-risk) 50% 75%, var(--surface-sunken) 75% 100%)',
    );
  });

  it('eats the older pack from the thumb side when the level drops', () => {
    const [line] = toLines([old, fresh]);

    expect(trackBackground(line, 1)).toBe(
      'linear-gradient(to right, var(--fresh) 0% 50%, var(--surface-sunken) 50% 100%)',
    );
  });

  it('keeps a single pack as one band from the left edge', () => {
    const line = lineFor(pack({ id: 9, phase: 'aging', amount_left: 0.75 }));

    expect(trackBackground(line)).toBe(
      'linear-gradient(to right, var(--aging) 0% 75%, var(--surface-sunken) 75% 100%)',
    );
  });
});

describe('levelPercent', () => {
  it('snaps the line to 0, 25, 50, 75, or 100', () => {
    expect(levelPercent(1.5, 2)).toBe(75);
    expect(levelPercent(0.1, 1)).toBe(0);
    expect(levelPercent(0.8, 1)).toBe(75);
    expect(levelPercent(2, 2)).toBe(100);
  });

  it('turns those stops back into a level, and 0% uses the line', () => {
    expect(levelFromPercent(50, 2)).toBe(1);
    expect(levelFromPercent(25, 1)).toBe(0.25);
    expect(levelFromPercent(0, 3)).toBe(0);
    expect(levelFromPercent(100, 3)).toBe(3);
  });
});
