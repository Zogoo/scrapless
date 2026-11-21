/**
 * How the Brotbox header names its day: "heute", "morgen", or the weekday
 * ("Montag"), counted from today in the kitchen's time zone, the same zone
 * the server used to pick the school day (Recipes::Suggest.school_day).
 */
export type DayWord = { kind: 'today' } | { kind: 'tomorrow' } | { kind: 'weekday'; name: string };

/** YYYY-MM-DD for "now" in a time zone. */
export function todayIn(timeZone: string, now = new Date()): string {
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(now);
  } catch {
    return new Intl.DateTimeFormat('en-CA').format(now); // an unknown zone: this phone's own date
  }
}

export function dayWord(forDate: string, today: string, locale: string): DayWord {
  const days = Math.round(
    (Date.parse(`${forDate}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 86_400_000,
  );
  if (days === 0) return { kind: 'today' };
  if (days === 1) return { kind: 'tomorrow' };
  const name = new Intl.DateTimeFormat(locale, { weekday: 'long', timeZone: 'UTC' }).format(
    new Date(`${forDate}T12:00:00Z`),
  );
  return { kind: 'weekday', name };
}
