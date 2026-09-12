import { Injectable, signal } from '@angular/core';

interface InstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

const DISMISSED_KEY = 'crisper_install_dismissed';

/**
 * "Add to home screen".
 *
 * Chrome and Edge hand us a deferred prompt we can fire on a tap. iOS Safari
 * does not — there is no API at all — so the only honest thing to do there is
 * show the two-step Share-sheet instruction, which is why the iOS branch exists.
 */
@Injectable({ providedIn: 'root' })
export class InstallService {
  private deferred: InstallPromptEvent | null = null;

  readonly available = signal(false);
  readonly installed = signal(false);

  constructor() {
    this.installed.set(this.isStandalone());

    window.addEventListener('beforeinstallprompt', (event) => {
      event.preventDefault();
      this.deferred = event as InstallPromptEvent;
      this.available.set(true);
    });

    window.addEventListener('appinstalled', () => {
      this.installed.set(true);
      this.available.set(false);
      this.deferred = null;
    });
  }

  get isIos(): boolean {
    const ua = navigator.userAgent;
    // iPadOS 13+ reports as a Mac, so touch points are the giveaway.
    return /iPad|iPhone|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  }

  isStandalone(): boolean {
    return (
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as Navigator & { standalone?: boolean }).standalone === true
    );
  }

  /** True when there is something useful to say about installing. */
  shouldOffer(): boolean {
    if (this.installed() || this.dismissed()) return false;
    return this.available() || this.isIos;
  }

  async promptInstall(): Promise<boolean> {
    if (!this.deferred) return false;

    await this.deferred.prompt();
    const { outcome } = await this.deferred.userChoice;
    this.deferred = null;
    this.available.set(false);
    return outcome === 'accepted';
  }

  dismiss(): void {
    try {
      localStorage.setItem(DISMISSED_KEY, '1');
    } catch {
      /* the banner will reappear next session; harmless */
    }
    this.available.set(false);
  }

  private dismissed(): boolean {
    try {
      return localStorage.getItem(DISMISSED_KEY) === '1';
    } catch {
      return false;
    }
  }
}
