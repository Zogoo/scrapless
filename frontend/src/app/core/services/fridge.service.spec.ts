import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { actorInterceptor } from '../interceptors/actor.interceptor';
import { fridgeInterceptor } from '../interceptors/fridge.interceptor';
import { Fridge } from '../models';
import { ActorService } from './actor.service';
import { FridgeService, joinCodeFromLocation, kitchenShareUrl } from './fridge.service';

const shared: Fridge = {
  id: 'fridge-1',
  name: 'Quiet Kitchen',
  token: 'bearer-secret',
  join_code: 'join-code',
  locale: 'en',
  alerts_per_week: 1,
  created_at: '2026-11-12T00:00:00Z',
};

describe('kitchenShareUrl', () => {
  it('puts the join code in the fragment and leaves the bearer token out', () => {
    const url = kitchenShareUrl('https://scrapless.test/', shared.join_code);

    expect(url).toBe('https://scrapless.test/join#join-code');
    expect(url).not.toContain(shared.token);
  });
});

describe('joinCodeFromLocation', () => {
  it('reads the fragment Angular kept', () => {
    expect(joinCodeFromLocation('join-code', '')).toBe('join-code');
  });

  it('falls back to the raw hash when the router has no fragment', () => {
    expect(joinCodeFromLocation(null, '#join%2Dcode')).toBe('join-code');
  });
});

describe('FridgeService', () => {
  let service: FridgeService;
  let http: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([fridgeInterceptor, actorInterceptor])),
        provideHttpClientTesting(),
      ],
    });
    service = TestBed.inject(FridgeService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('stores the shared kitchen token when a join code is redeemed', () => {
    localStorage.setItem('scrapless_token', 'old-token');

    service.join('join-code').subscribe();

    const req = http.expectOne(`${environment.apiUrl}/fridge/join`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ join_code: 'join-code' });
    expect(req.request.headers.get('Authorization')).toBe('Bearer old-token');
    expect(req.request.headers.get('X-Actor-Name')).toBeNull();
    req.flush(shared);

    expect(service.token).toBe('bearer-secret');
    expect(service.fridge()?.name).toBe('Quiet Kitchen');
  });

  // Joining used to strand the kitchen this phone was on.
  it('remembers the kitchen it left, and can go back to it', () => {
    const own = { ...shared, id: 'own', name: 'Own Kitchen', token: 'own-token' };
    service.restore().subscribe();
    http.expectOne(`${environment.apiUrl}/fridge`).flush(own);

    service.join('join-code').subscribe();
    http.expectOne(`${environment.apiUrl}/fridge/join`).flush(shared);
    expect(service.previous()).toEqual({ token: 'own-token', name: 'Own Kitchen' });

    service.switchBack().subscribe();
    const back = http.expectOne(`${environment.apiUrl}/fridge`);
    expect(back.request.headers.get('Authorization')).toBe('Bearer own-token');
    back.flush(own);

    expect(service.fridge()?.name).toBe('Own Kitchen');
    expect(service.previous()).toEqual({ token: 'bearer-secret', name: 'Quiet Kitchen' });
  });

  it('forgets the token when the server does not know the fridge', () => {
    localStorage.setItem('scrapless_token', 'stale-token');
    let result: Fridge | null | undefined;

    service.restore().subscribe((found) => (result = found));
    http
      .expectOne(`${environment.apiUrl}/fridge`)
      .flush({ error: 'no fridge' }, { status: 401, statusText: 'Unauthorized' });

    expect(result).toBeNull();
    expect(service.token).toBeNull();
  });

  // Offline, a 5xx or a machine still waking must not cost the phone its kitchen.
  it.each([
    [0, 'Unknown Error'],
    [503, 'Service Unavailable'],
  ])('keeps the token when the boot request fails with %s', (status, statusText) => {
    localStorage.setItem('scrapless_token', 'bearer-secret');
    let failed = false;

    service.restore().subscribe({ error: () => (failed = true) });
    http.expectOne(`${environment.apiUrl}/fridge`).flush(null, { status, statusText });

    expect(failed).toBe(true);
    expect(service.token).toBe('bearer-secret');
  });
});

describe('actor name on adds', () => {
  let http: HttpTestingController;
  let client: HttpClient;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([fridgeInterceptor, actorInterceptor])),
        provideHttpClientTesting(),
      ],
    });
    TestBed.inject(ActorService).setName('Mama');
    client = TestBed.inject(HttpClient);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('sends the name with a capture and a memo line', () => {
    client.post(`${environment.apiUrl}/captures`, { source: 'text', text: 'milk' }).subscribe();
    client.post(`${environment.apiUrl}/memo`, { name: 'Milk' }).subscribe();
    client.post(`${environment.apiUrl}/memo/dictate`, { transcript: 'bread' }).subscribe();
    client.get(`${environment.apiUrl}/memo`).subscribe();

    const capture = http.expectOne(`${environment.apiUrl}/captures`);
    const memo = http.expectOne(
      (req) => req.url === `${environment.apiUrl}/memo` && req.method === 'POST',
    );
    const dictate = http.expectOne(`${environment.apiUrl}/memo/dictate`);
    const list = http.expectOne(
      (req) => req.url === `${environment.apiUrl}/memo` && req.method === 'GET',
    );

    expect(capture.request.headers.get('X-Actor-Name')).toBe(encodeURIComponent('Mama'));
    expect(memo.request.headers.get('X-Actor-Name')).toBe(encodeURIComponent('Mama'));
    expect(dictate.request.headers.get('X-Actor-Name')).toBe(encodeURIComponent('Mama'));
    expect(list.request.headers.get('X-Actor-Name')).toBeNull();

    capture.flush({});
    memo.flush({});
    dictate.flush({});
    list.flush({});
  });
});
