const root = new URL('.', import.meta.url);
const localCache = `kartoved-library:${root.pathname}`;
const memory = new Map();
let worker, serial = 0;
const requests = new Map();

function failWorker(error) {
  worker?.terminate();
  worker = null;
  for (const request of requests.values()) request.reject(error);
  requests.clear();
}

function scanWorker() {
  if (worker) return worker;
  worker = new Worker(new URL('scan_worker.mjs', root), {type: 'module'});
  worker.onmessage = ({data}) => {
    const request = requests.get(data.id);
    if (!request) return;
    if (data.stage) {
      request.progress?.(data.stage, data.corners);
      return;
    }
    requests.delete(data.id);
    if (data.error) request.reject(new Error(data.error));
    else request.resolve(data.value);
  };
  worker.onerror = (event) => failWorker(new Error(event.message || 'Сканер недоступен'));
  return worker;
}

async function scan(file, engine, tray, outlineOnly, progress) {
  const blob = await (await fetch(file)).blob();
  return requestScan({blob, engine, tray, outlineOnly}, progress);
}

function requestScan(message, progress) {
  return new Promise((resolve, reject) => {
    const instance = scanWorker();
    const id = ++serial;
    const timer = setTimeout(() => failWorker(new Error('Сканер не ответил')), 90000);
    requests.set(id, {
      progress,
      resolve: (data) => { clearTimeout(timer); resolve(data); },
      reject: (error) => { clearTimeout(timer); reject(error); },
    });
    instance.postMessage({id, ...message, reportProgress: Boolean(progress)});
  });
}

const canvasSize = (width, height) => Object.assign(document.createElement('canvas'), {width, height});
const bitmapFrom = async (file) => createImageBitmap(await (await fetch(file)).blob());

async function unmirror(file) {
  const bitmap = await bitmapFrom(file);
  try {
    const canvas = canvasSize(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    context.translate(canvas.width, 0);
    context.scale(-1, 1);
    context.drawImage(bitmap, 0, 0);
    return URL.createObjectURL(await jpeg(canvas));
  } finally {
    bitmap.close();
  }
}

function jpeg(canvas) {
  return new Promise((resolve, reject) => canvas.toBlob(
    (blob) => blob ? resolve(blob) : reject(new Error('Не удалось подготовить снимок')),
    'image/jpeg', .88,
  ));
}

const hasCorners = (corners) => corners.length === 8 && corners.every(Number.isFinite);

async function photoCanvas(file, limit) {
  const bitmap = await bitmapFrom(file);
  try {
    const scale = Math.min(1, limit / Math.max(bitmap.width, bitmap.height));
    const canvas = canvasSize(Math.max(1, Math.round(bitmap.width * scale)),
      Math.max(1, Math.round(bitmap.height * scale)));
    canvas.getContext('2d', {willReadFrequently: true}).drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return canvas;
  } finally {
    bitmap.close();
  }
}

async function straighten(file, corners) {
  if (!hasCorners(corners)) throw new Error('Не видно границ карты');
  const source = await photoCanvas(file, 1600);
  const image = source.getContext('2d').getImageData(0, 0, source.width, source.height).data;
  const card = canvasSize(600, 840);
  const context = card.getContext('2d');
  const output = context.createImageData(card.width, card.height);
  const [x0, y0, x1, y1, x2, y2, x3, y3] = corners;
  for (let y = 0; y < card.height; y++) {
    const v = y / (card.height - 1);
    const leftX = x0 + (x3 - x0) * v, rightX = x1 + (x2 - x1) * v;
    const leftY = y0 + (y3 - y0) * v, rightY = y1 + (y2 - y1) * v;
    for (let x = 0; x < card.width; x++) {
      const u = x / (card.width - 1);
      const sx = Math.max(0, Math.min(source.width - 1, Math.round((leftX + (rightX - leftX) * u) * source.width)));
      const sy = Math.max(0, Math.min(source.height - 1, Math.round((leftY + (rightY - leftY) * u) * source.height)));
      const from = (sy * source.width + sx) * 4;
      const to = (y * card.width + x) * 4;
      output.data[to] = image[from];
      output.data[to + 1] = image[from + 1];
      output.data[to + 2] = image[from + 2];
      output.data[to + 3] = 255;
    }
  }
  context.putImageData(output, 0, 0);
  return card;
}

async function crop(file, corners) {
  const photo = hasCorners(corners) ? await straighten(file, corners) : await photoCanvas(file, 840);
  return new Uint8Array(await (await jpeg(photo)).arrayBuffer());
}

let sampleCanvas;
async function traySample(file, bounds, side) {
  const image = await bitmapFrom(file);
  try {
    const height = side * (bounds.length / 4);
    if (sampleCanvas?.width !== side || sampleCanvas.height !== height) {
      sampleCanvas = canvasSize(side, height);
    }
    const ctx = sampleCanvas.getContext('2d', {willReadFrequently: true});
    for (let i = 0; i < bounds.length; i += 4) {
      const [l,t,r,b] = bounds.slice(i, i+4);
      ctx.drawImage(image, l * image.width, t * image.height, (r-l) * image.width,
        (b-t) * image.height, 0, side * (i / 4), side, side);
    }
    const rgba = ctx.getImageData(0, 0, side, height).data;
    const light = new Uint8Array(side * height);
    for (let i = 0; i < light.length; i++) {
      light[i] = (rgba[4*i] * 77 + rgba[4*i+1] * 150 + rgba[4*i+2] * 29) >> 8;
    }
    return light;
  } finally {
    image.close();
  }
}

let ocr, englishOcr, ocrScript;
function loadOcrScript() {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = new URL('runtime/ocr/tesseract.min.js', root);
    script.onload = resolve;
    script.onerror = () => { script.remove(); reject(new Error('Распознавание текста недоступно')); };
    document.head.append(script);
  });
}

