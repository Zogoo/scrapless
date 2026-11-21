import { MemoItem } from '../../core/models';

/**
 * The store sections a shopping list is walked through, in the order they
 * are shown. Each server category (Categories::NAMES) belongs to one; anything
 * unknown, or missing, is "Sonstiges".
 */
export const SECTIONS: readonly { key: string; categories: readonly string[] }[] = [
  { key: 'produce', categories: ['produce'] },
  { key: 'bakery', categories: ['bakery'] },
  { key: 'chilled', categories: ['dairy', 'deli', 'prepared'] },
  { key: 'meat_fish', categories: ['meat_fish'] },
  { key: 'frozen', categories: ['frozen'] },
  { key: 'pantry', categories: ['pantry'] },
  { key: 'drinks', categories: ['drinks'] },
  { key: 'other', categories: ['other', 'unknown'] },
];

export interface Section {
  key: string;
  items: MemoItem[];
}

export function sectionOf(category: string | null | undefined): string {
  return SECTIONS.find((s) => s.categories.includes(category ?? ''))?.key ?? 'other';
}

/** Open lines by section, in store order; a section with nothing open is left out. */
export function openSections(items: readonly MemoItem[]): Section[] {
  const open = items.filter((item) => !item.done);
  return SECTIONS.map((section) => ({
    key: section.key,
    items: open.filter((item) => sectionOf(item.category) === section.key),
  })).filter((section) => section.items.length > 0);
}

/** "2× " before the name when there is more than one. */
export function countPrefix(item: Pick<MemoItem, 'quantity'>): string {
  return (item.quantity ?? 1) > 1 ? `${item.quantity}× ` : '';
}
