const scope = new URL(self.registration.scope);
const prefix = `kartoved-site:${scope.pathname}:`;
const name = `${prefix}__KARTOVED_BUILD__`;
const shell = [
  'index.html', 'browser.mjs', 'flutter_bootstrap.js', 'main.dart.js',
  'kartoved.svg', 'sqlite3.wasm', 'sqflite_sw.js', 'assets/FontManifest.json',
  'assets/AssetManifest.bin.json', 'assets/assets/oracle/scan_names.json',
  'runtime/card_added.wav', 'runtime/card_found.wav', 'runtime/card_review.wav',
];

// Оболочка, шрифты и модели, необходимые для холодного запуска сканера.
function scannerFiles(engine) {
  return [
    ...shell, 'scan_worker.mjs', 'assets/AssetManifest.bin',
    ...['', 'chromium/', 'webparagraph/'].flatMap(variant =>
      ['js', 'wasm'].map(ext => `canvaskit/${variant}canvaskit.${ext}`)),
    'assets/fonts/MaterialIcons-Regular.otf', 'assets/fonts/fallback/Roboto-Regular.ttf',
    ...['Nunito', 'NunitoSans', 'JetBrainsMono'].map(font => `assets/assets/fonts/${font}.ttf`),
    ...['forest', 'dragon', 'island'].map(art => `assets/assets/design/${art}-cover.webp`),
    ...['scan_glass', 'ink_sparkle', 'stretch_effect'].map(shader => `assets/shaders/${shader}.frag`),
    'assets/packages/material_ui/shaders/ink_sparkle.frag',
    ...['catalog.json', 'cards.sqlite.pack', 'detector.onnx', 'embed.onnx', 'search.onnx']
      .map(file => `assets/assets/oracle/${file}`),
    ...['ort.wasm.min.mjs', 'ort-wasm-simd-threaded.mjs', 'ort-wasm-simd-threaded.wasm']
      .map(file => `runtime/ort/${file}`),
    'runtime/ocr/tesseract.min.js', 'runtime/ocr/worker.min.js',
    ...['lstm', 'simd-lstm'].flatMap(core => ['.wasm', '.wasm.js'].map(ext =>
      `runtime/ocr/core/tesseract-core-${core}${ext}`)),
    ...['eng', 'rus'].map(lang => `runtime/ocr/data/${lang}.traineddata.gz`),
    ...(engine === 'mtgIdentification'
      ? ['assets/assets/mtg_identification/recognize.onnx', 'assets/assets/mtg_identification/printings.json'] : []),
  ];
}

self.addEventListener('message', event => {
  if (event.data?.type !== 'offline-scanner') return;
  const {prepare, engine} = event.data;
  const port = event.ports[0];
  event.waitUntil((async () => {
    try {
      const cache = await caches.open(name);
      const saved = new Set((await cache.keys()).map(key => key.url));
      const missing = scannerFiles(engine).map(path => new URL(path, scope).href)
        .filter(url => !saved.has(url));
      if (prepare) {
        for (const url of missing) await cache.add(new Request(url, {cache: 'reload'}));
      }
      port.postMessage({ready: prepare || !missing.length});
    } catch {
      port.postMessage({error: true});
    }
  })());
});

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
