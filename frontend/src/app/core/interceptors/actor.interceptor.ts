import { HttpInterceptorFn, HttpRequest } from '@angular/common/http';
import { inject } from '@angular/core';

import { ActorService } from '../services/actor.service';

/**
 * Sends the name on this phone with the requests that add something: a capture,
 * a memo line, a spoken list. Other requests do not need it, and a blank name
 * sends nothing.
 */
export const actorInterceptor: HttpInterceptorFn = (req, next) => {
  const name = inject(ActorService).name();
  if (!name || !attributesThis(req)) return next(req);

  return next(req.clone({ setHeaders: { 'X-Actor-Name': encodeURIComponent(name) } }));
};

function attributesThis(req: HttpRequest<unknown>): boolean {
  if (req.method !== 'POST') return false;

  const path = new URL(req.url, 'http://localhost').pathname;
  return path.endsWith('/captures') || path.endsWith('/memo') || path.endsWith('/memo/dictate');
}
