import { describe, expect, it } from 'vitest';

import { ScoredItem } from '../../core/models';
import { formatLevel, segments, toLines, trackBackground } from './kitchen-line';

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

describe('toLines', () => {
  it('folds two packs of the same food into one line, soonest-dying first', () => {
    const lines = toLines([fresh, old, pack({ id: 3, canonical_name: 'eggs' })]);

    expect(lines).toHaveLength(2);
    const milk = lines.find((l) => l.key === 'fridge:milk')!;
    expect(milk.packs.map((p) => p.id)).toEqual([1, 2]);
    expect(milk.first.id).toBe(1);
    expect(milk.level).toBe(1.5);
  });

  it('keeps frozen milk apart from fridge milk', () => {
    expect(toLines([fresh, pack({ id: 4, storage: 'freezer' })])).toHaveLength(2);
  });
});

describe('segments', () => {
  it('lays packs out fresh on the left, old on the right, and drains the right first', () => {
    const [line] = toLines([old, fresh]);

    expect(segments(line, 1.25).map((s) => [s.id, s.amount])).toEqual([
      [2, 1],
      [1, 0.25],
    ]);
  });
});

describe('trackBackground', () => {
  it('colours each pack by its freshness and greys out what is gone', () => {
    const [line] = toLines([old, fresh]);

    expect(trackBackground(line)).toBe(
      'linear-gradient(to right, var(--fresh) 0% 50%, var(--at-risk) 50% 75%, var(--surface-sunken) 75% 100%)',
    );
  });
});

describe('formatLevel', () => {
  it('says how much without a unit', () => {
    expect(formatLevel(1.5)).toBe('1½');
    expect(formatLevel(0.75)).toBe('¾');
    expect(formatLevel(2)).toBe('2');
    expect(formatLevel(0)).toBe('0');
  });
});
