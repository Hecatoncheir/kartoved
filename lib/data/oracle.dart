import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:onnxruntime_core/onnxruntime_core.dart';
import 'package:path/path.dart' as p;

typedef Hit = ({int index, double score});

/// Распознаёт одиночную фотографию. Вызывается в рабочем изоляте.
List<Hit> identify(String directory, String photo) {
  final config = jsonDecode(
    File(p.join(directory, 'catalog.json')).readAsStringSync(),
  ) as Map;
  final constants = config['constants'] as Map;
  final side = constants['scene'] as int;
  final decoded = im.decodeImage(File(photo).readAsBytesSync());
  if (decoded == null) throw const FormatException('Не удалось открыть снимок');
  final original = im.bakeOrientation(decoded);
  final large = math.max(original.width, original.height);
  final scale = side / large;
  final scaled = im.copyResize(
    original,
    width: math.max(1, (original.width * scale).round()),
    height: math.max(1, (original.height * scale).round()),
    interpolation: im.Interpolation.linear,
  );
  final scene = im.Image(width: side, height: side, numChannels: 4);
  im.fill(scene, color: im.ColorRgba8(48, 48, 48, 255));
  im.compositeImage(
    scene,
    scaled,
    dstX: (side - scaled.width) ~/ 2,
    dstY: (side - scaled.height) ~/ 2,
  );
  final bytes = scene.getBytes(order: im.ChannelOrder.rgba);
  final sessions = <Session>[];
  Session open(String name) {
    final session = Session.fromBytes(
      File(p.join(directory, '$name.onnx')).readAsBytesSync(),
      options: const SessionOptions(intraOpNumThreads: 2),
    );
    sessions.add(session);
    return session;
  }

  try {
    final detector = open('detector');
    final width = constants['det_input'] as int;
    final coarse = _detect(
      detector,
      bytes,
      side,
      width,
      side / 2,
      side / 2,
      side.toDouble(),
    );
    final refine = math.max(
      coarse.short *
          (constants['card_aspect'] as num) /
          (constants['refine_fill'] as num),
      (constants['refine_min_side'] as num).toDouble(),
    );
    final fine = _detect(
      detector,
      bytes,
      side,
      width,
      coarse.x,
      coarse.y,
      refine,
    );
    if (fine.vote / (constants['rotations'] as int) < 0.5 ||
        fine.short < side * 0.09) {
      return [];
    }
    final embed = open('embed');
    final features = _run(embed, {
      'scene': _pixels(bytes, side),
      'quad': _floats(fine.quad, [4, 2]),
    }, (outputs) => Float32List.fromList(outputs.values.first.view.float32s));
    final search = open('search');
    final hits = _run(
      search,
      {
        'embeddings': _floats(features, [features.length ~/ 128, 128]),
        if (config['searchMask'] == true)
          'mask': _floats(
            Float32List(config['count'] as int)
              ..fillRange(0, config['count'] as int, 1),
            [config['count'] as int],
          ),
      },
      (outputs) {
        final ids = outputs['indices']!.view.int64s;
        final scores = outputs['scores']!.view.float32s;
        return [
          for (var i = 0; i < ids.length; i++)
            if (scores[i] >= 0.0) (index: ids[i], score: scores[i]),
        ];
      },
    );
    return hits.isEmpty || hits.first.score < 0.60 ? [] : hits;
  } finally {
    for (final session in sessions.reversed) {
      session.release();
    }
  }
}

OrtTensor _pixels(Uint8List data, int side) =>
    OrtTensor.fromData(OrtElementType.uint8, data, [side, side, 4]);
OrtTensor _floats(Float32List data, List<int> shape) =>
    OrtTensor.fromData(OrtElementType.float32, data, shape);

T _run<T>(
  Session session,
  Map<String, OrtTensor> inputs,
  T Function(Map<String, OrtTensor>) read,
) {
  Map<String, OrtTensor> outputs = {};
  try {
    outputs = session.run(inputs);
    return read(outputs);
  } finally {
    for (final tensor in [...outputs.values, ...inputs.values]) {
      tensor.release();
    }
  }
}

typedef _Detection = ({
  double x,
  double y,
  double short,
  double vote,
  Float32List quad,
});
_Detection _detect(
  Session model,
  Uint8List scene,
  int side,
  int width,
  double cx,
  double cy,
  double extent,
) {
  final data = Uint8List(width * width * 4);
  final step = extent / width;
  for (var y = 0; y < width; y++) {
    final sy = ((y - width / 2) * step + cy).clamp(0.0, side - 1.0);
    final y0 = sy.floor(), y1 = math.min(y0 + 1, side - 1);
    final fy = sy - y0;
    for (var x = 0; x < width; x++) {
      final sx = ((x - width / 2) * step + cx).clamp(0.0, side - 1.0);
      final x0 = sx.floor(), x1 = math.min(x0 + 1, side - 1);
      final fx = sx - x0;
      final pos = (y * width + x) * 4;
      for (var c = 0; c < 3; c++) {
        final a =
            scene[(y0 * side + x0) * 4 + c] * (1 - fx) +
            scene[(y0 * side + x1) * 4 + c] * fx;
        final b =
            scene[(y1 * side + x0) * 4 + c] * (1 - fx) +
            scene[(y1 * side + x1) * 4 + c] * fx;
        data[pos + c] = (a * (1 - fy) + b * fy).round();
      }
      data[pos + 3] = 255;
    }
  }
  return _run(model, {'window': _pixels(data, width)}, (out) {
    final values = out.values.toList();
    final raw = values[0].view.float32s,
        up = values[1].view.float32s,
        centre = values[2].view.float32s;
    final quad = Float32List.fromList([
      for (var i = 0; i < raw.length; i++)
        (raw[i] - width / 2) * step + (i.isEven ? cx : cy),
    ]);
    return (
      quad: quad,
      x: (centre[0] - width / 2) * step + cx,
      y: (centre[1] - width / 2) * step + cy,
      short: values[3].view.float32s.first * step,
      vote: math.sqrt(up[0] * up[0] + up[1] * up[1]),
    );
  });
}
