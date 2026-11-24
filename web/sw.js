const scope = new URL(self.registration.scope);
const prefix = `kartoved-site:${scope.pathname}:`;
const name = `${prefix}__KARTOVED_BUILD__`;
const shell = [
  'index.html', 'browser.mjs', 'flutter_bootstrap.js', 'main.dart.js',
  'runtime/favicon.png', 'sqlite3.wasm', 'sqflite_sw.js', 'assets/FontManifest.json',
  'assets/AssetManifest.bin.json', 'assets/assets/oracle/scan_names.json',
  'runtime/card_added.wav', 'runtime/card_found.wav',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(name);
    await cache.addAll(shell.map((path) => new Request(new URL(path, scope), {cache: 'reload'})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith(prefix) && key !== name) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(name);
    if (request.mode === 'navigate') {
      try {
        return await fetch(request);
      } catch {
        return await cache.match(new URL('index.html', scope)) || Response.error();
      }
    }
    const cached = await cache.match(request);
    if (cached) return cached;
    const response = await fetch(request);
    if (response.ok) await cache.put(request, response.clone()).catch(() => {});
    return response;
  })());
});
