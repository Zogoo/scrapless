import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
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
});
