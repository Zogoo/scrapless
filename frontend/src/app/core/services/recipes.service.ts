import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { Meal, RecipeSuggestions, Refinement } from '../models';

@Injectable({ providedIn: 'root' })
export class RecipesService {
  private readonly http = inject(HttpClient);

  /**
   * One explicit ask for one meal. The server stores it for the rest of the
   * day; a refinement asks once more and replaces what was stored.
   */
  suggest(meal: Meal, refine?: Refinement): Observable<RecipeSuggestions> {
    const body = refine ? { meal, refine } : { meal };
    return this.http.post<RecipeSuggestions>(`${environment.apiUrl}/recipes/suggest`, body);
  }
}
