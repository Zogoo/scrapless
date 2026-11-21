/**
 * The household's food settings: Brotboxen on school days, how it eats, and
 * foods to leave out. One place for the choices, so onboarding and Settings
 * offer the same ones.
 *
 * Never medical: these are foods to leave out, not allergies, and the wording
 * on screen stays that way.
 */
export type Diet = 'all' | 'vegetarian' | 'vegan';

/** "Keine · 1 · 2 · 3 · 4+": 4+ stores 4. */
export const BROTBOX_CHOICES: readonly number[] = [0, 1, 2, 3, 4];

export const DIETS: readonly Diet[] = ['all', 'vegetarian', 'vegan'];

/**
 * The quick choices, stored as these words whatever the phone's language, so
 * a kitchen shared by an English and a German phone means the same thing.
 * The server maps them to recipe rules (Recipes::FoodRules).
 */
export const COMMON_EXCLUSIONS: readonly string[] = [
  'Schwein',
  'Nüsse',
  'Fisch',
  'Laktose',
  'Gluten',
];

/** The chip a stored count belongs to: 5 or 6 show as 4+. */
export function brotboxChip(count: number | null | undefined): number | null {
  return count == null ? null : Math.min(count, 4);
}
