import { Component, OnInit, inject, signal, ChangeDetectionStrategy } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';
import { filter } from 'rxjs/operators';

import { FridgeService } from './core/services/fridge.service';
import { UndoService } from './core/services/undo.service';
import { LocaleService } from './core/services/locale.service';

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

  protected readonly ready = signal(false);
  protected readonly showTabs = signal(false);
  protected readonly showYou = signal(false);
  /** Brand bar matches the restlos shell. Capture keeps the camera full-bleed. */
  protected readonly showBrand = signal(false);

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
