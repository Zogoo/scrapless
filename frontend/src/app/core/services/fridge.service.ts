import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of, tap } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { environment } from '../../../environments/environment';
import { Fridge } from '../models';

const TOKEN_KEY = 'scrapless_token';
const FRIDGE_KEY = 'scrapless_fridge';

/**
 * The join code sits in the fragment so opening the link does not send it to
 * the server. The bearer token is not in the link at all.
 */
export function kitchenShareUrl(origin: string, joinCode: string): string {
  const base = origin.replace(/\/$/, '');
  return `${base}/join#${encodeURIComponent(joinCode)}`;
}

/** The code from a share link, whether Angular kept the fragment or not. */
export function joinCodeFromLocation(fragment: string | null, hash = ''): string {
  const raw = (fragment || hash.replace(/^#/, '')).trim();
  if (!raw) return '';

  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

/**
 * Identity, such as it is.
 *
 * There is no account. A fridge is a token, held in two independent places so
 * that losing one does not lose the kitchen:
 *
 *   localStorage — survives cookie clearing, readable by this code
 *   a signed 10-year cookie — survives localStorage clearing, set by the server
 *
 * On boot we try localStorage first and fall back to the cookie, which the
 * browser sends automatically. Only if both are empty is this a new fridge.
 */
@Injectable({ providedIn: 'root' })
export class FridgeService {
  private readonly http = inject(HttpClient);
  private readonly current = signal<Fridge | null>(null);

  readonly fridge = this.current.asReadonly();
  readonly isKnown = computed(() => this.current() !== null);

  get token(): string | null {
    try {
      return localStorage.getItem(TOKEN_KEY);
    } catch {
      return null; // private mode, or storage blocked
    }
  }

  /** Resolves to null when this browser has never seen a fridge. */
  restore(): Observable<Fridge | null> {
    return this.http.get<Fridge>(`${environment.apiUrl}/fridge`).pipe(
      tap((fridge) => this.accept(fridge)),
      catchError(() => {
        this.forgetLocal();
        return of(null);
      }),
    );
  }

  /** `name` empty means the user skipped the question; the server names it. */
  create(name: string): Observable<Fridge> {
    return this.http
      .post<Fridge>(`${environment.apiUrl}/fridge`, { name: name.trim() || null })
      .pipe(tap((fridge) => this.accept(fridge)));
  }

  rename(name: string): Observable<Fridge> {
    return this.http
      .patch<Fridge>(`${environment.apiUrl}/fridge`, { name })
      .pipe(tap((fridge) => this.accept(fridge)));
  }

  /**
   * Opens a kitchen someone shared. The server trades the join code for the
   * bearer token, sets the ten-year cookie, and we store the token here. A
   * phone that already had a kitchen switches to this one.
   */
  join(code: string): Observable<Fridge> {
    return this.http
      .post<Fridge>(`${environment.apiUrl}/fridge/join`, { join_code: code })
      .pipe(tap((fridge) => this.accept(fridge)));
  }

  forget(): Observable<void> {
    return this.http
      .delete<void>(`${environment.apiUrl}/fridge`)
      .pipe(tap(() => this.forgetLocal()));
  }

  private accept(fridge: Fridge): void {
    this.current.set(fridge);
    try {
      localStorage.setItem(TOKEN_KEY, fridge.token);
      localStorage.setItem(FRIDGE_KEY, JSON.stringify({ id: fridge.id, name: fridge.name }));
    } catch {
      // The cookie still identifies this fridge; storage is the belt, not the braces.
    }
  }

  private forgetLocal(): void {
    this.current.set(null);
    try {
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(FRIDGE_KEY);
    } catch {
      /* nothing to clear */
    }
  }
}
