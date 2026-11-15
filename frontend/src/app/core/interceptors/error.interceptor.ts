import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';
import { catchError, throwError } from 'rxjs';

import { isApiRequest } from './is-api';

/**
 * Turns a transport failure into a sentence a person can act on.
 *
 * Never an error code and never a stack: doc 4 §4.13 forbids "OCR confidence
 * below threshold" in favour of "that one was hard to read".
 */
export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  if (!isApiRequest(req)) return next(req);

  const translate = inject(TranslateService);

  return next(req).pipe(
    catchError((error: HttpErrorResponse) => {
      const body = error.error as { error?: string | string[]; retryable?: boolean } | null;
      const record = body && typeof body === 'object' ? body : null;
      const raw = record?.error;
      const message = Array.isArray(raw) ? raw.join(', ') : raw;
      const retryable =
        typeof record?.retryable === 'boolean'
          ? record.retryable
          : error.status >= 500 || error.status === 0;

      return throwError(() => ({
        status: error.status,
        message: message || translate.instant(fallbackKey(error.status)),
        retryable,
      }));
    }),
  );
};

/** A sentence for when the server sent none, in the app's language. */
function fallbackKey(status: number): string {
  if (status === 0) return 'errors.offline';
  if (status === 413) return 'errors.too_big';
  if (status >= 500) return 'errors.server';
  return 'errors.generic';
}
