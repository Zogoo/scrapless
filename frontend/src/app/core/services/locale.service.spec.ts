import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { localeInterceptor } from '../interceptors/locale.interceptor';
import { LocaleService } from './locale.service';

describe('LocaleService', () => {
  let locale: LocaleService;
  let http: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([localeInterceptor])),
        provideHttpClientTesting(),
        provideTranslateService({ fallbackLang: 'en', lang: 'en' }),
      ],
    });
    locale = TestBed.inject(LocaleService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('remembers a choice made in Settings over the browser language', () => {
    locale.use('de');

    expect(locale.initial()).toBe('de');
    expect(locale.current()).toBe('de');
  });

  it('ignores a language the app does not speak', () => {
    locale.use('fr');

    expect(locale.current()).toBe('en');
  });

  // Without this header every sentence the server writes came back English.
  it('tells the server which language to answer in', () => {
    locale.use('de');

    TestBed.inject(HttpClient).get('/api/v1/items').subscribe();

    expect(http.expectOne('/api/v1/items').request.headers.get('X-Locale')).toBe('de');
  });
});
