// Keeps the app shell available offline. Bump VERSION whenever a file in SHELL changes,
// otherwise phones keep the old shell. Only successful responses are cached.
const VERSION = 'homelab-v1'
const SHELL = ['/', '/app.js', '/style.css', '/icon.svg', '/manifest.webmanifest']

self.addEventListener('install', (e) => e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())))
self.addEventListener('activate', (e) => e.waitUntil(
  caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim())))

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url)
  if (e.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return
  // network first, shell from cache when offline
  e.respondWith(fetch(e.request).then((r) => {
    if (r.ok) { const copy = r.clone(); caches.open(VERSION).then((c) => c.put(e.request, copy)) }
    return r
  }).catch(() => caches.match(e.request).then((r) => r || caches.match('/'))))
})
