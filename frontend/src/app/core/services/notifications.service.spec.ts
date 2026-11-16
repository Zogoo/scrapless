import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { InboxEntry, NotificationsService } from './notifications.service';

const URL = `${environment.apiUrl}/notifications`;

function entry(id: number, extra: Partial<InboxEntry> = {}): InboxEntry {
  return {
    id,
    title: 'Worth using tonight',
    body: 'Spinach wants using tonight.',
    url: `/today?n=${id}`,
    sent_on: '2026-11-18',
    item_ids: [id * 10],
    read: false,
    live: true,
    unread: true,
    ...extra,
  };
}

describe('NotificationsService', () => {
  let service: NotificationsService;
  let http: HttpTestingController;

  async function loadWith(list: InboxEntry[]): Promise<void> {
    const done = service.load();
    http.expectOne(URL).flush(list);
    await done;
  }

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    service = TestBed.inject(NotificationsService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  it('counts only what is unread and still about food to use', async () => {
    await loadWith([
      entry(1),
      entry(2, { read: true, unread: false }),
      entry(3, { live: false, unread: false }),
    ]);

    expect(service.unread()).toBe(1);
  });

  it('marks one read at once and tells the server', async () => {
    await loadWith([entry(1), entry(2)]);

    service.read(1);

    expect(service.unread()).toBe(1);
    expect(service.find(1)?.read).toBe(true);
    http.expectOne(`${URL}/1/read`).flush(null, { status: 204, statusText: 'No Content' });
  });

  // Opened from the lock screen: the boot load can still be in flight.
  it('keeps a read that a crossing load does not know about yet', async () => {
    const boot = service.load();
    service.read(1);
    http.expectOne(`${URL}/1/read`).flush(null, { status: 204, statusText: 'No Content' });
    http.expectOne(URL).flush([entry(1)]);
    await boot;

    expect(service.unread()).toBe(0);
  });

  it('marks them all read', async () => {
    await loadWith([entry(1), entry(2)]);

    service.readAll();

    expect(service.unread()).toBe(0);
    http.expectOne(`${URL}/read_all`).flush(null, { status: 204, statusText: 'No Content' });
  });

  it('keeps what it had when a load fails', async () => {
    await loadWith([entry(1)]);

    const again = service.load();
    http.expectOne(URL).error(new ProgressEvent('error'));
    await again;

    expect(service.list()).toHaveLength(1);
  });

  // Switching kitchens while the old kitchen's bell is still loading.
  it('drops an answer about the kitchen it just left', async () => {
    const old = service.load();
    service.clear();
    http.expectOne(URL).flush([entry(1)]);
    await old;

    expect(service.list()).toEqual([]);

    const next = service.load();
    http.expectOne(URL).flush([entry(2)]);
    await next;
    expect(service.list().map((e) => e.id)).toEqual([2]);
  });

  it('recounts after food changes, but only when the bell holds anything', async () => {
    service.recount();
    http.expectNone(URL);

    await loadWith([entry(1)]);
    service.recount();
    http.expectOne(URL).flush([entry(1, { live: false, unread: false })]);
    await Promise.resolve();
    await Promise.resolve();

    expect(service.unread()).toBe(0);
  });

  it('empties when the kitchen is forgotten', async () => {
    await loadWith([entry(1)]);

    service.clear();

    expect(service.list()).toEqual([]);
  });
});
