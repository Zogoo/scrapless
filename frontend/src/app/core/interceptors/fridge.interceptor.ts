import { inject } from '@angular/core';
import { HttpInterceptorFn } from '@angular/common/http';

import { FridgeService } from '../services/fridge.service';

/**
 * Sends both halves of the identity on every API call: the bearer token from
 * localStorage when we have one, and `withCredentials` so the ten-year cookie
 * goes too. Either alone is enough for the server to find the fridge.
 */
export const fridgeInterceptor: HttpInterceptorFn = (req, next) => {
  const token = inject(FridgeService).token;
  const withCredentials = req.clone({ withCredentials: true });

  if (!token) {
    return next(withCredentials);
  }

  return next(withCredentials.clone({ setHeaders: { Authorization: `Bearer ${token}` } }));
};
