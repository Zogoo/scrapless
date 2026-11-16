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

  protected readonly loading = signal(true);
  protected readonly error = signal('');
  protected readonly editingKey = signal<string | null>(null);
  protected readonly draftName = signal('');

  private readonly all = computed<ScoredItem[]>(() => {
    const today = this.items.today();
    return today ? [...today.use_first, ...today.fine_for_now] : [];
  });

  /** One line per food per place, however many packs of it there are. */
  protected readonly groups = computed(() => {
    const by: Record<Storage, KitchenLine[]> = { fridge: [], freezer: [], pantry: [] };
    for (const line of toLines(this.all())) by[line.first.storage].push(line);
    return by;
  });

  protected readonly storages: Storage[] = ['fridge', 'freezer', 'pantry'];

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

  protected jump(storage: Storage): void {
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    document
      .getElementById(`place-${storage}`)
      ?.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
  }

  protected startEdit(line: KitchenLine): void {
    this.editingKey.set(line.key);
    this.draftName.set(line.first.display_name);
  }

  /**
   * Correction must be cheaper than capture, so it is one field and one tap —
   * and it pays for itself, because the server feeds the change back into the
   * receipt dictionary.
   */
  protected saveEdit(line: KitchenLine): void {
    const name = this.draftName().trim();
    if (!name) return;

    // A rename is about the food, not one carton of it, so every pack follows.
    const changes = { display_name: name, canonical_name: name.toLowerCase() };
    forkJoin(line.packs.map((pack) => this.items.correct(pack.id, changes))).subscribe({
      next: () => {
        this.editingKey.set(null);
        this.load();
      },
      error: (err: { message?: string }) => this.error.set(err.message ?? ''),
    });
  }

  /** For a line read wrong, not eaten or binned: it is not waste, so it is deleted. */
  protected removeLine(line: KitchenLine): void {
    forkJoin(line.packs.map((pack) => this.items.remove(pack.id))).subscribe({
      next: () => {
        this.editingKey.set(null);
        this.load();
      },
      error: (err: { message?: string }) => this.error.set(err.message ?? ''),
    });
  }
}
