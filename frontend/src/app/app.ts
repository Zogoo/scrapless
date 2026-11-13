import { Component, OnInit, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';
import { filter } from 'rxjs/operators';

import { FridgeService } from './core/services/fridge.service';
import { environment } from '../environments/environment';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, TranslatePipe],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App implements OnInit {
  protected readonly fridge = inject(FridgeService);
  private readonly router = inject(Router);
  private readonly translate = inject(TranslateService);

  protected readonly ready = signal(false);
  protected readonly showTabs = signal(false);
  protected readonly showYou = signal(false);
  /** Brand bar matches the restlos shell. Capture keeps the camera full-bleed. */
  protected readonly showBrand = signal(false);

  ngOnInit(): void {
    this.translate.use(this.preferredLocale());

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

  private preferredLocale(): string {
    const wanted = navigator.language?.slice(0, 2) ?? environment.defaultLocale;
    return environment.availableLocales.includes(wanted) ? wanted : environment.defaultLocale;
  }
}
