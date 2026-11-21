import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { Meal, RecipeSuggestions } from '../models';

@Injectable({ providedIn: 'root' })
export class RecipesService {
  private readonly http = inject(HttpClient);

  /** One explicit ask for one meal. The server stores it for the rest of the day. */
  suggest(meal: Meal): Observable<RecipeSuggestions> {
    return this.http.post<RecipeSuggestions>(`${environment.apiUrl}/recipes/suggest`, { meal });
  }
}
