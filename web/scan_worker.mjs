import * as ort from './runtime/ort/ort.wasm.min.mjs';

ort.env.wasm.wasmPaths = new URL('./runtime/ort/', import.meta.url).href;
ort.env.wasm.numThreads = 1;

const models = new URL('./assets/assets/oracle/', import.meta.url);
const mtgModels = new URL('./assets/assets/mtg_identification/', import.meta.url);
const open = (name, directory = models) => ort.InferenceSession.create(new URL(`${name}.onnx`, directory).href, {
  executionProviders: ['wasm'],
});

let manifest, detector, embed, search, mtg, pose;
const oracleDetector = () => detector ??= open('detector').catch((error) => { detector = null; throw error; });
const oracleEncoder = () => embed ??= open('embed').catch((error) => { embed = null; throw error; });
const oracleIndex = () => search ??= open('search').catch((error) => { search = null; throw error; });

async function warmOracle() {
  await Promise.all([oracleDetector(), oracleEncoder(), oracleIndex()]);
}
async function loadManifest() {
  const response = await fetch(new URL('catalog.json', models));
  if (!response.ok) throw new Error('Каталог распознавания недоступен');
  return response.json();
}

function sceneImage(bitmap, side) {
  const scale = side / Math.max(bitmap.width, bitmap.height);
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));
  const left = Math.floor((side - width) / 2);
  const top = Math.floor((side - height) / 2);
  const canvas = new OffscreenCanvas(side, side);
  const context = canvas.getContext('2d', {alpha: false});
  context.fillStyle = '#303030';
  context.fillRect(0, 0, side, side);
  context.drawImage(bitmap, left, top, width, height);
  return {bytes: context.getImageData(0, 0, side, side).data, width, height, left, top};
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
  const session = await (mtg ??= open('recognize', mtgModels).catch((error) => { mtg = null; throw error; }));
  return hitsFrom(await session.run({
    scene: new ort.Tensor('uint8', new Uint8Array(scene), [side, side, 4]),
    quad: new ort.Tensor('float32', Float32Array.from(quad), [4, 2]),
  }));
}

function hitsFrom(result) {
  return Array.from(result.scores.data, (score, i) => ({score, index: Number(result.indices.data[i])}))
    .filter((hit) => hit.score >= 0);
}

async function mtgRotations(scene, side, quad) {
  const scores = new Map();
  let bestScore = -1;
  let bestQuad = quad;
  for (let offset = 0; offset < quad.length; offset += 2) {
    const rotated = [...quad.slice(offset), ...quad.slice(0, offset)];
    const hits = await identifyMtgCard(scene, side, rotated);
    if ((hits[0]?.score ?? -1) > bestScore) {
      bestScore = hits[0].score;
      bestQuad = rotated;
    }
    for (const {index, score} of hits) {
      scores.set(index, Math.max(score, scores.get(index) ?? 0));
    }
  }
  const mtgHits = Array.from(scores, ([index, score]) => ({index, score})).sort((a, b) => b.score - a.score);
  return {mtgHits, quad: bestQuad};
}

function relativeCorners(quad, scene) {
  return Array.from(quad, (value, i) => i % 2 === 0
    ? (value - scene.left) / scene.width : (value - scene.top) / scene.height);
}

async function recognizeStandaloneMtg(blob) {
  const side = 640;
  const scene = await readScene(blob, side);
  const session = await (pose ??= open('pose', mtgModels).catch((error) => { pose = null; throw error; }));
  const {score, quad} = await session.run({
    scene: new ort.Tensor('uint8', new Uint8Array(scene.bytes), [side, side, 4]),
  });
  if (score.data[0] < .50) return {hits: [], mtgHits: [], corners: []};
  const rotated = await mtgRotations(scene.bytes, side, quad.data);
  return {hits: [], mtgHits: rotated.mtgHits, corners: relativeCorners(rotated.quad, scene)};
}

const empty = {hits: [], mtgHits: [], corners: []};

async function recognizeTray(scene, config, model, [left, top, right, bottom]) {
  const {scene: side, det_input: input, rotations} = config.constants;
  const l = scene.left + left * scene.width, r = scene.left + right * scene.width;
  const t = scene.top + top * scene.height, b = scene.top + bottom * scene.height;
  const size = Math.min(r - l, b - t);
  const found = await detect(model, scene.bytes, side, input, [side / 2, side / 2, side]);
  const near = Math.abs(found.x - (l + r) / 2) <= size * .11 &&
    Math.abs(found.y - (t + b) / 2) <= size * .11;
  const upright = found.quad[0] < found.x && found.quad[1] < found.y &&
    found.quad[2] > found.x && found.quad[3] < found.y;
  if (found.vote / rotations < .5 || !near || !upright ||
    found.short < size * .75 || found.short > size * 1.25) return empty;

  const hits = await identifyCard(scene.bytes, side, [l, t, r, t, r, b, l, b], config);
  if (!hits.length || hits[0].score < .60) return empty;
  return {hits, mtgHits: [], corners: [left, top, right, top, right, bottom, left, bottom]};
}

async function recognize(blob, engine, tray) {
  if (engine === 'mtgStandalone') return recognizeStandaloneMtg(blob);
  const config = await (manifest ??= loadManifest().catch((error) => { manifest = null; throw error; }));
  const constants = config.constants;
  const side = constants.scene;
  const input = constants.det_input;
  const scene = await readScene(blob, side);
  const model = await oracleDetector();
  if (tray) return recognizeTray(scene, config, model, tray);
  for (const region of windows(side, scene.width, scene.height)) {
    const coarse = await detect(model, scene.bytes, side, input, region);
    const extent = Math.max(coarse.short * constants.card_aspect / constants.refine_fill, constants.refine_min_side);
    const fine = await detect(model, scene.bytes, side, input, [coarse.x, coarse.y, extent]);
    if (fine.vote / constants.rotations < .5 || fine.short < side * .09) continue;
    const hits = await identifyCard(scene.bytes, side, fine.quad, config);
    if (!hits.length || hits[0].score < .60) continue;
    const mtgHits = engine === 'mtgIdentification'
      ? await identifyMtgCard(scene.bytes, side, fine.quad)
      : [];
    const corners = relativeCorners(fine.quad, scene);
    return {hits, mtgHits, corners};
  }
  return empty;
}

let queue = Promise.resolve();
self.onmessage = ({data: {id, blob, engine, tray, warm}}) => {
  queue = queue.then(async () => {
    try {
      self.postMessage({id, value: warm ? await warmOracle() : await recognize(blob, engine, tray)});
    } catch (error) {
      self.postMessage({id, error: error.message || String(error)});
    }
  });
};
