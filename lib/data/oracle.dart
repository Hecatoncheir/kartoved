import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:onnxruntime_core/onnxruntime_core.dart';
import 'package:path/path.dart' as p;

import 'paddle_title.dart';
import 'recognition_result.dart';
import 'scan_progress.dart';
import 'tray.dart';

export 'recognition_result.dart';

/// Распознаёт одиночную фотографию. Вызывается в рабочем изоляте.
List<Hit> identify(String directory, String photo) =>
    identifyPhoto(directory, photo).hits;

Recognition identifyPhoto(
  String directory,
  String photo, {
  Uint8List? mtgGraph,
  TrayArea? tray,
  bool outlineOnly = false,
  PaddleTitleAssets? titleAssets,
  ScanProgress? onProgress,
}) {
  final decoded = im.decodeImage(File(photo).readAsBytesSync());
  if (decoded == null) throw const FormatException('Не удалось открыть снимок');
  return identifyImage(
    directory,
    im.bakeOrientation(decoded),
    mtgGraph: mtgGraph,
    tray: tray,
    outlineOnly: outlineOnly,
    titleAssets: titleAssets,
    onProgress: onProgress,
  );
}

Recognition identifyImage(
  String directory,
  im.Image original, {
  Uint8List? mtgGraph,
  TrayArea? tray,
  bool outlineOnly = false,
  PaddleTitleAssets? titleAssets,
  ScanProgress? onProgress,
  OracleRecognizer? recognizer,
}) {
  final active = recognizer ?? OracleRecognizer(directory);
  try {
    return active.identify(
      original,
      mtgGraph: mtgGraph,
      tray: tray,
      outlineOnly: outlineOnly,
      titleAssets: titleAssets,
      onProgress: onProgress,
    );
  } finally {
    if (recognizer == null) active.close();
  }
}

class OracleRecognizer {
  OracleRecognizer(this.directory)
    : _config = jsonDecode(
        File(p.join(directory, 'catalog.json')).readAsStringSync(),
      ) as Map;

  final String directory;
  final _sessions = <String, Session>{};
  final Map _config;

  Session _open(String name) => _sessions.putIfAbsent(
    name,
    () => _openGraph(File(p.join(directory, '$name.onnx')).readAsBytesSync()),
  );

  Session _openExtra(String name, Uint8List graph) =>
      _sessions.putIfAbsent(name, () => _openGraph(graph));

  void warm({Uint8List? mtgGraph, PaddleTitleAssets? titleAssets}) {
    _open('detector');
    _open('embed');
    _open('search');
    if (mtgGraph != null) _openExtra('mtg', mtgGraph);
    if (titleAssets != null) _openExtra('title', titleAssets.graph);
  }

  void close() {
    for (final session in _sessions.values) {
      session.release();
    }
    _sessions.clear();
  }

  Recognition identify(
    im.Image original, {
    Uint8List? mtgGraph,
    TrayArea? tray,
    required bool outlineOnly,
    PaddleTitleAssets? titleAssets,
    ScanProgress? onProgress,
  }) {
    final config = _config;
    final constants = config['constants'] as Map;
    final side = constants['scene'] as int;
    final (bytes, width, height) = _scene(original, side);

    TitleRead? titleFor(List<double> corners) {
      if (titleAssets == null || corners.isEmpty) return null;
      try {
        final crop = tray?.corners ?? corners;
        return readPaddleTitle(
          original,
          crop,
          titleAssets,
          session: () => _openExtra('title', titleAssets.graph),
          retryQuad: tray == null ? null : corners,
          onRead: (points) => onProgress?.call(ScanStage.title, points),
        );
      } catch (_) {
        return null;
      }
    }

    final detector = _open('detector');
    final input = constants['det_input'] as int;
    final rotations = constants['rotations'] as int;
    late final embed = _open('embed');
    late final search = _open('search');
    late final mtg = _openExtra('mtg', mtgGraph!);

    if (tray != null) {
      final center = side / 2;
      final card = _detect(
        detector,
        bytes,
        side,
        input,
        center,
        center,
        side.toDouble(),
      );
      if (card.vote / rotations < .5) {
        return (hits: [], mtgHits: [], corners: [], title: null);
      }
      final upright =
          card.quad[0] < card.x &&
          card.quad[1] < card.y &&
          card.quad[2] > card.x &&
          card.quad[3] < card.y;
      final inside = upright && _isInTray(tray, side, width, height, card);
      final corners = inside || card.short >= side * .09
          ? _relativeCorners(card.quad, side, width, height)
          : const <double>[];
      if (!inside) {
        return (hits: [], mtgHits: [], corners: corners, title: null);
      }
      onProgress?.call(ScanStage.card, corners);
      final title = titleFor(corners);
      onProgress?.call(ScanStage.artwork, tray.corners);
      final (artwork, artQuad) = _trayArtwork(original, tray, side);
      final hits = _identifyCard(embed, search, config, artwork, side, artQuad);
      if ((hits.firstOrNull?.score ?? 0) < .60) {
        return (hits: [], mtgHits: [], corners: corners, title: title);
      }
      return (
        hits: hits,
        mtgHits: mtgGraph == null ? [] : _runMtg(mtg, artwork, side, artQuad),
        corners: corners,
        title: title,
      );
    }

    var outline = const <double>[];
    TitleRead? title;
    for (final window in _windows(side, width, height)) {
      final coarse = _detect(
        detector,
        bytes,
        side,
        input,
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
        input,
        coarse.x,
        coarse.y,
        refine,
      );
      if (fine.vote / rotations < 0.5 || fine.short < side * 0.09) continue;
      final corners = _relativeCorners(fine.quad, side, width, height);
      if (outlineOnly) {
        return (hits: [], mtgHits: [], corners: corners, title: null);
      }
      onProgress?.call(ScanStage.card, corners);
      if (outline.isEmpty) {
        outline = corners;
        title = titleFor(corners);
      }
      onProgress?.call(ScanStage.artwork, corners);
      final hits = _identifyCard(embed, search, config, bytes, side, fine.quad);
      if (hits.isEmpty || hits.first.score < .60) continue;
      final mtgHits = mtgGraph == null
          ? const <Hit>[]
          : _runMtg(mtg, bytes, side, fine.quad);
      if ((title?.confidence ?? 0) < .86 &&
          (title?.contrast?.confidence ?? 0) < .86 &&
          !identical(outline, corners)) {
        title = titleFor(corners);
      }
      return (hits: hits, mtgHits: mtgHits, corners: corners, title: title);
    }
    return (hits: [], mtgHits: [], corners: outline, title: title);
  }
}

