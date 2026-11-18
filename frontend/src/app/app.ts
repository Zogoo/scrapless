import {
  Component,
  OnInit,
  computed,
  effect,
  inject,
  signal,
  untracked,
  ChangeDetectionStrategy,
} from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';
import { filter } from 'rxjs/operators';

import { FridgeService } from './core/services/fridge.service';
import { UndoService } from './core/services/undo.service';
import { LocaleService } from './core/services/locale.service';
import { PushService } from './core/services/push.service';
import { NotificationsService } from './core/services/notifications.service';
import { Bell } from './features/notifications/bell';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, TranslatePipe, Bell],
  templateUrl: './app.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './app.scss',
})
export class App implements OnInit {
  protected readonly fridge = inject(FridgeService);
  protected readonly undo = inject(UndoService);
  private readonly locale = inject(LocaleService);
  private readonly router = inject(Router);
  private readonly push = inject(PushService);
  private readonly notifications = inject(NotificationsService);
  private readonly translate = inject(TranslateService);

  protected readonly ready = signal(false);
  protected readonly showTabs = signal(false);
  protected readonly showYou = signal(false);
  /** Brand bar matches the rettich shell. Capture keeps the camera full-bleed. */
  protected readonly showBrand = signal(false);

  /** Only the id: a rename or a budget change is the same kitchen. */
  private readonly kitchenId = computed(() => this.fridge.fridge()?.id ?? null);

  constructor() {
    // Whenever this phone lands on a kitchen — boot, join, switching back, a new
    // one after forgetting — re-tell the server where to send notifications.
    // Untracked: the request's interceptors read the kitchen signal, which
    // would otherwise make every rename re-register the phone.
    effect(() => {
      const id = this.kitchenId();
      untracked(() => {
        this.notifications.clear();
        if (!id) return;
        void this.push.refresh();
        void this.notifications.load();
      });
    });
  }

  /**
   * The bell is never polled — the server sleeps when idle, and a poll would
   * keep it awake. It reloads when the app comes back to the foreground (when
   * phone apps refresh), when a push arrives while the app is open, and when
   * the language changes, since the server writes the words.
   */
  private watchNotifications(): void {
    const reload = () => {
      if (this.kitchenId()) void this.notifications.load();
    };
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') reload();
    });
    navigator.serviceWorker?.addEventListener('message', (event: MessageEvent) => {
      if (event.data?.type === 'push') reload();
    });
    this.translate.onLangChange.subscribe(reload);
  }

  ngOnInit(): void {
    this.locale.use(this.locale.initial());
    this.watchNotifications();

    this.syncChrome(this.router.url);
    // The tab bar is noise on the one screen that exists to have nothing on it.
    this.router.events.pipe(filter((event) => event instanceof NavigationEnd)).subscribe(() => {
      this.syncChrome(this.router.url);
    });

    // Resolve the fridge before the first paint so a returning user lands on
    // Today rather than flashing the onboarding question at them.
    this.fridge.restore().subscribe({
      next: () => this.ready.set(true),
      error: () => this.ready.set(true),
    });
  }

  private syncChrome(url: string): void {
    const path = url.split('?')[0];
    this.showTabs.set(!path.startsWith('/welcome'));
    this.showBrand.set(this.showTabs() && !path.startsWith('/add'));
    this.showYou.set(['/today', '/recipes', '/memo', '/kitchen'].includes(path));
  }
}
