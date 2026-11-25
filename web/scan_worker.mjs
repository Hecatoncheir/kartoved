import * as ort from './runtime/ort/ort.wasm.min.mjs';

ort.env.wasm.wasmPaths = new URL('./runtime/ort/', import.meta.url).href;
ort.env.wasm.numThreads = 1;

const models = new URL('./assets/assets/oracle/', import.meta.url);
const mtgModels = new URL('./assets/assets/mtg_identification/', import.meta.url);
const open = (name, directory = models) => ort.InferenceSession.create(new URL(`${name}.onnx`, directory).href, {
  executionProviders: ['wasm'],
});

let manifest, detector, embed, search, mtg;
const oracleDetector = () => detector ??= open('detector').catch((error) => { detector = null; throw error; });
const oracleEncoder = () => embed ??= open('embed').catch((error) => { embed = null; throw error; });
const oracleIndex = () => search ??= open('search').catch((error) => { search = null; throw error; });
const mtgEncoder = () => mtg ??= open('recognize', mtgModels).catch((error) => { mtg = null; throw error; });

async function warmModels(engine) {
  await Promise.all([oracleDetector(), oracleEncoder(), oracleIndex(),
    ...(engine === 'mtgIdentification' ? [mtgEncoder()] : [])]);
}
async function loadManifest() {
  const response = await fetch(new URL('catalog.json', models));
  if (!response.ok) throw new Error('Каталог распознавания недоступен');
  return response.json();
}

function sceneImage(bitmap, side, [l, t, r, b] = [0, 0, 1, 1]) {
  const sourceWidth = bitmap.width * (r - l), sourceHeight = bitmap.height * (b - t);
  const scale = side / Math.max(sourceWidth, sourceHeight);
  const width = Math.max(1, Math.round(sourceWidth * scale));
  const height = Math.max(1, Math.round(sourceHeight * scale));
  const left = Math.floor((side - width) / 2);
  const top = Math.floor((side - height) / 2);
  const canvas = new OffscreenCanvas(side, side);
  const context = canvas.getContext('2d', {alpha: false});
  context.fillStyle = '#303030';
  context.fillRect(0, 0, side, side);
  context.drawImage(bitmap, l * bitmap.width, t * bitmap.height, sourceWidth, sourceHeight,
    left, top, width, height);
  return {bytes: context.getImageData(0, 0, side, side).data, width, height, left, top};
}

function trayArtwork(bitmap, side, tray) {
  const [l, t, r, b] = tray;
  const dx = (r - l) * .09, dy = (b - t) * .09;
  const area = [Math.max(0, l - dx), Math.max(0, t - dy), Math.min(1, r + dx), Math.min(1, b + dy)];
  const scene = sceneImage(bitmap, side, area);
  const [left, top, right, bottom] = tray.map((v, i) => (v - area[i % 2]) / (area[i % 2 + 2] - area[i % 2]));
  const x0 = scene.left + left * scene.width, x1 = scene.left + right * scene.width;
  const y0 = scene.top + top * scene.height, y1 = scene.top + bottom * scene.height;
  const bytes = scene.bytes;
  let light = 0, samples = 0;
  for (let y = Math.ceil(y0); y < y1; y += 13) {
    for (let x = Math.ceil(x0); x < x1; x += 13) {
      const i = (y * side + x) * 4;
      light += .21 * bytes[i] + .72 * bytes[i + 1] + .07 * bytes[i + 2];
      samples++;
    }
  }
  if (samples > 0 && light / samples < 90) {
    for (let i = 0; i < bytes.length; i += 4) {
      bytes[i] = bytes[i] * 1.5625 - 32;
      bytes[i + 1] = bytes[i + 1] * 1.5625 - 32;
      bytes[i + 2] = bytes[i + 2] * 1.5625 - 32;
    }
  }
  return {bytes, quad: [x0, y0, x1, y0, x1, y1, x0, y1]};
}

async function readScene(blob, side) {
  const bitmap = await createImageBitmap(blob);
  try {
    return sceneImage(bitmap, side);
  } finally {
    bitmap.close();
  }
}

function* windows(side, width, height) {
  const center = side / 2;
  yield [center, center, side];
  const extent = side * .64;
  const dx = Math.max(0, (width - extent) / 2);
  const dy = Math.max(0, (height - extent) / 2);
  for (const y of new Set([center - dy, center + dy])) {
    for (const x of new Set([center - dx, center + dx])) yield [x, y, extent];
  }
}

function sampleWindow(scene, side, input, cx, cy, step) {
  const result = new Uint8Array(input * input * 4);
  const edge = side - 1;
  const sample = (offset, center) => Math.max(0, Math.min(edge, (offset - input / 2) * step + center));
  for (let y = 0; y < input; y++) {
    const sy = sample(y, cy);
    const y0 = Math.floor(sy), y1 = Math.min(y0 + 1, edge);
    const fy = sy - y0;
    for (let x = 0; x < input; x++) {
      const sx = sample(x, cx);
      const x0 = Math.floor(sx), x1 = Math.min(x0 + 1, edge);
      const fx = sx - x0;
      const pixel = (y * input + x) * 4;
      for (let c = 0; c < 3; c++) {
        const top = scene[(y0 * side + x0) * 4 + c] * (1 - fx) + scene[(y0 * side + x1) * 4 + c] * fx;
        const bottom = scene[(y1 * side + x0) * 4 + c] * (1 - fx) + scene[(y1 * side + x1) * 4 + c] * fx;
        result[pixel + c] = Math.round(top * (1 - fy) + bottom * fy);
      }
      result[pixel + 3] = 255;
    }
  }
  return result;
}

