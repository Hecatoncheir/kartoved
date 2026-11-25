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
    requests.delete(data.id);
    if (data.error) request.reject(new Error(data.error));
    else request.resolve(data.value);
  };
  worker.onerror = (event) => failWorker(new Error(event.message || 'Сканер недоступен'));
  return worker;
}

async function scan(file, engine, tray) {
  const blob = await (await fetch(file)).blob();
  return requestScan({blob, engine, tray});
}

function requestScan(message) {
  return new Promise((resolve, reject) => {
    const instance = scanWorker();
    const id = ++serial;
    const timer = setTimeout(() => failWorker(new Error('Сканер не ответил')), 90000);
    requests.set(id, {
      resolve: (data) => { clearTimeout(timer); resolve(data); },
      reject: (error) => { clearTimeout(timer); reject(error); },
    });
    instance.postMessage({id, ...message});
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

async function straighten(file, corners) {
  if (corners.length !== 8 || !corners.every(Number.isFinite)) throw new Error('Не видно границ карты');
  const bitmap = await bitmapFrom(file);
  let source;
  try {
    const scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    source = canvasSize(Math.round(bitmap.width * scale), Math.round(bitmap.height * scale));
    source.getContext('2d', {willReadFrequently: true}).drawImage(bitmap, 0, 0, source.width, source.height);
  } finally {
    bitmap.close();
  }
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
  return new Uint8Array(await (await jpeg(await straighten(file, corners))).arrayBuffer());
}

let ocr;
function loadOcr() {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = new URL('runtime/ocr/tesseract.min.js', root);
    script.onload = () => resolve(globalThis.Tesseract.createWorker(['eng', 'rus'], 1, {
      workerPath: new URL('runtime/ocr/worker.min.js', root).href,
      corePath: new URL('runtime/ocr/core/', root).href,
      langPath: new URL('runtime/ocr/data/', root).href,
      cachePath: 'kartoved-ocr',
      workerBlobURL: false,
      logger: () => {},
    }));
    script.onerror = () => { script.remove(); reject(new Error('Распознавание текста недоступно')); };
    document.head.append(script);
  });
}

const ocrEngine = () => ocr ??= loadOcr().catch((error) => { ocr = null; throw error; });

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

async function warmTray() {
  await Promise.all([requestScan({warm: true}), ocrEngine()]);
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
function unlockSound() {
  try {
    audio ??= new AudioContext();
    if (audio.state !== 'running') audio.resume().catch(() => {});
  } catch {
    // Воспроизведение зависит от настроек браузера.
  }
}

async function chime(targetFound) {
  if (audio?.state !== 'running') return;
  const path = targetFound ? 'runtime/card_found.wav' : 'runtime/card_added.wav';
  try {
    if (!sounds.has(path)) {
      sounds.set(path, fetch(new URL(path, root))
        .then((response) => response.arrayBuffer())
        .then((bytes) => audio.decodeAudioData(bytes)));
    }
    const source = audio.createBufferSource();
    source.buffer = await sounds.get(path);
    source.connect(audio.destination);
    source.start();
  } catch {
    sounds.delete(path);
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

globalThis.kartoved = {scan, crop, unmirror, readCardText, trayPhoto, readTrayText, warmTray, guide, scannerModel, chime, unlockSound, readCache, writeCache, unpack, download, pickBackup, reload};

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register(new URL('sw.js', root), {updateViaCache: 'none'})
    .catch((error) => console.warn('Автономный режим браузера недоступен', error));
}
