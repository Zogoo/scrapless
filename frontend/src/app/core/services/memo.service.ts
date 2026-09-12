import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { MemoItem, MemoPage, Suggestion } from '../models';

@Injectable({ providedIn: 'root' })
export class MemoService {
  private readonly http = inject(HttpClient);
  private readonly url = `${environment.apiUrl}/memo`;

  readonly items = signal<MemoItem[]>([]);
  readonly suggestions = signal<Suggestion[]>([]);

  load(): Observable<MemoPage> {
    return this.http.get<MemoPage>(this.url).pipe(
      tap((page) => {
        this.items.set(page.items);
        this.suggestions.set(page.suggestions);
      }),
    );
  }

  add(name: string, source: 'text' | 'suggestion' = 'text'): Observable<MemoItem> {
    return this.http.post<MemoItem>(this.url, { name, source });
  }

  /** A whole spoken sentence, split into lines server-side and free of charge. */
  dictate(transcript: string): Observable<{ transcript: string; items: MemoItem[] }> {
    return this.http.post<{ transcript: string; items: MemoItem[] }>(`${this.url}/dictate`, {
      transcript,
    });
  }

  dictateAudio(blob: Blob, seconds: number): Observable<{ transcript: string; items: MemoItem[] }> {
    const form = new FormData();
    form.append('audio', blob, 'memo.webm');
    form.append('duration_seconds', String(seconds));
    return this.http.post<{ transcript: string; items: MemoItem[] }>(`${this.url}/dictate`, form);
  }

  setDone(id: number, done: boolean): Observable<MemoItem> {
    return this.http.patch<MemoItem>(`${this.url}/${id}`, { memo_item: { done } });
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.url}/${id}`);
  }

  suggest(query: string): Observable<Suggestion[]> {
    return this.http.get<Suggestion[]>(`${this.url}/suggestions`, { params: { q: query } });
  }
}
