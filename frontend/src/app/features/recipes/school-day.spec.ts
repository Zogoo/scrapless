import { describe, expect, it } from 'vitest';

import { dayWord, todayIn } from './school-day';

describe('the Brotbox day', () => {
  it('is today, tomorrow, or the weekday by name', () => {
    expect(dayWord('2026-11-18', '2026-11-18', 'de')).toEqual({ kind: 'today' });
    expect(dayWord('2026-11-19', '2026-11-18', 'de')).toEqual({ kind: 'tomorrow' });
    expect(dayWord('2026-11-23', '2026-11-20', 'de')).toEqual({ kind: 'weekday', name: 'Montag' });
    expect(dayWord('2026-11-23', '2026-11-21', 'en')).toEqual({ kind: 'weekday', name: 'Monday' });
  });

  it("counts from today in the kitchen's time zone, not the phone's", () => {
    const lateInUtc = new Date('2026-11-18T23:30:00Z'); // already Thursday in Berlin

    expect(todayIn('Europe/Berlin', lateInUtc)).toBe('2026-11-19');
    expect(todayIn('UTC', lateInUtc)).toBe('2026-11-18');
  });
});