async function loadOcr(languages) {
  await (ocrScript ??= loadOcrScript().catch(error => { ocrScript = null; throw error; }));
  return globalThis.Tesseract.createWorker(languages, 1, {
      workerPath: new URL('runtime/ocr/worker.min.js', root).href,
      corePath: new URL('runtime/ocr/core/', root).href,
      langPath: new URL('runtime/ocr/data/', root).href,
      cachePath: 'kartoved-ocr',
      workerBlobURL: false,
      logger: () => {},
  });
}

const ocrEngine = () => ocr ??= loadOcr(['eng', 'rus']).catch((error) => { ocr = null; throw error; });
const englishEngine = () => englishOcr ??= loadOcr(['eng']).then(async worker => {
  await worker.setParameters({tessedit_pageseg_mode: '7'});
  return worker;
}).catch(error => { englishOcr = null; throw error; });

async function readEnglishTitle(bytes) {
  const bitmap = await createImageBitmap(new Blob([bytes], {type: 'image/jpeg'}));
  try {
    const title = canvasSize(520, 64);
    const {width, height} = bitmap;
    title.getContext('2d').drawImage(bitmap, width * .062, height * .026, width * .74,
      height * .051, 0, 0, title.width, title.height);
    const engine = await englishEngine();
    return (await engine.recognize(title)).data.text;
  } finally {
    bitmap.close();
  }
}

async function readTextOnCard(card) {
  const engine = await ocrEngine();
  const context = card.getContext('2d');
  context.fillStyle = '#fff';
  context.fillRect(0, card.height * .15, card.width, card.height * .38);
  const result = await engine.recognize(card);
  return result.data.text;
}

async function readCardText(file, corners) {
  return readTextOnCard(await straighten(file, corners));
}

async function readTrayFooter(card) {
  const footer = canvasSize(440, 110);
  footer.getContext('2d').drawImage(card, 0, 730, 440, 110, 0, 0, 440, 110);
  const engine = await ocrEngine();
  const result = await engine.recognize(footer, {tessedit_pageseg_mode: '6'});
  return result.data.text;
}

async function trayPhoto(file, [left, top, right, bottom], readFooter) {
  const image = await bitmapFrom(file);
  const card = canvasSize(600, 840);
  try {
    card.getContext('2d').drawImage(image,
      left * image.width, top * image.height,
      (right - left) * image.width, (bottom - top) * image.height,
      0, 0, card.width, card.height);
  } finally {
    image.close();
  }
  const [photo, footer] = await Promise.all([
    jpeg(card),
    readFooter ? readTrayFooter(card).catch(() => '') : '',
  ]);
  return {bytes: new Uint8Array(await photo.arrayBuffer()), footer};
}

async function readTrayText(bytes) {
  const bitmap = await createImageBitmap(new Blob([bytes], {type: 'image/jpeg'}));
  const card = canvasSize(bitmap.width, bitmap.height);
  try {
    card.getContext('2d').drawImage(bitmap, 0, 0);
  } finally {
    bitmap.close();
  }
  return readTextOnCard(card);
}

async function warmTray(engine, essentials) {
  await Promise.all([requestScan({warm: true, engine}), essentials ? englishEngine() : ocrEngine()]);
}

async function readCache(key) {
  if (memory.has(key)) return memory.get(key);
  try {
    const cache = await caches.open(localCache);
    const response = await cache.match(new URL(`local-cache/${key}`, root));
    return response ? new Uint8Array(await response.arrayBuffer()) : null;
  } catch {
    return null;
  }
}

