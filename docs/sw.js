// Service worker: shows push notifications and keeps the app working offline.
const CACHE = 'anki-streak-v1';
const SHELL = ['./', 'index.html', 'manifest.json', 'icon-192.png', 'icon-180.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
  self.clients.claim();
});

// Network first, cache as fallback, so stats are always fresh when online.
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET' || !e.request.url.startsWith(self.location.origin)) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request.url.split('?')[0], copy));
        return res;
      })
      .catch(() => caches.match(e.request.url.split('?')[0]).then((r) => r || caches.match('index.html')))
  );
});

self.addEventListener('push', (e) => {
  let data = {};
  try { data = e.data.json(); } catch { data = { title: 'Anki Streak', body: e.data ? e.data.text() : 'Time to review your cards' }; }
  e.waitUntil(Promise.all([
    self.registration.showNotification(data.title || 'Anki Streak', {
      body: data.body || '',
      icon: 'icon-192.png',
      badge: 'icon-192.png',
      tag: 'streak',
      renotify: true,
      data: { url: data.url || './' },
    }),
    // Red badge on the app icon until you study.
    self.navigator && 'setAppBadge' in self.navigator ? self.navigator.setAppBadge(1).catch(() => {}) : null,
  ]));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) if ('focus' in c) return c.focus();
      return self.clients.openWindow(e.notification.data.url || './');
    })
  );
});
