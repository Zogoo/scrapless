import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { Router } from '@angular/router';
import { forkJoin } from 'rxjs';
import { TranslatePipe } from '@ngx-translate/core';

import { ItemsService } from '../../core/services/items.service';
import { ScoredItem, Storage } from '../../core/models';
import { ItemLine } from '../../shared/item-line/item-line';
import { KitchenLine, toLines } from '../../shared/item-line/line';

/**
 * The full inventory, deliberately demoted to a tab you may visit twice a month.
 * Sorted by time left, never alphabetically: this is a triage queue, not a
 * database. Each line is the same card Home uses; here the packs of one food
 * in one place are grouped into it.
 */
@Component({
  selector: 'app-kitchen',
  imports: [TranslatePipe, ItemLine],
  templateUrl: './kitchen.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './kitchen.scss',
})
export class Kitchen implements OnInit {
  private readonly items = inject(ItemsService);
  private readonly router = inject(Router);

  /** "Swipe left to delete", shown until the first swipe that asks. */
  protected readonly showSwipeHint = signal(!swipeLearnedBefore());
  protected readonly loading = signal(true);
  protected readonly error = signal('');
  /** All places, until a storage button narrows the list. */
  protected readonly place = signal<'all' | Storage>('all');
  protected readonly query = signal('');

  private readonly all = computed<ScoredItem[]>(() => {
    const today = this.items.today();
    return today ? [...today.use_first, ...today.fine_for_now] : [];
  });

  private readonly lines = computed(() => toLines(this.all()));

  /** Lines that match the place and the name search together. */
  protected readonly filtered = computed(() => {
    const place = this.place();
    const q = this.query().trim().toLowerCase();
    return this.lines().filter((line) => {
      if (place !== 'all' && line.first.storage !== place) return false;
      return !q || matches(line, q);
    });
  });

  /** One line per food per place, however many packs of it there are. */
  protected readonly groups = computed(() => {
    const by: Record<Storage, KitchenLine[]> = { fridge: [], freezer: [], pantry: [] };
    for (const line of this.filtered()) by[line.first.storage].push(line);
    return by;
  });

  /** How many lines each button would show, given the current search. */
  protected readonly counts = computed(() => {
    const q = this.query().trim().toLowerCase();
    const counts = { all: 0, fridge: 0, freezer: 0, pantry: 0 };
    for (const line of this.lines()) {
      if (q && !matches(line, q)) continue;
      counts.all += 1;
      counts[line.first.storage] += 1;
    }
    return counts;
  });

  protected readonly storages: Storage[] = ['fridge', 'freezer', 'pantry'];

  /** All places, or the one selected. A search hides a place it missed. */
  protected readonly places = computed((): Storage[] => {
    const place = this.place();
    const chosen = place === 'all' ? this.storages : [place];
    if (!this.query().trim()) return chosen;
    return chosen.filter((storage) => this.groups()[storage].length > 0);
  });

  protected capture(): void {
    void this.router.navigate(['/add']);
  }

  ngOnInit(): void {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.error.set(''); // a retry that works must not keep the old failure on screen
    this.items.load().subscribe({
      next: () => this.loading.set(false),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? '');
        this.loading.set(false);
      },
    });
  }

  /** For a line read wrong, not eaten or binned: it is not waste, so it is deleted. */
  protected swipeLearned(): void {
    this.showSwipeHint.set(false);
    try {
      localStorage.setItem(SWIPE_LEARNED_KEY, '1');
    } catch {
      /* private mode: the hint just stays */
    }
  }

  protected removeLine(line: KitchenLine): void {
    forkJoin(line.packs.map((pack) => this.items.remove(pack.id))).subscribe({
      next: () => {
        this.load();
      },
      error: (err: { message?: string }) => this.error.set(err.message ?? ''),
    });
  }
}

/** A search finds a line by its title or by any pack on it ("basmati" finds "Reis"). */
function matches(line: KitchenLine, q: string): boolean {
  return [line.title, ...line.packs.map((pack) => pack.display_name)].some((name) =>
    name.toLowerCase().includes(q),
  );
}

const SWIPE_LEARNED_KEY = 'scrapless_swipe_learned';

function swipeLearnedBefore(): boolean {
  try {
    return localStorage.getItem(SWIPE_LEARNED_KEY) === '1';
  } catch {
    return false;
  }
}
