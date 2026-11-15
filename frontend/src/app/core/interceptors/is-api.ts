import { HttpRequest } from '@angular/common/http';

import { environment } from '../../../environments/environment';

/**
 * True for calls to our API, false for everything else — notably the
 * translation files. Interceptors that need TranslateService must skip those:
 * the translation loader fetches them while TranslateService is still being
 * built, and injecting it there is a circular dependency (NG0200) that left
 * the whole app blank.
 */
export function isApiRequest(req: HttpRequest<unknown>): boolean {
  return req.url.startsWith(environment.apiUrl);
}
