import {
  Component,
  Injectable,
  computed,
  inject,
  signal,
  ChangeDetectionStrategy,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';

import { FridgeService } from '../../core/services/fridge.service';
import { LocaleService } from '../../core/services/locale.service';
import { RecipesService } from '../../core/services/recipes.service';
import { Meal, Recipe } from '../../core/models';
import { BROTBOX_CHOICES, DIETS, Diet } from '../../core/food-settings';
import { dayWord, todayIn } from './school-day';

/**
 * "Später" on the question card lasts until the app is reloaded: kept in
 * memory (a root service lives until then), not storage, so the next visit
 * asks again until it is answered.
 */
@Injectable({ providedIn: 'root' })
export class FoodQuestionsLater {
  readonly later = signal(false);
}

/**
 * Breakfast, the Brotbox, lunch or dinner, from what is already in the kitchen.
 * The tab is called "Essen"; the route and names stay "recipes".
 *
 * Nothing is asked until a meal is tapped, and opening this tab asks nothing.
 * Each meal is generated at most once a day; a second tap shows that result.
 */
@Component({
  selector: 'app-recipes',
  imports: [TranslatePipe, RouterLink],
  templateUrl: './recipes.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './recipes.scss',
})
export class Recipes {
  private readonly recipesApi = inject(RecipesService);
  private readonly translate = inject(TranslateService);
  private readonly locale = inject(LocaleService);
  protected readonly fridge = inject(FridgeService);

  /** Brotbox only for a kitchen that packs some; with 0 or never said it is not there. */
  protected readonly meals = computed<readonly Meal[]>(() =>
    (this.fridge.fridge()?.brotbox_count ?? 0) > 0
      ? ['breakfast', 'brotbox', 'lunch', 'dinner']
      : ['breakfast', 'lunch', 'dinner'],
  );
  protected readonly brotboxChoices = BROTBOX_CHOICES;
  protected readonly diets = DIETS;
  private readonly later = inject(FoodQuestionsLater).later;

  /**
   * For kitchens that skipped onboarding's question or existed before it:
   * only the questions still unanswered, until both are, or "Später".
   */
  protected readonly askBrotbox = computed(() => this.fridge.fridge()?.brotbox_count == null);
  protected readonly askDiet = computed(() => this.fridge.fridge()?.diet == null);
  protected readonly showQuestions = computed(
    () => !!this.fridge.fridge() && !this.later() && (this.askBrotbox() || this.askDiet()),
  );

  protected answerBrotbox(count: number): void {
    this.fridge.setFoodSettings({ brotbox_count: count }).subscribe();
  }

  protected answerDiet(diet: Diet): void {
    this.fridge.setFoodSettings({ diet }).subscribe();
  }

  protected askLater(): void {
    this.later.set(true);
  }

  /** The school day the shown Brotbox is for. */
  protected readonly forDate = signal<string | null>(null);
  protected readonly selected = signal<Meal | null>(null);
  protected readonly recipes = signal<Recipe[]>([]);
  protected readonly loading = signal(false);
  protected readonly error = signal('');
  protected readonly retryable = signal(false);
  /** No food to cook from, as opposed to no idea this time (which may be retried). */
  protected readonly kitchenEmpty = signal(false);

  /** "Brotbox für morgen · 2", over a Brotbox result. */
  protected readonly brotboxHeader = computed(() => {
    const forDate = this.forDate();
    const fridge = this.fridge.fridge();
    if (this.selected() !== 'brotbox' || !forDate || !fridge) return '';

    const word = dayWord(
      forDate,
      todayIn(fridge.timezone ?? 'Europe/Berlin'),
      this.locale.current(),
    );
    const when =
      word.kind === 'weekday' ? word.name : this.translate.instant(`recipes.day_${word.kind}`);
    return this.translate.instant('recipes.brotbox_for', {
      when,
      count: fridge.brotbox_count ?? 0,
    });
  });

  protected ask(meal: Meal): void {
    this.selected.set(meal);
    this.loading.set(true);
    this.error.set('');
    this.retryable.set(false);

    this.recipesApi.suggest(meal).subscribe({
      next: (page) => {
        if (this.selected() !== meal) return;

        this.recipes.set(page.recipes.slice(0, 3));
        this.kitchenEmpty.set(page.kitchen_empty === true);
        this.forDate.set(page.for_date ?? null);
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