List<double> _relativeCorners(
  Float32List quad,
  int side,
  int width,
  int height,
) => [
  for (var i = 0; i < quad.length; i++)
    _unitCoord(quad[i], side, i.isEven ? width : height),
];

bool _isInTray(
  TrayArea area,
  int side,
  int width,
  int height,
  _Detection card,
) {
  final offsetX = (side - width) ~/ 2, offsetY = (side - height) ~/ 2;
  final l = offsetX + area.left * width, r = offsetX + area.right * width;
  final t = offsetY + area.top * height, b = offsetY + area.bottom * height;
  final size = math.min(r - l, b - t);
  final near =
      (card.x - (l + r) / 2).abs() <= size * .11 &&
      (card.y - (t + b) / 2).abs() <= size * .11;
  return near && card.short >= size * .75 && card.short <= size * 1.25;
}

Session _openGraph(Uint8List graph) => Session.fromBytes(
  graph,
  options: const SessionOptions(intraOpNumThreads: 2),
);

(Uint8List, int, int) _scene(im.Image original, int side) {
  final scale = side / math.max(original.width, original.height);
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
  return (
    scene.getBytes(order: im.ChannelOrder.rgba),
    scaled.width,
    scaled.height,
  );
}

(Uint8List, Float32List) _trayArtwork(im.Image image, TrayArea tray, int side) {
  final left = tray.left * image.width, right = tray.right * image.width;
  final top = tray.top * image.height, bottom = tray.bottom * image.height;
  final padX = (right - left) * .09, padY = (bottom - top) * .09;
  final x = math.max(0, (left - padX).floor());
  final y = math.max(0, (top - padY).floor());
  final cropWidth = math.min(image.width, (right + padX).ceil()) - x;
  final cropHeight = math.min(image.height, (bottom + padY).ceil()) - y;
  final (bytes, width, height) = _scene(
    im.copyCrop(image, x: x, y: y, width: cropWidth, height: cropHeight),
    side,
  );
  final offsetX = (side - width) ~/ 2, offsetY = (side - height) ~/ 2;
  final l = offsetX + (left - x) * width / cropWidth;
  final r = offsetX + (right - x) * width / cropWidth;
  final t = offsetY + (top - y) * height / cropHeight;
  final b = offsetY + (bottom - y) * height / cropHeight;
  var light = 0.0, samples = 0;
  for (var y = t.ceil(); y < b; y += 13) {
    for (var x = l.ceil(); x < r; x += 13) {
      final offset = (y * side + x) * 4;
      light +=
          .21 * bytes[offset] +
          .72 * bytes[offset + 1] +
          .07 * bytes[offset + 2];
      samples++;
    }
  }
  if (samples > 0 && light / samples < 90) {
    for (var offset = 0; offset < bytes.length; offset += 4) {
      for (var channel = 0; channel < 3; channel++) {
        final i = offset + channel;
        bytes[i] = (bytes[i] * 1.5625 - 32).round().clamp(0, 255);
      }
    }
  }
  return (bytes, Float32List.fromList([l, t, r, t, r, b, l, b]));
}

List<Hit> _runMtg(
  Session encoder,
  Uint8List scene,
  int side,
  Float32List quad,
) => _run(encoder, {
  'scene': _pixels(scene, side),
  'quad': _floats(quad, [4, 2]),
}, _readHits);

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
  return _run(search, {
    'embeddings': _floats(features, [features.length ~/ 128, 128]),
    if (config['searchMask'] == true)
      'mask': _floats(
        Float32List(config['count'] as int)
          ..fillRange(0, config['count'] as int, 1),
        [config['count'] as int],
      ),
  }, _readHits);
}

List<Hit> _readHits(Map<String, OrtTensor> outputs) {
  final ids = outputs['indices']!.view.int64s;
  final scores = outputs['scores']!.view.float32s;
  return [
    for (var i = 0; i < ids.length; i++)
      if (scores[i] >= 0.0) (index: ids[i], score: scores[i]),
  ];
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
