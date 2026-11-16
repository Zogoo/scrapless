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
import { TranslatePipe } from '@ngx-translate/core';
import { filter } from 'rxjs/operators';

import { FridgeService } from './core/services/fridge.service';
import { UndoService } from './core/services/undo.service';
import { LocaleService } from './core/services/locale.service';
import { PushService } from './core/services/push.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, TranslatePipe],
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

  protected readonly ready = signal(false);
  protected readonly showTabs = signal(false);
  protected readonly showYou = signal(false);
  /** Brand bar matches the restlos shell. Capture keeps the camera full-bleed. */
  protected readonly showBrand = signal(false);

  /** Only the id: a rename or a budget change is the same kitchen. */
  private readonly kitchenId = computed(() => this.fridge.fridge()?.id ?? null);

  constructor() {
    // Whenever this phone lands on a kitchen — boot, join, switching back, a new
    // one after forgetting — re-tell the server where to send notifications.
    // Untracked: the request's interceptors read the kitchen signal, which
    // would otherwise make every rename re-register the phone.
    effect(() => {
      if (this.kitchenId()) untracked(() => void this.push.refresh());
    });
  }

  ngOnInit(): void {
    this.locale.use(this.locale.initial());

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