async function detect(session, scene, side, input, [cx, cy, extent]) {
  const step = extent / input;
  const window = sampleWindow(scene, side, input, cx, cy, step);
  const result = await session.run({window: new ort.Tensor('uint8', window, [input, input, 4])});
  const [raw, up, center, size] = session.outputNames.map((name) => result[name].data);
  const convert = (value, origin) => (value - input / 2) * step + origin;
  return {
    quad: Array.from(raw, (value, i) => convert(value, i % 2 === 0 ? cx : cy)),
    x: convert(center[0], cx),
    y: convert(center[1], cy),
    short: size[0] * step,
    vote: Math.hypot(up[0], up[1]),
  };
}

async function identifyCard(scene, side, quad, config) {
  const encoder = await oracleEncoder();
  const encoded = await encoder.run({
    scene: new ort.Tensor('uint8', new Uint8Array(scene), [side, side, 4]),
    quad: new ort.Tensor('float32', Float32Array.from(quad), [4, 2]),
  });
  const features = encoded[encoder.outputNames[0]].data;
  const inputs = {embeddings: new ort.Tensor('float32', features, [features.length / 128, 128])};
  if (config.searchMask) {
    inputs.mask = new ort.Tensor('float32', new Float32Array(config.count).fill(1), [config.count]);
  }
  const index = await oracleIndex();
  return hitsFrom(await index.run(inputs));
}

async function identifyMtgCard(scene, side, quad) {
  const session = await mtgEncoder();
  return hitsFrom(await session.run({
    scene: new ort.Tensor('uint8', new Uint8Array(scene), [side, side, 4]),
    quad: new ort.Tensor('float32', Float32Array.from(quad), [4, 2]),
  }));
}

function hitsFrom(result) {
  return Array.from(result.scores.data, (score, i) => ({score, index: Number(result.indices.data[i])}))
    .filter((hit) => hit.score >= 0);
}

function relativeCorners(quad, scene) {
  return Array.from(quad, (value, i) => i % 2 === 0
    ? (value - scene.left) / scene.width : (value - scene.top) / scene.height);
}

const empty = {hits: [], mtgHits: [], corners: []};

function isInTray(scene, [left, top, right, bottom], found) {
  const l = scene.left + left * scene.width, r = scene.left + right * scene.width;
  const t = scene.top + top * scene.height, b = scene.top + bottom * scene.height;
  const size = Math.min(r - l, b - t);
  const near = Math.abs(found.x - (l + r) / 2) <= size * .11 &&
    Math.abs(found.y - (t + b) / 2) <= size * .11;
  return near && found.short >= size * .75 && found.short <= size * 1.25;
}

async function recognizeTray(bitmap, config, model, tray, engine, progress) {
  const {scene: side, det_input: input, rotations} = config.constants;
  const scene = sceneImage(bitmap, side);
  const found = await detect(model, scene.bytes, side, input, [side / 2, side / 2, side]);
  if (found.vote / rotations < .5) return empty;
  const corners = relativeCorners(found.quad, scene);
  const upright = found.quad[0] < found.x && found.quad[1] < found.y &&
    found.quad[2] > found.x && found.quad[3] < found.y;
  if (!upright || !isInTray(scene, tray, found)) {
    return found.short >= side * .09 ? {...empty, corners} : empty;
  }

  progress?.('card', corners);
  const [l, t, r, b] = tray;
  progress?.('artwork', [l, t, r, t, r, b, l, b]);
  const artwork = trayArtwork(bitmap, side, tray);
  const hits = await identifyCard(artwork.bytes, side, artwork.quad, config);
  if (!(hits[0]?.score >= .60)) return {...empty, corners};
  const mtgHits = engine === 'mtgIdentification'
    ? await identifyMtgCard(artwork.bytes, side, artwork.quad)
    : [];
  return {hits, mtgHits, corners};
}

async function recognize(blob, engine, tray, outlineOnly, progress) {
  const config = await (manifest ??= loadManifest().catch((error) => { manifest = null; throw error; }));
  const constants = config.constants;
  const side = constants.scene;
  const input = constants.det_input;
  const model = await oracleDetector();
  if (tray) {
    const bitmap = await createImageBitmap(blob);
    try {
      return await recognizeTray(bitmap, config, model, tray, engine, progress);
    } finally {
      bitmap.close();
    }
  }
  const scene = await readScene(blob, side);
  let outline = null;
  for (const region of windows(side, scene.width, scene.height)) {
    const coarse = await detect(model, scene.bytes, side, input, region);
    const extent = Math.max(coarse.short * constants.card_aspect / constants.refine_fill, constants.refine_min_side);
    const fine = await detect(model, scene.bytes, side, input, [coarse.x, coarse.y, extent]);
    if (fine.vote / constants.rotations < .5 || fine.short < side * .09) continue;
    const corners = relativeCorners(fine.quad, scene);
    if (outlineOnly) return {...empty, corners};
    outline ??= corners;
    progress?.('card', corners);
    progress?.('artwork', corners);
    const hits = await identifyCard(scene.bytes, side, fine.quad, config);
    if (!hits.length || hits[0].score < .60) continue;
    const mtgHits = engine === 'mtgIdentification'
      ? await identifyMtgCard(scene.bytes, side, fine.quad)
      : [];
    return {hits, mtgHits, corners};
  }
  return outline ? {...empty, corners: outline} : empty;
}

let queue = Promise.resolve();
self.onmessage = ({data: {id, blob, engine, tray, warm, outlineOnly, reportProgress}}) => {
  queue = queue.then(async () => {
    try {
      const progress = reportProgress
        ? (stage, corners) => self.postMessage({id, stage, corners})
        : undefined;
      self.postMessage({id, value: warm ? await warmModels(engine) : await recognize(blob, engine, tray, outlineOnly, progress)});
    } catch (error) {
      self.postMessage({id, error: error.message || String(error)});
    }
  });
};
