import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';

/** One line in the bell: what the kitchen was told, in this phone's language. */
export interface InboxEntry {
  id: number;
  title: string;
  body: string;
  /** Where tapping it goes: the same place the push opens. */
  url: string;
  sent_on: string;
  item_ids: number[];
  /** Someone in the kitchen has opened it. Read is per kitchen, not per phone. */
  read: boolean;
  /** Some of its food is still here. */
  live: boolean;
  /** Counted on the bell: not read, and still about food to use. */
  unread: boolean;
}

/** The lock-screen notification's tag (Notifications::Message::TAG). */
const PUSH_TAG = 'scrapless-rescue';

/**
 * The bell: every notification the kitchen got, whether or not this phone
 * allowed push. Push is only how one also reaches the lock screen.
 *
 * Never polled: the server sleeps when idle and a poll would keep it awake.
 * The app reloads it when it lands on a kitchen, comes back to the
 * foreground, or hears from the service worker that a push arrived.
 */
@Injectable({ providedIn: 'root' })
export class NotificationsService {
  private readonly http = inject(HttpClient);
  private readonly url = `${environment.apiUrl}/notifications`;

  readonly list = signal<InboxEntry[]>([]);
  /** Read here, maybe not yet on the server: a load that crosses the POST must not undo it. */
  private readonly readHere = new Set<number>();
  private loading?: Promise<void>;
  /** Bumped when the kitchen changes, so an answer about the old one is dropped. */
  private kitchen = 0;
  readonly unread = computed(() => this.list().filter((entry) => entry.unread).length);

  /** Boot, Today and the bell can all ask at once; they share one request. */
  load(): Promise<void> {
    this.loading ??= this.fetch().finally(() => (this.loading = undefined));
    return this.loading;
  }

  private async fetch(): Promise<void> {
    const kitchen = this.kitchen;
    try {
      const list = await firstValueFrom(this.http.get<InboxEntry[]>(this.url));
      if (kitchen !== this.kitchen) return;
      this.list.set(list.map((entry) => (this.readHere.has(entry.id) ? asRead(entry) : entry)));
    } catch {
      return; // the bell keeps what it had; the next foreground tries again
    }
    this.syncBadge();
  }

  /** Food changed: reload, unless there is nothing in the bell it could change. */
  recount(): void {
    if (this.list().length) void this.load();
  }

  /**
   * A different kitchen, or none: empty the bell and drop any load still on
   * its way. Ids are global, so what was read here stays read.
   */
  clear(): void {
    this.kitchen++;
    this.loading = undefined;
    this.list.set([]);
    this.syncBadge();
  }

  find(id: number): InboxEntry | undefined {
    return this.list().find((entry) => entry.id === id);
  }

  /** Opened, from the bell or from the lock screen. */
  read(id: number): void {
    this.readHere.add(id);
    this.mark((entry) => entry.id === id);
    this.http.post(`${this.url}/${id}/read`, {}).subscribe({
      error: () => undefined, // shows unread again on the next load; nothing lost
    });
    void this.closeShown((url) => url.endsWith(`n=${id}`));
  }

  readAll(): void {
    this.list().forEach((entry) => this.readHere.add(entry.id));
    this.mark(() => true);
    this.http.post(`${this.url}/read_all`, {}).subscribe({ error: () => undefined });
    void this.closeShown(() => true);
  }

  private mark(match: (entry: InboxEntry) => boolean): void {
    this.list.update((list) => list.map((entry) => (match(entry) ? asRead(entry) : entry)));
    this.syncBadge();
  }

  /** The number on the app icon, where the platform has one. */
  private syncBadge(): void {
    const count = this.unread();
    const nav = navigator as Navigator & {
      setAppBadge?: (count: number) => Promise<void>;
      clearAppBadge?: () => Promise<void>;
    };
    const done = count > 0 ? nav.setAppBadge?.(count) : nav.clearAppBadge?.();
    done?.catch(() => undefined);
  }

  /** Read in the app means gone from the lock screen too. */
  private async closeShown(match: (url: string) => boolean): Promise<void> {
    try {
      const registration = await navigator.serviceWorker?.getRegistration();
      const shown = (await registration?.getNotifications({ tag: PUSH_TAG })) ?? [];
      shown.filter((n) => match(String(n.data?.url ?? ''))).forEach((n) => n.close());
    } catch {
      /* no service worker here; nothing on the lock screen to close */
    }
  }
}

function asRead(entry: InboxEntry): InboxEntry {
  return { ...entry, read: true, unread: false };
}
