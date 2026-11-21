import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { TranslateService, provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { environment } from '../../../environments/environment';
import { Fridge, Meal } from '../../core/models';
import { FridgeService } from '../../core/services/fridge.service';
import { Recipes } from './recipes';

/** The surface the test drives; these members are protected on the component. */
interface RecipesScreen {
  ask(meal: Meal): void;
}

function kitchen(brotboxCount: number | null): Fridge {
  return {
    id: 'k',
    name: 'Küche',
    token: 't',
    join_code: 'j',
    locale: 'de',
    timezone: 'Europe/Berlin',
    alerts_per_week: 1,
    brotbox_count: brotboxCount,
    diet: 'all',
    excluded_foods: [],
    created_at: '',
  };
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

  describe('the Brotbox', () => {
    const recipe = {
      title: 'Käsehäppchen',
      minutes: 5,
      ingredients: [],
      steps: ['Schneiden.'],
      use_first_count: 0,
    };

    function render(brotboxCount: number | null) {
      (TestBed.inject(FridgeService) as unknown as { accept(f: Fridge): void }).accept(
        kitchen(brotboxCount),
      );
      const translate = TestBed.inject(TranslateService);
      translate.setTranslation('de', {
        recipes: {
          brotbox: 'Brotbox',
          brotbox_for: 'Brotbox für {{when}} · {{count}}',
          day_today: 'heute',
          day_tomorrow: 'morgen',
        },
      });
      translate.use('de');
      const fixture = TestBed.createComponent(Recipes);
      fixture.detectChanges();
      const root = fixture.nativeElement as HTMLElement;
      const meals = () => [...root.querySelectorAll<HTMLButtonElement>('.meals button')];
      return {
        fixture,
        root,
        meals,
        screen: fixture.componentInstance as unknown as RecipesScreen,
      };
    }

    afterEach(() => vi.useRealTimers());

    it('shows no Brotbox to a kitchen that packs none or never said', () => {
      for (const count of [0, null]) {
        const { meals } = render(count);
        expect(meals().map((m) => m.textContent!.trim())).not.toContain('Brotbox');
        TestBed.resetTestingModule();
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
      }
    });

    it('offers Frühstück, Brotbox, Mittag and Abend to a kitchen with two boxes', () => {
      const { meals } = render(2);

      expect(meals().map((m) => m.textContent!.trim())).toEqual([
        'recipes.breakfast',
        'Brotbox',
        'recipes.lunch',
        'recipes.dinner',
      ]);
    });

    it('heads an evening Brotbox "Brotbox für morgen · 2"', () => {
      vi.useFakeTimers({ toFake: ['Date'] });
      vi.setSystemTime(new Date('2026-11-18T17:30:00+01:00')); // Wednesday evening, Berlin
      const { fixture, root, screen } = render(2);

      screen.ask('brotbox');
      http.expectOne(`${environment.apiUrl}/recipes/suggest`).flush({
        meal: 'brotbox',
        recipes: [recipe],
        cached: false,
        for_date: '2026-11-19',
        mode: 'live',
      });
      fixture.detectChanges();

      expect(root.querySelector('.for-day')?.textContent?.trim()).toBe('Brotbox für morgen · 2');
    });
  });

  // Once a day: no buttons under a result ask the model again.
  it('offers no way to ask again under a result', () => {
    const fixture = TestBed.createComponent(Recipes);
    (fixture.componentInstance as unknown as RecipesScreen).ask('dinner');
    const recipe = {
      title: 'Pfanne',
      minutes: 10,
      ingredients: [],
      steps: ['Braten.'],
      use_first_count: 0,
    };
    http
      .expectOne(`${environment.apiUrl}/recipes/suggest`)
      .flush({ meal: 'dinner', recipes: [recipe], cached: false, mode: 'live' });
    fixture.detectChanges();

    expect((fixture.nativeElement as HTMLElement).querySelector('.refine')).toBeNull();
  });

  describe('the one-time question card', () => {
    function render(changes: Partial<Fridge>) {
      (TestBed.inject(FridgeService) as unknown as { accept(f: Fridge): void }).accept({
        ...kitchen(null),
        ...changes,
      });
      const fixture = TestBed.createComponent(Recipes);
      fixture.detectChanges();
      const root = fixture.nativeElement as HTMLElement;
      const questions = () => [...root.querySelectorAll('.ask [id^="ask-"]')].map((p) => p.id);
      return { fixture, root, questions };
    }

    it('asks only what is still unanswered', () => {
      expect(render({ brotbox_count: null, diet: null }).questions()).toEqual([
        'ask-brotbox',
        'ask-diet',
      ]);
    });

    it('asks only how the kitchen eats when the Brotbox count is known', () => {
      expect(render({ brotbox_count: 0, diet: null }).questions()).toEqual(['ask-diet']);
    });

    it('is not there once both are answered', () => {
      expect(render({ brotbox_count: 2, diet: 'all' }).root.querySelector('.ask')).toBeNull();
    });

    it('saves each answer at once, shows the Brotbox chip, and goes once both are answered', () => {
      const { fixture, root } = render({ brotbox_count: null, diet: null });
      const answer = (group: string, index: number, changes: Partial<Fridge>) => {
        root
          .querySelectorAll<HTMLButtonElement>(`[aria-labelledby="${group}"] button`)
          [index].click();
        const req = http.expectOne(`${environment.apiUrl}/fridge`);
        expect(req.request.body).toEqual(changes);
        req.flush({ ...kitchen(null), diet: null, ...changes }); // diet still unanswered
        fixture.detectChanges();
      };

      answer('ask-brotbox', 2, { brotbox_count: 2 });
      const meals = [...root.querySelectorAll('.meals button')].map((m) => m.textContent!.trim());
      expect(meals).toContain('recipes.brotbox');
      expect(root.querySelector('.ask')).not.toBeNull();

      const flushDiet = root.querySelectorAll<HTMLButtonElement>(
        '[aria-labelledby="ask-diet"] button',
      );
      flushDiet[1].click();
      const req = http.expectOne(`${environment.apiUrl}/fridge`);
      expect(req.request.body).toEqual({ diet: 'vegetarian' });
      req.flush({ ...kitchen(2), diet: 'vegetarian' });
      fixture.detectChanges();

      expect(root.querySelector('.ask')).toBeNull();
    });

    it('stays away after "Später" until the app is reloaded, even on another visit to the tab', () => {
      const { fixture, root } = render({ brotbox_count: null, diet: null });

      (root.querySelector('.ask .later') as HTMLButtonElement).click();
      fixture.detectChanges();
      expect(root.querySelector('.ask')).toBeNull();

      const again = TestBed.createComponent(Recipes);
      again.detectChanges();
      expect((again.nativeElement as HTMLElement).querySelector('.ask')).toBeNull();
    });

    it('points to Settings for foods to leave out', () => {
      const link = render({ brotbox_count: null, diet: null }).root.querySelector('.ask a');

      expect(link?.getAttribute('href')).toBe('/settings');
    });
  });
});
