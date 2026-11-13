import { Component, inject, signal } from '@angular/core';
import { TranslatePipe } from '@ngx-translate/core';

import { RecipesService } from '../../core/services/recipes.service';
import { Recipe } from '../../core/models';

/**
 * A few short dinners from what is already in the kitchen.
 *
 * Nothing is asked until the button is pressed. The server answers from
 * cache until the food changes, and refuses a fridge that asks too often.
 */
@Component({
  selector: 'app-recipes',
  imports: [TranslatePipe],
  templateUrl: './recipes.html',
  styleUrl: './recipes.scss',
})
export class Recipes {
  private readonly recipesApi = inject(RecipesService);

  protected readonly recipes = signal<Recipe[]>([]);
  protected readonly asked = signal(false);
  protected readonly loading = signal(false);
  protected readonly error = signal('');
  protected readonly retryable = signal(false);

  protected ask(): void {
    this.asked.set(true);
    this.loading.set(true);
    this.error.set('');
    this.retryable.set(false);

    this.recipesApi.suggest().subscribe({
      next: (page) => {
        this.recipes.set(page.recipes.slice(0, 3));
        this.loading.set(false);
      },
      error: (err: { message?: string; retryable?: boolean }) => {
        this.recipes.set([]);
        this.error.set(err.message ?? '');
        this.retryable.set(err.retryable === true);
        this.loading.set(false);
      },
    });
  }
}
