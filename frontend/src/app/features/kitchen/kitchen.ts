import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { forkJoin } from 'rxjs';
import { TranslatePipe } from '@ngx-translate/core';

import { ItemsService } from '../../core/services/items.service';
import { Outcome, ScoredItem, Storage } from '../../core/models';
import { KitchenLine, formatLevel, toLines, trackBackground } from './kitchen-line';

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
  private readonly router = inject(Router);

  protected readonly loading = signal(true);
  protected readonly error = signal('');
  protected readonly open = signal<Storage | null>('fridge');
  protected readonly editingKey = signal<string | null>(null);
  protected readonly draftName = signal('');
  /** The line being dragged and where its thumb is, before the server agrees. */
  private readonly preview = signal<{ key: string; level: number } | null>(null);

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

  protected level(line: KitchenLine): number {
    const preview = this.preview();
    return preview?.key === line.key ? preview.level : line.level;
  }

  protected track(line: KitchenLine): string {
    return trackBackground(line, this.level(line));
  }

  protected amount(line: KitchenLine): string {
    return formatLevel(this.level(line));
  }

  protected slide(line: KitchenLine, event: Event): void {
    this.preview.set({ key: line.key, level: Number((event.target as HTMLInputElement).value) });
  }

  /** Committed on release, not on every pixel of the drag. */
  protected commitLevel(line: KitchenLine, event: Event): void {
    const level = Number((event.target as HTMLInputElement).value);
    const ids = line.packs.map((pack) => pack.id);

    this.items.level(ids, level).subscribe({
      next: () => this.items.load().subscribe({ next: () => this.preview.set(null) }),
      error: (err: { message?: string }) => {
        this.preview.set(null);
        this.error.set(err.message ?? '');
      },
    });
  }

  protected resolve(item: ScoredItem, outcome: Outcome): void {
    this.items.resolve(item.id, outcome).subscribe({ next: () => this.load() });
  }
}
