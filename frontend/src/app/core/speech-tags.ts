/**
 * The BCP-47 tag the browser's recogniser is given for each of the app's
 * languages (environment.availableLocales). A regional tag picks the accent
 * model the recogniser uses.
 *
 * A language missing here is still recognised in that language — the plain
 * locale code is a valid tag too — never silently in another one. The spec
 * fails if an available locale has no entry.
 */
export const SPEECH_TAGS: Readonly<Record<string, string>> = {
  en: 'en-GB',
  de: 'de-DE',
};
