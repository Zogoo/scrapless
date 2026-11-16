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
 *   navigations and static assets -> cache first, revalidate in the background
 *   /api/*                        -> network only, never cached
 *
 * And push: the server sends one notification at a time (see the handlers at
 * the bottom), and a tap opens Today.
 *
 * The API is never cached on purpose. Serving a stale "use the spinach today"
 * from last Tuesday is worse than showing nothing: the entire product promise
 * is that the thing on screen is current.
 */
const VERSION = 'restlos-look-v1';
const SHELL = ['/', '/index.html', '/manifest.webmanifest'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll(SHELL))
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

  // An SPA navigation must resolve to the shell, or a deep link opened offline
  // gets a browser error page instead of the app.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => caches.match('/index.html').then((r) => r || Response.error())),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(VERSION).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => cached);

      return cached || network;
    }),
  );
});

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
