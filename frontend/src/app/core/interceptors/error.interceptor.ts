import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';

/**
 * Turns a transport failure into a sentence a person can act on.
 *
 * Never an error code and never a stack: doc 4 §4.13 forbids "OCR confidence
 * below threshold" in favour of "that one was hard to read".
 */
export const errorInterceptor: HttpInterceptorFn = (req, next) =>
  next(req).pipe(
    catchError((error: HttpErrorResponse) => {
      const body = error.error as { error?: string | string[] } | null;
      const raw = body?.error;
      const message = Array.isArray(raw) ? raw.join(', ') : raw;

      return throwError(() => ({
        status: error.status,
        message: message || fallbackFor(error.status),
        retryable: error.status >= 500 || error.status === 0,
      }));
    }),
  );

function fallbackFor(status: number): string {
  if (status === 0) return "You're offline. This will keep working when you're back.";
  if (status === 413) return 'That photo was a bit big. Try again.';
  if (status >= 500) return 'Our end had a wobble. Try that again?';
  return 'That did not go through.';
}
