import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of, tap, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { environment } from '../../../environments/environment';
import { Fridge } from '../models';

const TOKEN_KEY = 'scrapless_token';
const FRIDGE_KEY = 'scrapless_fridge';
/** The kitchen this phone was on before it joined another, so it can go back. */
const PREVIOUS_KEY = 'scrapless_previous';

export interface PreviousKitchen {
  token: string;
  name: string;
}

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

  /**
   * Resolves to null only when the server says it does not know this fridge.
   *
   * Any other failure — offline, a 5xx, a machine still waking — rethrows and
   * keeps the token. Forgetting it there sent a returning phone to the welcome
   * screen, where Skip made a new kitchen over the real one.
   */
  restore(): Observable<Fridge | null> {
    return this.http.get<Fridge>(`${environment.apiUrl}/fridge`).pipe(
      tap((fridge) => this.accept(fridge)),
      catchError((error: { status?: number }) => {
        if (error?.status !== 401) return throwError(() => error);

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

  /** Remembered on the kitchen too, for anything the server writes later. */
  setLocale(locale: string): Observable<Fridge> {
    return this.http
      .patch<Fridge>(`${environment.apiUrl}/fridge`, { locale })
      .pipe(tap((fridge) => this.accept(fridge)));
  }

  /** The kitchen's weekly notification budget, shared by every phone in it. */
  setAlertsPerWeek(count: number): Observable<Fridge> {
    return this.http
      .patch<Fridge>(`${environment.apiUrl}/fridge`, { alerts_per_week: count })
      .pipe(tap((fridge) => this.accept(fridge)));
  }

  /**
   * Opens a kitchen someone shared. The server trades the join code for the
   * bearer token, sets the ten-year cookie, and we store the token here. A
   * phone that already had a kitchen switches to this one.
   */
  join(code: string): Observable<Fridge> {
    const leaving = this.current();
    return this.http.post<Fridge>(`${environment.apiUrl}/fridge/join`, { join_code: code }).pipe(
      tap((fridge) => {
        // Switching used to strand the old kitchen unless its link was saved.
        if (leaving && leaving.id !== fridge.id) this.remember(leaving);
        this.accept(fridge);
      }),
    );
  }

  /** The kitchen behind a share code, by name, without opening it. */
  preview(code: string): Observable<{ name: string }> {
    return this.http.post<{ name: string }>(`${environment.apiUrl}/fridge/preview`, {
      join_code: code,
    });
  }

  previous(): PreviousKitchen | null {
    try {
      return JSON.parse(localStorage.getItem(PREVIOUS_KEY) ?? 'null') as PreviousKitchen | null;
    } catch {
      return null;
    }
  }

  /**
   * Goes back to the kitchen this phone left, and remembers the one it is
   * leaving, so the two can be swapped back and forth. The server re-stamps
   * the cookie from the bearer token on the very next request.
   *
   * Resolves to null, staying put, when the other kitchen no longer exists —
   * someone forgot it from another phone. It is then no longer offered. (This
   * used to fall back to the cookie, land on the same kitchen, and offer
   * "Back to" the kitchen already open.) Offline, nothing changes and it throws.
   */
  switchBack(): Observable<Fridge | null> {
    const back = this.previous();
    const leaving = this.current();
    if (!back) return of(null);

    try {
      if (leaving) this.remember(leaving);
      else localStorage.removeItem(PREVIOUS_KEY);
      localStorage.setItem(TOKEN_KEY, back.token);
    } catch {
      return of(null);
    }
    this.current.set(null);
    return this.restore().pipe(
      tap((fridge) => {
        if (fridge || !leaving) return;
        this.accept(leaving);
        this.dropPrevious();
      }),
      catchError((error: unknown) => {
        if (leaving) {
          this.accept(leaving);
          this.remember(back);
        }
        return throwError(() => error);
      }),
    );
  }

  private dropPrevious(): void {
    try {
      localStorage.removeItem(PREVIOUS_KEY);
    } catch {
      /* nothing kept */
    }
  }

  private remember(fridge: PreviousKitchen): void {
    try {
      localStorage.setItem(
        PREVIOUS_KEY,
        JSON.stringify({ token: fridge.token, name: fridge.name }),
      );
    } catch {
      /* nowhere to keep it; the old kitchen's own link still works */
    }
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
