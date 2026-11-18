import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { MemoItem, MemoPage, Suggestion } from '../models';

/** How the mic was used; logged server-side so the gestures are measured. */
export interface DictationGesture {
  gesture: 'hold' | 'tap' | 'key';
  press_ms: number;
}

export interface Dictation {
  transcript: string;
  items: MemoItem[];
}

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

  /**
   * A spoken sentence or a single held word, split into lines server-side and
   * free of charge. `lang` is the language spoken, which can differ from the
   * app's.
   */
  dictate(transcript: string, lang: string, gesture: DictationGesture): Observable<Dictation> {
    return this.http.post<Dictation>(`${this.url}/dictate`, { transcript, lang, ...gesture });
  }

  /** The paid path, for browsers without a recogniser. */
  dictateAudio(
    blob: Blob,
    seconds: number,
    lang: string,
    filename: string,
    gesture: DictationGesture,
  ): Observable<Dictation> {
    const form = new FormData();
    form.append('audio', blob, filename);
    form.append('duration_seconds', String(seconds));
    form.append('lang', lang);
    form.append('gesture', gesture.gesture);
    form.append('press_ms', String(gesture.press_ms));
    return this.http.post<Dictation>(`${this.url}/dictate`, form);
  }

  rename(id: number, name: string): Observable<MemoItem> {
    return this.http.patch<MemoItem>(`${this.url}/${id}`, { memo_item: { name } });
  }

  setDone(id: number, done: boolean): Observable<MemoItem> {
    return this.http.patch<MemoItem>(`${this.url}/${id}`, { memo_item: { done } });
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.url}/${id}`);
  }

  /** "Stop suggesting this": answers with the suggestions that are left. */
  dismiss(name: string): Observable<Suggestion[]> {
    return this.http
      .post<Suggestion[]>(`${this.url}/dismiss_suggestion`, { name })
      .pipe(tap((left) => this.suggestions.set(left)));
  }

  /** Every bought line, in one tap. */
  clearDone(): Observable<void> {
    return this.http.delete<void>(`${this.url}/clear_done`);
  }

  suggest(query: string): Observable<Suggestion[]> {
    return this.http.get<Suggestion[]>(`${this.url}/suggestions`, { params: { q: query } });
  }
}
