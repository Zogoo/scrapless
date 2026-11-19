import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';
import { TranslateService, provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { errorInterceptor } from '../../core/interceptors/error.interceptor';
import { InstallService } from '../../core/services/install.service';
import { PushService } from '../../core/services/push.service';
import { Today } from './today';

/** The surface the test drives; these members are protected on the component. */
interface TodayScreen {
  error(): string;
  load(): void;
  picked(): number[];
}

describe('Today', () => {
  let http: HttpTestingController;
  let screen: TodayScreen;
  const query = new BehaviorSubject(convertToParamMap({}));

  beforeEach(() => {
    query.next(convertToParamMap({}));
    TestBed.configureTestingModule({
      imports: [Today],
      providers: [
        provideHttpClient(withInterceptors([errorInterceptor])),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
        { provide: ActivatedRoute, useValue: { queryParamMap: query } },
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

  // A tap on the lock screen or in the bell opens /today?n=<id>.
  it('counts an opened notification read and points at its food', async () => {
    const fixture = TestBed.createComponent(Today);
    fixture.detectChanges();
    const empty = {
      use_first: [],
      fine_for_now: [],
      probably_gone: [],
      sweep_count: 0,
      as_of: '2026-11-18',
    };
    http.match(`${environment.apiUrl}/items`).forEach((req) => req.flush(empty));

    // The suite's own instance listens too; both count the same tap.
    query.next(convertToParamMap({ n: '7' }));
    http.match(`${environment.apiUrl}/notifications/7/read`).forEach((req) => req.flush(null));
    const opened = {
      id: 7,
      title: '',
      body: '',
      url: '/today?n=7',
      sent_on: '2026-11-18',
      item_ids: [41, 42],
      read: true,
      live: true,
      unread: false,
    };
    http.match(`${environment.apiUrl}/notifications`).forEach((req) => req.flush([opened]));
    const today = fixture.componentInstance as unknown as TodayScreen;
    await fixture.whenStable();

    expect(today.picked()).toEqual([41, 42]);
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

  // Found in the second QA pass: the heading said "Sunday" in the German UI.
  it('names the day in the app language', () => {
    TestBed.inject(TranslateService).use('de');
    const fixture = TestBed.createComponent(Today);
    fixture.detectChanges();
    http.match(`${environment.apiUrl}/items`).forEach((req) =>
      req.flush({
        use_first: [],
        fine_for_now: [],
        probably_gone: [],
        sweep_count: 0,
        as_of: '2026-11-15',
        has_captured: true,
      }),
    );
    fixture.detectChanges();

    expect((fixture.nativeElement as HTMLElement).querySelector('h1')?.textContent?.trim()).toBe(
      'Sonntag',
    );
  });

  // Home shows the same line as the Kitchen for the packs this filter already
  // chose, and leaves the fine-for-now list as a list.
  it('uses the shared line for use-first and keeps the rest of the filter', () => {
    const fixture = TestBed.createComponent(Today);
    fixture.detectChanges();
    http.match(`${environment.apiUrl}/items`).forEach((req) =>
      req.flush({
        use_first: [
          {
            id: 7,
            display_name: 'Milch',
            canonical_name: 'milch',
            storage: 'fridge',
            amount_left: 1,
            window_start: '2026-11-14',
            window_end: '2026-11-20',
            opened_on: null,
            phase: 'fresh',
            headline: 'fine for about 4 days',
            high_risk: false,
            safety_date: false,
          },
        ],
        fine_for_now: [
          {
            id: 8,
            display_name: 'Reis',
            canonical_name: 'reis',
            storage: 'pantry',
            amount_left: 1,
            window_end: '2027-01-01',
            phase: 'fresh',
            headline: 'fine',
            life_fraction: 0.1,
          },
        ],
        probably_gone: [],
        sweep_count: 0,
        as_of: '2026-11-16',
        has_captured: true,
      }),
    );
    fixture.detectChanges();

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelectorAll('app-item-line input[type="range"]')).toHaveLength(1);
    expect(root.querySelector('.rest-toggle')).not.toBeNull();
    // Half, Froze, and Used stay off the card. Sliding to 0% marks the packs used.
    expect(root.textContent).not.toContain('today.half');
    expect(root.textContent).not.toContain('today.used');
    expect(root.textContent).not.toContain('today.froze');
    expect(root.textContent).not.toContain('today.partial');
  });

  // Found on production: a kitchen stocked before notifications existed never
  // scans again, so the capture review never asked it.
  describe('the notification question', () => {
    const stocked = {
      use_first: [],
      fine_for_now: [
        {
          id: 8,
          display_name: 'Reis',
          canonical_name: 'reis',
          storage: 'pantry',
          amount_left: 1,
          window_end: '2027-01-01',
          phase: 'fresh',
          headline: 'fine',
          life_fraction: 0.1,
        },
      ],
      probably_gone: [],
      sweep_count: 0,
      as_of: '2026-11-17',
      has_captured: true,
    };
    const empty = { ...stocked, fine_for_now: [], has_captured: false };

    function render(page: object) {
      const fixture = TestBed.createComponent(Today);
      fixture.detectChanges();
      http.match(`${environment.apiUrl}/items`).forEach((req) => req.flush(page));
      fixture.detectChanges();
      return fixture;
    }

    beforeEach(() => localStorage.clear());

    it('is asked of a kitchen that already has food', () => {
      TestBed.inject(PushService).state.set('off');

      expect(render(stocked).nativeElement.querySelector('.notify-ask')).not.toBeNull();
    });

    it('waits until there is food to notify about', () => {
      TestBed.inject(PushService).state.set('off');

      expect(render(empty).nativeElement.querySelector('.notify-ask')).toBeNull();
    });

    it('is not asked where the answer is already known', () => {
      TestBed.inject(PushService).state.set('on');

      expect(render(stocked).nativeElement.querySelector('.notify-ask')).toBeNull();
    });

    it('goes away on "Not now" and stays away', () => {
      const push = TestBed.inject(PushService);
      push.state.set('off');
      const fixture = render(stocked);

      const buttons = fixture.nativeElement.querySelectorAll('.notify-actions button');
      (buttons[1] as HTMLButtonElement).click();
      fixture.detectChanges();

      expect(fixture.nativeElement.querySelector('.notify-ask')).toBeNull();
      expect(localStorage.getItem('scrapless_push_asked')).toBe('1');
    });
  });
});
