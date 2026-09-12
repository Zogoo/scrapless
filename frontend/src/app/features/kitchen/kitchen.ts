import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { TranslatePipe } from '@ngx-translate/core';

import { ItemsService } from '../../core/services/items.service';
import { Outcome, ScoredItem, Storage } from '../../core/models';

/**
 * The full inventory, deliberately demoted to a tab you may visit twice a month.
 * Sorted by time left, never alphabetically: this is a triage queue, not a
 * database.
 */
@Component({
  selector: 'app-kitchen',
  imports: [TranslatePipe],
  templateUrl: './kitchen.html',
  styleUrl: './kitchen.scss',
})
export class Kitchen implements OnInit {
  private readonly items = inject(ItemsService);

  protected readonly loading = signal(true);
  protected readonly error = signal('');
  protected readonly open = signal<Storage | null>('fridge');
  protected readonly editingId = signal<number | null>(null);
  protected readonly draftName = signal('');

  private readonly all = computed<ScoredItem[]>(() => {
    const today = this.items.today();
    return today ? [...today.use_first, ...today.fine_for_now] : [];
  });

  protected readonly groups = computed(() => {
    const by: Record<Storage, ScoredItem[]> = { fridge: [], freezer: [], pantry: [] };
    for (const item of this.all()) by[item.storage].push(item);
    return by;
  });

  protected readonly storages: Storage[] = ['fridge', 'freezer', 'pantry'];

  ngOnInit(): void {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.items.load().subscribe({
      next: () => this.loading.set(false),
      error: (err: { message?: string }) => {
        this.error.set(err.message ?? '');
        this.loading.set(false);
      },
    });
  }

  protected toggle(storage: Storage): void {
    this.open.set(this.open() === storage ? null : storage);
  }

  protected startEdit(item: ScoredItem): void {
    this.editingId.set(item.id);
    this.draftName.set(item.display_name);
  }

  /**
   * Correction must be cheaper than capture, so it is one field and one tap —
   * and it pays for itself, because the server feeds the change back into the
   * receipt dictionary.
   */
  protected saveEdit(item: ScoredItem): void {
    const name = this.draftName().trim();
    if (!name) return;

    this.items
      .correct(item.id, { display_name: name, canonical_name: name.toLowerCase() })
      .subscribe({
        next: () => {
          this.editingId.set(null);
          this.load();
        },
        error: (err: { message?: string }) => this.error.set(err.message ?? ''),
      });
  }

  protected resolve(item: ScoredItem, outcome: Outcome): void {
    this.items.resolve(item.id, outcome).subscribe({ next: () => this.load() });
  }

  protected barWidth(item: ScoredItem): string {
    return `${Math.min(100, Math.round(item.life_fraction * 100))}%`;
  }
}
