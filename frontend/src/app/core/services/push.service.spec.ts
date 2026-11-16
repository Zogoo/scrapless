import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { environment } from '../../../environments/environment';
import { PushService, urlBase64ToUint8Array } from './push.service';

const KEY_URL = `${environment.apiUrl}/push_subscription/key`;
const SUBSCRIBE_URL = `${environment.apiUrl}/push_subscription`;

describe('PushService', () => {
  let service: PushService;
  let http: HttpTestingController;

  const subscription = {
    endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
    toJSON: () => ({
      endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
      keys: { p256dh: 'p', auth: 'a' },
    }),
    unsubscribe: vi.fn(async () => true),
  };
  const pushManager = {
    getSubscription: vi.fn(async (): Promise<typeof subscription | null> => null),
    subscribe: vi.fn(async () => subscription),
  };

  /** A browser with Web Push, the permission in the given state. */
  function browserWithPush(permission: NotificationPermission, answer = permission): void {
    vi.stubGlobal('PushManager', class {});
    vi.stubGlobal('Notification', {
      permission,
      requestPermission: vi.fn(async () => answer),
    });
    Object.defineProperty(navigator, 'serviceWorker', {
      value: { ready: Promise.resolve({ pushManager }) },
      configurable: true,
    });
  }

  async function refreshWithKey(key: string | null) {
    const state = service.refresh();
    http.expectOne(KEY_URL).flush({ public_key: key });
    return state;
  }

  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
    pushManager.getSubscription.mockResolvedValue(null);
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    service = TestBed.inject(PushService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    vi.unstubAllGlobals();
    Reflect.deleteProperty(navigator, 'serviceWorker');
    TestBed.resetTestingModule();
  });

  it('offers nothing when the server has no push keys', async () => {
    browserWithPush('default');

    expect(await refreshWithKey(null)).toBe('unavailable');
  });

  it('says so when the browser has no Web Push', async () => {
    expect(await refreshWithKey('BKey')).toBe('unsupported');
  });

  it('is off until this phone says yes, and then asks on the capture review', async () => {
    browserWithPush('default');

    expect(await refreshWithKey('BKey')).toBe('off');
    expect(service.shouldAsk()).toBe(true);
  });

  it('asks only once: "Not now" is remembered', async () => {
    browserWithPush('default');
    await refreshWithKey('BKey');

    service.markAsked();
    expect(service.shouldAsk()).toBe(false);
  });

  it('subscribes on yes and tells the server where to send', async () => {
    browserWithPush('default', 'granted');
    await refreshWithKey('BKey');

    const state = service.enable();
    const post = await vi.waitFor(() => http.expectOne(SUBSCRIBE_URL));
    expect(service.busy()).toBe(true); // the button says "One moment…" meanwhile
    expect(post.request.body.endpoint).toBe(subscription.endpoint);
    post.flush(null, { status: 201, statusText: 'Created' });

    expect(await state).toBe('on');
    expect(service.busy()).toBe(false);
    expect(pushManager.subscribe).toHaveBeenCalledWith(
      expect.objectContaining({ userVisibleOnly: true }),
    );
    expect(service.shouldAsk()).toBe(false);
  });

  it('respects a no', async () => {
    browserWithPush('default', 'denied');
    await refreshWithKey('BKey');

    expect(await service.enable()).toBe('blocked');
    expect(pushManager.subscribe).not.toHaveBeenCalled();
  });

  // The re-registration is what moves the phone when it switches kitchens.
  it('re-registers an existing subscription on refresh', async () => {
    browserWithPush('granted');
    pushManager.getSubscription.mockResolvedValue(subscription);

    const state = service.refresh();
    http.expectOne(KEY_URL).flush({ public_key: 'BKey' });
    const post = await vi.waitFor(() => http.expectOne(SUBSCRIBE_URL));
    post.flush(null, { status: 201, statusText: 'Created' });

    expect(await state).toBe('on');
  });

  it('turns off on this phone and on the server', async () => {
    browserWithPush('granted');
    pushManager.getSubscription.mockResolvedValue(subscription);

    const state = service.disable();
    const del = await vi.waitFor(() => http.expectOne(SUBSCRIBE_URL));
    expect(del.request.method).toBe('DELETE');
    del.flush(null, { status: 204, statusText: 'No Content' });

    expect(await state).toBe('off');
    expect(subscription.unsubscribe).toHaveBeenCalled();
  });

  it('decodes the base64url server key into bytes', () => {
    expect(Array.from(urlBase64ToUint8Array('AQID_-8'))).toEqual([1, 2, 3, 255, 239]);
  });
});
