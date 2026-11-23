import * as ort from './runtime/ort/ort.wasm.min.mjs';

ort.env.wasm.wasmPaths = new URL('./runtime/ort/', import.meta.url).href;
ort.env.wasm.numThreads = 1;

const models = new URL('./assets/assets/oracle/', import.meta.url);
const open = (name) => ort.InferenceSession.create(new URL(`${name}.onnx`, models).href, {
  executionProviders: ['wasm'],
});

let manifest, detector, embed, search;
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
  const encoder = await (embed ??= open('embed').catch((error) => { embed = null; throw error; }));
  const encoded = await encoder.run({
    scene: new ort.Tensor('uint8', new Uint8Array(scene), [side, side, 4]),
    quad: new ort.Tensor('float32', Float32Array.from(quad), [4, 2]),
  });
  const features = encoded[encoder.outputNames[0]].data;
  const inputs = {embeddings: new ort.Tensor('float32', features, [features.length / 128, 128])};
  if (config.searchMask) {
    inputs.mask = new ort.Tensor('float32', new Float32Array(config.count).fill(1), [config.count]);
  }
  const index = await (search ??= open('search').catch((error) => { search = null; throw error; }));
  const result = await index.run(inputs);
  return Array.from(result.scores.data, (score, i) => ({score, index: Number(result.indices.data[i])}))
    .filter((hit) => hit.score >= 0);
}

async function recognize(blob) {
  const config = await (manifest ??= loadManifest().catch((error) => { manifest = null; throw error; }));
  const constants = config.constants;
  const side = constants.scene;
  const input = constants.det_input;
  const bitmap = await createImageBitmap(blob);
  let scene;
  try {
    scene = sceneImage(bitmap, side);
  } finally {
    bitmap.close();
  }
  const model = await (detector ??= open('detector').catch((error) => { detector = null; throw error; }));
  for (const region of windows(side, scene.width, scene.height)) {
    const coarse = await detect(model, scene.bytes, side, input, region);
    const extent = Math.max(coarse.short * constants.card_aspect / constants.refine_fill, constants.refine_min_side);
    const fine = await detect(model, scene.bytes, side, input, [coarse.x, coarse.y, extent]);
    if (fine.vote / constants.rotations < .5 || fine.short < side * .09) continue;
    const hits = await identifyCard(scene.bytes, side, fine.quad, config);
    if (!hits.length || hits[0].score < .60) continue;
    const corners = fine.quad.map((value, i) => i % 2 === 0
      ? (value - scene.left) / scene.width : (value - scene.top) / scene.height);
    return {hits, corners};
  }
  return {hits: [], corners: []};
}

let queue = Promise.resolve();
self.onmessage = ({data: {id, blob}}) => {
  queue = queue.then(async () => {
    try {
      self.postMessage({id, value: await recognize(blob)});
    } catch (error) {
      self.postMessage({id, error: error.message || String(error)});
    }
  });
};
