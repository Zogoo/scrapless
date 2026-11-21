import { describe, expect, it } from 'vitest';

import { MemoItem } from '../../core/models';
import { countPrefix, openSections } from './sections';

function line(id: number, category: string | undefined, done = false, quantity = 1): MemoItem {
  return {
    id,
    name: `L${id}`,
    note: null,
    done,
    source: 'text',
    position: id,
    created_at: '',
    added_by_name: null,
    category,
    quantity,
  };
}

describe('store sections', () => {
  it('groups open lines in store order and leaves out empty sections', () => {
    const sections = openSections([
      line(1, 'other'),
      line(2, 'dairy'),
      line(3, 'produce'),
      line(4, 'deli'),
      line(5, 'produce', true), // done: not in a section
    ]);

    expect(sections.map((s) => [s.key, s.items.map((i) => i.id)])).toEqual([
      ['produce', [3]],
      ['chilled', [2, 4]],
      ['other', [1]],
    ]);
  });

  it('files an unknown or missing category under Sonstiges', () => {
    expect(
      openSections([line(1, 'unknown'), line(2, undefined), line(3, 'nonsense')])[0],
    ).toMatchObject({
      key: 'other',
    });
  });

  it('shows a count only when there is more than one', () => {
    expect(countPrefix({ quantity: 2 })).toBe('2× ');
    expect(countPrefix({ quantity: 1 })).toBe('');
    expect(countPrefix({})).toBe('');
  });
});
