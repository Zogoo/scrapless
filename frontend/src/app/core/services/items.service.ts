import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { Item, Outcome, Storage, Today } from '../models';
import { NotificationsService } from './notifications.service';

@Injectable({ providedIn: 'root' })
export class ItemsService {
  private readonly http = inject(HttpClient);
  private readonly url = `${environment.apiUrl}/items`;
  private readonly notifications = inject(NotificationsService);

  /**
   * Food that is used, thrown out, emptied or brought back changes what the
   * bell counts: a notification stops counting once its food is gone. Found in
   * QA — the badge kept "1 unread" for a yogurt already used up.
   */
  private readonly recount = <T>() => tap<T>(() => this.notifications.recount());

  readonly today = signal<Today | null>(null);

  load(): Observable<Today> {
    return this.http.get<Today>(this.url).pipe(tap((today) => this.today.set(today)));
  }

  /** Every outcome is one POST with no form. */
  resolve(id: number, outcome: Outcome, days?: number): Observable<Item> {
    return this.http
      .post<Item>(`${this.url}/${id}/resolve`, { outcome, days })
      .pipe(this.recount());
  }

  /** To another place in the kitchen; the server treats the freezer as freezing it. */
  move(id: number, to: Storage): Observable<Item> {
    return this.http.post<Item>(`${this.url}/${id}/resolve`, { outcome: 'moved', to });
  }

  /** Takes back the last tap on this food, if it was just now. */
  undo(id: number): Observable<Item> {
    return this.http.post<Item>(`${this.url}/${id}/undo`, {}).pipe(this.recount());
  }

  /** One slider per Kitchen line: `level` runs 0..ids.length, oldest drained first. */
  level(ids: number[], level: number): Observable<{ items: Item[] }> {
    return this.http
      .post<{ items: Item[] }>(`${this.url}/level`, { ids, level })
      .pipe(this.recount());
  }

  correct(id: number, changes: Partial<Item>): Observable<Item> {
    return this.http.patch<Item>(`${this.url}/${id}`, { item: changes });
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.url}/${id}`).pipe(this.recount());
  }
}
