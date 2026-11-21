import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { TranslateService, provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { Meal } from '../../core/models';
import { Recipes } from './recipes';

/** The surface the test drives; these members are protected on the component. */
interface RecipesScreen {
  ask(meal: Meal): void;
}

describe('Recipes', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [Recipes],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  it('is called "Essen" in German', () => {
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('de', { recipes: { title: 'Essen' } });
    translate.use('de');
    const fixture = TestBed.createComponent(Recipes);
    fixture.detectChanges();

    expect((fixture.nativeElement as HTMLElement).querySelector('h1')?.textContent?.trim()).toBe(
      'Essen',
    );
  });

  it('does not ask for a recipe just because the tab opened', () => {
    TestBed.createComponent(Recipes);

    http.expectNone(`${environment.apiUrl}/recipes/suggest`);
  });

  it('asks for the meal that was tapped', () => {
    const screen = TestBed.createComponent(Recipes).componentInstance as unknown as RecipesScreen;

    screen.ask('breakfast');

    const req = http.expectOne(`${environment.apiUrl}/recipes/suggest`);
    expect(req.request.body).toEqual({ meal: 'breakfast' });
    req.flush({ meal: 'breakfast', recipes: [], cached: false, mode: 'stub' });
  });

  // Observed: a full kitchen at breakfast was told "nothing to cook yet, once
  // there is food here" — the empty-kitchen message, with no way to ask again.
  describe('with no recipes back', () => {
    function answer(kitchenEmpty: boolean) {
      const fixture = TestBed.createComponent(Recipes);
      (fixture.componentInstance as unknown as RecipesScreen).ask('breakfast');
      http.expectOne(`${environment.apiUrl}/recipes/suggest`).flush({
        meal: 'breakfast',
        recipes: [],
        cached: false,
        kitchen_empty: kitchenEmpty,
        mode: 'live',
      });
      fixture.detectChanges();
      return fixture.nativeElement as HTMLElement;
    }

    it('offers to try again when there is food, and asks the model again', () => {
      const root = answer(false);
      const again = root.querySelector('.calm button') as HTMLButtonElement;

      expect(root.textContent).toContain('recipes.no_idea_title');
      again.click();

      http.expectOne(`${environment.apiUrl}/recipes/suggest`).flush({
        meal: 'breakfast',
        recipes: [],
        cached: false,
        kitchen_empty: false,
        mode: 'live',
      });
    });

    it('says the kitchen is empty only when it is, with nothing to retry', () => {
      const root = answer(true);

      expect(root.textContent).toContain('recipes.empty_title');
      expect(root.querySelector('.calm button')).toBeNull();
    });
  });

  it('asks people to check the ingredients under every recipe', () => {
    const fixture = TestBed.createComponent(Recipes);
    (fixture.componentInstance as unknown as RecipesScreen).ask('dinner');
    const recipe = {
      title: 'Pfanne',
      minutes: 10,
      ingredients: [],
      steps: ['Braten.'],
      use_first_count: 0,
    };
    http.expectOne(`${environment.apiUrl}/recipes/suggest`).flush({
      meal: 'dinner',
      recipes: [recipe, { ...recipe, title: 'Suppe' }],
      cached: false,
      mode: 'live',
    });
    fixture.detectChanges();

    const cards = [...(fixture.nativeElement as HTMLElement).querySelectorAll('article.card')];
    expect(cards).toHaveLength(2);
    expect(
      cards.every((card) =>
        card.querySelector('.check')?.textContent?.includes('recipes.check_ingredients'),
      ),
    ).toBe(true);
  });
});
