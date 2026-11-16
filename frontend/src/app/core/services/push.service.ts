import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { isIosDevice } from './install.service';

/**
 * Where this phone stands on notifications.
 *
 *   unavailable    the server has no push keys; offer nothing
 *   unsupported    this browser has no Web Push
 *   needs_install  iPhone/iPad Safari: push exists only once added to the Home Screen
 *   blocked        the person said no; only the browser's own settings can undo it
 *   off / on       this phone is (not) subscribed
 */
export type PushState = 'unavailable' | 'unsupported' | 'needs_install' | 'blocked' | 'off' | 'on';

/** Answered once, on the capture review: "Not now" is remembered on this phone. */
const ASKED_KEY = 'scrapless_push_asked';
/** `serviceWorker.ready` never settles when registration failed. */
const READY_TIMEOUT_MS = 5000;

/**
 * Web Push for the one notification the product is built around (doc 4 §4.9).
 *
 * The server decides when to send and what to say; this only subscribes the
 * phone and tells the server. `enable()` must run inside a tap: Safari refuses
 * a permission prompt that does not come from one, so nothing is awaited
 * before asking.
 */
@Injectable({ providedIn: 'root' })
export class PushService {
  private readonly http = inject(HttpClient);
  private publicKey: string | null = null;

  readonly state = signal<PushState>('unavailable');

  /**
   * Works out the state and, when subscribed, tells the server again. That
   * re-registration is what moves the subscription when this phone switches
   * kitchens, and what restores it after the old kitchen was forgotten.
   */
  async refresh(): Promise<PushState> {
    try {
      const { public_key } = await firstValueFrom(
        this.http.get<{ public_key: string | null }>(`${environment.apiUrl}/push_subscription/key`),
      );
      this.publicKey = public_key;
    } catch {
      this.publicKey = null;
    }
    if (!this.publicKey) return this.set('unavailable');
    if (!this.supported()) return this.set(isIosDevice() ? 'needs_install' : 'unsupported');
    if (Notification.permission === 'denied') return this.set('blocked');

    const subscription = await this.subscription();
    if (!subscription || Notification.permission !== 'granted') return this.set('off');

    try {
      await this.register(subscription);
      return this.set('on');
    } catch {
      return this.set('off');
    }
  }

  async enable(): Promise<PushState> {
    if (!this.publicKey || !this.supported()) return this.state();

    const permission = await Notification.requestPermission();
    this.markAsked();
    if (permission !== 'granted') return this.set(permission === 'denied' ? 'blocked' : 'off');

    try {
      const registration = await this.registration();
      if (!registration) return this.set('unsupported');

      // A subscription made with an older server key cannot be reused.
      await (await registration.pushManager.getSubscription())?.unsubscribe();
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(this.publicKey),
      });
      await this.register(subscription);
      return this.set('on');
    } catch {
      return this.set('off');
    }
  }

  async disable(): Promise<PushState> {
    const subscription = await this.subscription();
    if (subscription) {
      await firstValueFrom(
        this.http.delete(`${environment.apiUrl}/push_subscription`, {
          body: { endpoint: subscription.endpoint },
        }),
      ).catch(() => undefined); // the server forgets dead endpoints on its own
      await subscription.unsubscribe();
    }
    return this.set('off');
  }

  /** The notification was tapped; `id` comes from the URL it opened. */
  opened(id: string): void {
    this.http.post(`${environment.apiUrl}/notifications/${id}/opened`, {}).subscribe({
      error: () => undefined, // a lost count, not a lost feature
    });
  }

  /** True when the capture review should ask. */
  shouldAsk(): boolean {
    const state = this.state();
    if (state !== 'off' && state !== 'needs_install') return false;
    try {
      return localStorage.getItem(ASKED_KEY) !== '1';
    } catch {
      return false;
    }
  }

  markAsked(): void {
    try {
      localStorage.setItem(ASKED_KEY, '1');
    } catch {
      /* asked again next time; harmless */
    }
  }

  private supported(): boolean {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }

  private async registration(): Promise<ServiceWorkerRegistration | null> {
    if (!this.supported()) return null;
    const timeout = new Promise<null>((resolve) =>
      setTimeout(() => resolve(null), READY_TIMEOUT_MS),
    );
    return Promise.race([navigator.serviceWorker.ready, timeout]);
  }

  private async subscription(): Promise<PushSubscription | null> {
    const registration = await this.registration();
    return registration ? registration.pushManager.getSubscription() : null;
  }

  private register(subscription: PushSubscription): Promise<unknown> {
    return firstValueFrom(
      this.http.post(`${environment.apiUrl}/push_subscription`, subscription.toJSON()),
    );
  }

  private set(state: PushState): PushState {
    this.state.set(state);
    return state;
  }
}

/** The VAPID key travels base64url-encoded; the Push API wants bytes. */
export function urlBase64ToUint8Array(base64: string): Uint8Array<ArrayBuffer> {
  const padded = (base64 + '='.repeat((4 - (base64.length % 4)) % 4))
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const raw = atob(padded);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}
