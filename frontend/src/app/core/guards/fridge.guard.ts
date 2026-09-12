import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs/operators';
import { of } from 'rxjs';

import { FridgeService } from '../services/fridge.service';

/**
 * Sends a browser with no fridge to the one onboarding question, and everyone
 * else straight to Today. The server is the authority: a token in localStorage
 * that the server does not recognise is not a fridge.
 */
export const fridgeGuard: CanActivateFn = () => {
  const fridge = inject(FridgeService);
  const router = inject(Router);

  if (fridge.isKnown()) return of(true);

  return fridge.restore().pipe(map((found) => (found ? true : router.createUrlTree(['/welcome']))));
};

/** The mirror image: keeps a known fridge out of the onboarding screen. */
export const noFridgeGuard: CanActivateFn = () => {
  const fridge = inject(FridgeService);
  const router = inject(Router);

  if (fridge.isKnown()) return of(router.createUrlTree(['/today']));

  return fridge.restore().pipe(map((found) => (found ? router.createUrlTree(['/today']) : true)));
};
