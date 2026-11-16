import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withInMemoryScrolling } from '@angular/router';
import { provideHttpClient, withInterceptors, withXhr } from '@angular/common/http';
import { provideTranslateService } from '@ngx-translate/core';
import { provideTranslateHttpLoader } from '@ngx-translate/http-loader';

import { routes } from './app.routes';
import { fridgeInterceptor } from './core/interceptors/fridge.interceptor';
import { actorInterceptor } from './core/interceptors/actor.interceptor';
import { errorInterceptor } from './core/interceptors/error.interceptor';
import { localeInterceptor } from './core/interceptors/locale.interceptor';
import { environment } from '../environments/environment';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes, withInMemoryScrolling({ scrollPositionRestoration: 'top' })),
    provideHttpClient(
      withXhr(),
      withInterceptors([fridgeInterceptor, actorInterceptor, localeInterceptor, errorInterceptor]),
    ),
    provideTranslateService({
      loader: provideTranslateHttpLoader({ prefix: '/assets/i18n/', suffix: '.json' }),
      fallbackLang: environment.defaultLocale,
      lang: environment.defaultLocale,
    }),
  ],
};
