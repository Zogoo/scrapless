import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { RecipeSuggestions } from '../models';

@Injectable({ providedIn: 'root' })
export class RecipesService {
  private readonly http = inject(HttpClient);

  /** One explicit ask. The server caches it until the kitchen changes. */
  suggest(): Observable<RecipeSuggestions> {
    return this.http.post<RecipeSuggestions>(`${environment.apiUrl}/recipes/suggest`, {});
  }
}
