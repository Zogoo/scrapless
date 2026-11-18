import { Injectable, inject } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';

import { environment } from '../../../environments/environment';

const LOCALE_KEY = 'scrapless_locale';

/**
 * The one place the app's language is chosen and remembered.
 *
 * A choice made in Settings wins over the browser's language, and stays on
 * this phone. Everything else reads the language from here — including the
 * header that makes the server answer in it (locale.interceptor.ts).
 */
@Injectable({ providedIn: 'root' })
export class LocaleService {
  private readonly translate = inject(TranslateService);

  readonly available = environment.availableLocales;

  /** The saved choice, else the browser's language if we speak it, else the default. */
  initial(): string {
    const saved = this.read();
    if (saved && this.available.includes(saved)) return saved;

    const browser = navigator.language?.slice(0, 2) ?? '';
    return this.available.includes(browser) ? browser : environment.defaultLocale;
  }

  current(): string {
    return this.translate.currentLang() ?? environment.defaultLocale;
  }

  use(locale: string): void {
    if (!this.available.includes(locale)) return;

    this.translate.use(locale);
    // Screen readers pick their voice from <html lang>; it said "en" in German.
    document.documentElement.lang = locale;
    try {
      localStorage.setItem(LOCALE_KEY, locale);
    } catch {
      /* private mode: the choice lasts for this visit */
    }
  }

  private read(): string | null {
    try {
      return localStorage.getItem(LOCALE_KEY);
    } catch {
      return null;
    }
  }
}