async function writeCache(key, bytes) {
  try {
    const cache = await caches.open(localCache);
    await cache.put(new URL(`local-cache/${key}`, root), new Response(bytes));
  } catch {
    // В приватном режиме кэш может быть недоступен.
    if (memory.size >= 64) memory.delete(memory.keys().next().value);
    memory.set(key, bytes);
  }
}

async function unpack(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

let guideVisible = true;
function guide(value) {
  try {
    const key = `${localCache}:guide`;
    if (value != null) localStorage.setItem(key, String(value));
    else return localStorage.getItem(key) !== 'false';
  } catch {
    // Настройка остаётся доступной в текущей вкладке.
  }
  if (value != null) guideVisible = value;
  return guideVisible;
}

let currentModel = 'oracle';
function scannerModel(value) {
  if (value != null) currentModel = value;
  try {
    const key = `${localCache}:model`;
    if (value == null) return localStorage.getItem(key) ?? currentModel;
    localStorage.setItem(key, value);
  } catch {
    // Настройка остаётся доступной в текущей вкладке.
  }
  return currentModel;
}

function download(name, mime, data) {
  const url = URL.createObjectURL(new Blob([data], {type: mime}));
  const link = Object.assign(document.createElement('a'), {href: url, download: name});
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

function pickBackup() {
  return new Promise((resolve, reject) => {
    const input = Object.assign(document.createElement('input'), {type: 'file', accept: '.json,application/json', hidden: true});
    input.oncancel = () => { input.remove(); resolve(null); };
    input.onchange = () => {
      const file = input.files[0];
      input.remove();
      if (!file) resolve(null);
      else if (file.size > 64 * 1024 * 1024) reject(new Error('Файл больше 64 МБ'));
      else file.text().then(resolve, reject);
    };
    document.body.append(input);
    input.click();
  });
}

let audio;
const sounds = new Map();
function loadSound(sound) {
  if (!sounds.has(sound)) {
    const buffer = fetch(new URL('runtime/card_' + sound + '.wav', root))
      .then((response) => response.arrayBuffer())
      .then((bytes) => audio.decodeAudioData(bytes))
      .catch(() => { sounds.delete(sound); return null; });
    sounds.set(sound, buffer);
  }
  return sounds.get(sound);
}

function unlockSound() {
  try {
    audio ??= new AudioContext();
    if (audio.state !== 'running') audio.resume().catch(() => {});
    for (const sound of ['added', 'found', 'review']) loadSound(sound);
  } catch {
    // Воспроизведение зависит от настроек браузера.
  }
}

async function chime(sound) {
  if (audio?.state !== 'running') return;
  const buffer = await loadSound(sound);
  if (!buffer) return;
  try {
    const source = audio.createBufferSource();
    source.buffer = buffer;
    source.connect(audio.destination);
    source.start();
  } catch {
    // Браузер мог приостановить звук после ухода вкладки в фон.
  }
}

async function reload() {
  try {
    const registration = await navigator.serviceWorker?.getRegistration(root);
    await registration?.update();
  } finally {
    location.reload();
  }
}

function scannerTray(value) {
  const key = `kartoved-scanner-tray:${root.pathname}`;
  try {
    if (value == null) return localStorage.getItem(key) !== 'false';
    localStorage.setItem(key, String(value));
  } catch (_) {
    // Настройка остаётся доступна в текущем сеансе.
  }
  return value ?? true;
}

function scannerOption(name, value) {
  const key = 'kartoved-scanner-' + name + ':' + root.pathname;
  try {
    if (value == null) return localStorage.getItem(key) === 'true';
    localStorage.setItem(key, String(value));
  } catch (_) {}
  return value ?? false;
}

async function offlineScanner(prepare) {
  const worker = (await navigator.serviceWorker?.getRegistration(root))?.active;
  if (!worker) throw new Error('Автономный режим пока недоступен');
  return new Promise((resolve, reject) => {
    const {port1, port2} = new MessageChannel();
    const timer = setTimeout(() => {
      port1.close();
      reject(new Error('Не удалось дождаться подготовки сканера'));
    }, prepare ? 300000 : 5000);
    port1.onmessage = ({data}) => {
      clearTimeout(timer);
      port1.close();
      if (data.error) reject(new Error('Не удалось сохранить файлы сканера'));
      else resolve(data.ready);
    };
    worker.postMessage({type: 'offline-scanner', engine: scannerModel(), prepare}, [port2]);
  });
}

globalThis.kartoved = {scan, crop, unmirror, readCardText, readEnglishTitle, traySample, trayPhoto, readTrayText, warmTray, guide, scannerModel, scannerTray, scannerOption, chime, unlockSound, readCache, writeCache, unpack, download, pickBackup, reload, offlineScanner};

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register(new URL('sw.js', root), {updateViaCache: 'none'})
    .catch((error) => console.warn('Автономный режим браузера недоступен', error));
}
