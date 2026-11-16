import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { InboxEntry, NotificationsService } from '../../core/services/notifications.service';
import { PushService, PushState } from '../../core/services/push.service';
import { Bell } from './bell';

function entry(id: number, extra: Partial<InboxEntry> = {}): InboxEntry {
  return {
    id,
    title: 'Worth using tonight',
    body: `Food ${id} wants using tonight.`,
    url: `/today?n=${id}`,
    sent_on: new Date().toISOString().slice(0, 10),
    item_ids: [id],
    read: false,
    live: true,
    unread: true,
    ...extra,
  };
}

describe('Bell', () => {
  const list = signal<InboxEntry[]>([]);
  const pushState = signal<PushState>('unavailable');
  const notifications = {
    list,
    unread: () => list().filter((e) => e.unread).length,
    load: vi.fn(async () => undefined),
    readAll: vi.fn(),
  };
  const push = { state: pushState, busy: signal(false), enable: vi.fn(async () => 'on') };

  function render() {
    const fixture = TestBed.createComponent(Bell);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    const open = () => {
      el.querySelector<HTMLButtonElement>('button.bell')!.click();
      fixture.detectChanges();
    };
    return { fixture, el, open };
  }

  beforeEach(() => {
    vi.clearAllMocks();
    list.set([]);
    pushState.set('unavailable');
    TestBed.configureTestingModule({
      imports: [Bell],
      providers: [
        provideRouter([]),
        provideTranslateService(),
        { provide: NotificationsService, useValue: notifications },
        { provide: PushService, useValue: push },
      ],
    });
  });

  afterEach(() => TestBed.resetTestingModule());

  it('shows the number of unread ones, and nothing at zero', () => {
    list.set([entry(1), entry(2), entry(3, { read: true, unread: false })]);
    const { fixture, el } = render();
    expect(el.querySelector('.count')?.textContent?.trim()).toBe('2');

    list.set([entry(3, { read: true, unread: false })]);
    fixture.detectChanges();
    expect(el.querySelector('.count')).toBeNull();
  });

  it('reloads when opened and lists unread first-class, used-up dimmed', () => {
    list.set([entry(1), entry(2, { live: false, unread: false })]);
    const { el, open } = render();

    open();

    expect(notifications.load).toHaveBeenCalled();
    expect(el.querySelectorAll('.entry.unread')).toHaveLength(1);
    expect(el.querySelectorAll('.entry.done')).toHaveLength(1);
  });

  it('opens a notification where its push would', () => {
    list.set([entry(7)]);
    const { el, open, fixture } = render();
    const navigate = vi.spyOn(TestBed.inject(Router), 'navigateByUrl').mockResolvedValue(true);

    open();
    el.querySelector<HTMLButtonElement>('.entry')!.click();
    fixture.detectChanges();

    expect(navigate).toHaveBeenCalledWith('/today?n=7');
    expect(el.querySelector('#bell-panel')).toBeNull();
  });

  // The bell is where a phone without push finds out it could have it.
  it('offers push only to a phone that can still turn it on', () => {
    const { el, open, fixture } = render();
    open();
    expect(el.querySelector('footer')).toBeNull(); // no server keys

    pushState.set('off');
    fixture.detectChanges();
    el.querySelector<HTMLButtonElement>('footer button')!.click();
    expect(push.enable).toHaveBeenCalled();

    pushState.set('blocked');
    fixture.detectChanges();
    expect(el.querySelector('footer')).toBeNull();
  });

  it('closes on the backdrop and on Escape', () => {
    const { el, open, fixture } = render();

    open();
    el.querySelector<HTMLElement>('.backdrop')!.click();
    fixture.detectChanges();
    expect(el.querySelector('#bell-panel')).toBeNull();

    open();
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    fixture.detectChanges();
    expect(el.querySelector('#bell-panel')).toBeNull();
  });
});
