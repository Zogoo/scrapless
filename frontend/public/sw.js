/**
 * A deliberately small service worker.
 *
 * Angular ships @angular/service-worker, but it is a build-time config, a
 * generated manifest and a versioning model to understand — for an MVP whose
 * only offline requirement is "the shell opens and the shopping list is
 * readable in an aisle with no signal", about forty lines does the job and can
 * be read in one sitting.
 *
 * Two strategies, chosen per request:
 *   content-hashed bundles (main-5OKTYVF2.js) -> cache first: a new build is a new URL
 *   everything else, navigations included    -> network first, cache only when offline
 *   /api/*                                    -> network only, never cached
 *
 * "Everything else" keeps its URL across deploys: index.html, the translation
 * files, the manifest. Served cache-first, a deploy paired new code with an
 * old en.json and the tap grid showed raw keys ("capture.grid.milk"). The
 * network fetch also skips the browser's HTTP cache (`cache: 'no-cache'`),
 * which had kept those files for a year.
 *
 * And push: the server sends one notification at a time (see the handlers at
 * the bottom), and a tap opens Today.
 *
 * The API is never cached on purpose. Serving a stale "use the spinach today"
 * from last Tuesday is worse than showing nothing: the entire product promise
 * is that the thing on screen is current.
 */
// Bumped when the caching rules change: activate deletes every older cache.
const VERSION = 'restlos-v2';
const SHELL = ['/', '/index.html', '/manifest.webmanifest'];
// Same rule as StaticCacheControl on the server.
const FINGERPRINTED = /^\/(main|chunk|polyfills|styles)-[A-Za-z0-9_]{8}\.(js|css)$/;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll(SHELL.map((url) => new Request(url, { cache: 'no-cache' }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (url.pathname.startsWith('/api/')) return;

  event.respondWith(FINGERPRINTED.test(url.pathname) ? cacheFirst(request) : networkFirst(request));
});

function remember(request, response) {
  if (response.ok) {
    const copy = response.clone();
    caches.open(VERSION).then((cache) => cache.put(request, copy));
  }
  return response;
}

function cacheFirst(request) {
  return caches
    .match(request)
    .then((cached) => cached || fetch(request).then((r) => remember(request, r)));
}

// An SPA navigation offline must still resolve to the shell, or a deep link
// gets a browser error page instead of the app.
function networkFirst(request) {
  return fetch(request, { cache: 'no-cache' })
    .then((response) => remember(request, response))
    .catch(() =>
      caches
        .match(request)
        .then(
          (cached) =>
            cached || (request.mode === 'navigate' ? caches.match('/index.html') : undefined),
        )
        .then((response) => response || Response.error()),
    );
}

// The server sends { title, body, url, tag }. The tag means a newer notification
// replaces an older one, so a retried push never shows twice.
self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = {};
  }
  if (!data.title) return;

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      tag: data.tag,
      icon: '/branding/app_icon_light.png',
      data: { url: data.url },
    }),
  );
});

// One action: open Today. Only ever a page of this app, whatever the payload says.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || '/today', self.location.origin);
  const url = target.origin === self.location.origin ? target.href : '/today';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      const open = windows[0];
      if (!open) return self.clients.openWindow(url);

      return open
        .focus()
        .then((client) => client.navigate(url))
        .catch(() => self.clients.openWindow(url));
    }),
  );
});
