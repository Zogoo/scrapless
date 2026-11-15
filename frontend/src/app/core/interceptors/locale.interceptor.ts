import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';

import { LocaleService } from '../services/locale.service';

/**
 * Tells the server which language to answer in. Without it every sentence the
 * server writes — "worth using tomorrow", every error — came back in English,
 * whatever language the app was showing.
 */
export const localeInterceptor: HttpInterceptorFn = (req, next) =>
  next(req.clone({ setHeaders: { 'X-Locale': inject(LocaleService).current() } }));
