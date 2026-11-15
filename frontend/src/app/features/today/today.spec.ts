import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { errorInterceptor } from '../../core/interceptors/error.interceptor';
import { InstallService } from '../../core/services/install.service';
import { Today } from './today';

/** The surface the test drives; these members are protected on the component. */
interface TodayScreen {
  error(): string;
  load(): void;
}

describe('Today', () => {
  let http: HttpTestingController;
  let screen: TodayScreen;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [Today],
      providers: [
        provideHttpClient(withInterceptors([errorInterceptor])),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
        // Reads matchMedia, which jsdom lacks; this test never installs anything.
        { provide: InstallService, useValue: { shouldOffer: () => false, available: () => false } },
      ],
    });
    screen = TestBed.createComponent(Today).componentInstance as unknown as TodayScreen;
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  // A phone that was offline at boot now keeps its kitchen and retries here,
  // so a retry that works must not leave "You're offline" on screen.
  it('clears the failure once a retry succeeds', () => {
    screen.load();
    http.expectOne(`${environment.apiUrl}/items`).error(new ProgressEvent('error'));
    expect(screen.error()).toContain('offline');

    screen.load();
    http.expectOne(`${environment.apiUrl}/items`).flush({
      use_first: [],
      fine_for_now: [],
      probably_gone: [],
      sweep_count: 0,
      as_of: '2026-11-15',
    });

    expect(screen.error()).toBe('');
  });

  // Observed in QA: a failed load left today() null, and the template read
  // today()!.use_first anyway — a TypeError and a blank screen under the error.
  it('renders the failure, not a crash, when the first load fails', () => {
    const fixture = TestBed.createComponent(Today);
    fixture.detectChanges();
    http
      .match(`${environment.apiUrl}/items`)
      .forEach((req) => req.error(new ProgressEvent('error')));

    expect(() => fixture.detectChanges()).not.toThrow();
    expect((fixture.nativeElement as HTMLElement).querySelector('.error')).not.toBeNull();
  });
});
