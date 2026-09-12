import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { Item, Outcome, Today } from '../models';

@Injectable({ providedIn: 'root' })
export class ItemsService {
  private readonly http = inject(HttpClient);
  private readonly url = `${environment.apiUrl}/items`;

  readonly today = signal<Today | null>(null);

  load(): Observable<Today> {
    return this.http.get<Today>(this.url).pipe(tap((today) => this.today.set(today)));
  }

  /** Every outcome is one POST with no form. */
  resolve(id: number, outcome: Outcome, days?: number): Observable<Item> {
    return this.http.post<Item>(`${this.url}/${id}/resolve`, { outcome, days });
  }

  correct(id: number, changes: Partial<Item>): Observable<Item> {
    return this.http.patch<Item>(`${this.url}/${id}`, { item: changes });
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.url}/${id}`);
  }
}
