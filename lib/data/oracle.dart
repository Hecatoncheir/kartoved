import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:onnxruntime_core/onnxruntime_core.dart';
import 'package:path/path.dart' as p;

import 'recognition_result.dart';

export 'recognition_result.dart';

/// Распознаёт одиночную фотографию. Вызывается в рабочем изоляте.
List<Hit> identify(String directory, String photo) =>
    identifyPhoto(directory, photo).hits;

Recognition identifyPhoto(String directory, String photo) {
  final decoded = im.decodeImage(File(photo).readAsBytesSync());
  if (decoded == null) throw const FormatException('Не удалось открыть снимок');
  return identifyImage(directory, im.bakeOrientation(decoded));
}

Recognition identifyImage(String directory, im.Image original) {
  final config = jsonDecode(
    File(p.join(directory, 'catalog.json')).readAsStringSync(),
  ) as Map;
  final constants = config['constants'] as Map;
  final side = constants['scene'] as int;
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
    final rotations = constants['rotations'] as int;
    late final embed = open('embed');
    late final search = open('search');

    for (final window in _windows(side, scaled.width, scaled.height)) {
      final coarse = _detect(
        detector,
        bytes,
        side,
        width,
        window.x,
        window.y,
        window.extent,
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
      if (fine.vote / rotations < 0.5 || fine.short < side * 0.09) continue;
      final hits = _identifyCard(embed, search, config, bytes, side, fine.quad);
      if (hits.isEmpty || hits.first.score < .60) continue;
      final corners = [
        for (var i = 0; i < fine.quad.length; i++)
          _unitCoord(
            fine.quad[i],
            side,
            i.isEven ? scaled.width : scaled.height,
          ),
      ];
      return (hits: hits, corners: corners);
    }
    return (hits: <Hit>[], corners: <double>[]);
  } finally {
    for (final session in sessions.reversed) {
      session.release();
    }
  }
}

// Увеличиваем перекрывающиеся участки кадра, если общий проход пропустил карту.
Iterable<({double x, double y, double extent})> _windows(
  int side,
  int width,
  int height,
) sync* {
  final center = side / 2;
  yield (x: center, y: center, extent: side.toDouble());
  final extent = side * .64;
  final dx = math.max(0.0, (width - extent) / 2);
  final dy = math.max(0.0, (height - extent) / 2);
  for (final y in {center - dy, center + dy}) {
    for (final x in {center - dx, center + dx}) {
      yield (x: x, y: y, extent: extent);
    }
  }
}

List<Hit> _identifyCard(
  Session embed,
  Session search,
  Map config,
  Uint8List bytes,
  int side,
  Float32List quad,
) {
  final features = _run(embed, {
    'scene': _pixels(bytes, side),
    'quad': _floats(quad, [4, 2]),
  }, (outputs) => Float32List.fromList(outputs.values.first.view.float32s));
  return _run(
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
}

double _unitCoord(double coordinate, int scene, int drawn) =>
    (coordinate - ((scene - drawn) ~/ 2)) / drawn;

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
