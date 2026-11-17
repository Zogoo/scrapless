import { Component, inject, signal, ChangeDetectionStrategy } from '@angular/core';
import { TranslatePipe } from '@ngx-translate/core';

import { RecipesService } from '../../core/services/recipes.service';
import { Meal, Recipe } from '../../core/models';

/**
 * Breakfast, lunch or dinner, from what is already in the kitchen.
 *
 * Nothing is asked until a meal is tapped, and opening this tab asks nothing.
 * Each meal is generated at most once a day; a second tap shows that result.
 */
@Component({
  selector: 'app-recipes',
  imports: [TranslatePipe],
  templateUrl: './recipes.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './recipes.scss',
})
export class Recipes {
  private readonly recipesApi = inject(RecipesService);

  protected readonly meals: readonly Meal[] = ['breakfast', 'lunch', 'dinner'];
  protected readonly selected = signal<Meal | null>(null);
  protected readonly recipes = signal<Recipe[]>([]);
  protected readonly loading = signal(false);
  protected readonly error = signal('');
  protected readonly retryable = signal(false);

  protected ask(meal: Meal): void {
    this.selected.set(meal);
    this.loading.set(true);
    this.error.set('');
    this.retryable.set(false);

    this.recipesApi.suggest(meal).subscribe({
      next: (page) => {
        if (this.selected() !== meal) return;

        this.recipes.set(page.recipes.slice(0, 3));
        this.loading.set(false);
      },
      error: (err: { message?: string; retryable?: boolean }) => {
        if (this.selected() !== meal) return;

        this.recipes.set([]);
        this.error.set(err.message ?? '');
        this.retryable.set(err.retryable === true);
        this.loading.set(false);
      },
    });
  }
}
