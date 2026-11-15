import { HttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { TranslateService } from '@ngx-translate/core';
import { afterEach, describe, expect, it } from 'vitest';

import { appConfig } from './app.config';
import { environment } from '../environments/environment';

// Boots the real providers — HTTP translation loader and every interceptor —
// which the feature specs do not. Found in QA: an interceptor that injected
// TranslateService ran on the loader's own request and blanked the whole app
// with NG0200 (circular dependency).
describe('appConfig', () => {
  afterEach(() => TestBed.resetTestingModule());

  it('loads translations through the interceptors without a circular dependency', () => {
    TestBed.configureTestingModule({
      providers: [...appConfig.providers, provideHttpClientTesting()],
    });
    const http = TestBed.inject(HttpTestingController);

    expect(() => TestBed.inject(TranslateService).use('de').subscribe()).not.toThrow();

    const load = http.expectOne('/assets/i18n/de.json');
    expect(load.request.headers.has('X-Locale')).toBe(false);
    load.flush({});
  });

  it('still sends the language with API calls', () => {
    TestBed.configureTestingModule({
      providers: [...appConfig.providers, provideHttpClientTesting()],
    });
    const http = TestBed.inject(HttpTestingController);

    TestBed.inject(HttpClient).get(`${environment.apiUrl}/items`).subscribe();

    expect(http.expectOne(`${environment.apiUrl}/items`).request.headers.has('X-Locale')).toBe(
      true,
    );
  });
});
