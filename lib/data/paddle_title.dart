import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:onnxruntime_core/onnxruntime_core.dart';

import 'recognition_result.dart';
import 'scan_progress.dart';

const paddleTitleAssets = 'assets/paddleocr';
typedef PaddleTitleAssets = ({Uint8List graph, List<String> alphabet});
typedef _Strip = ({Float32List pixels, int columns});

const _height = 48, _width = 320, _plane = _height * _width;

TitleRead? readPaddleTitle(
  im.Image source,
  List<double> quad,
  PaddleTitleAssets assets, {
  List<double>? retryQuad,
  void Function(List<double>)? onRead,
}) {
  final strip = _sample(source, quad, onRead);
  if (strip == null) return null;
  final session = Session.fromBytes(
    assets.graph,
    options: const SessionOptions(intraOpNumThreads: 2),
  );
  try {
    final color = _recognize(session, strip.pixels, assets.alphabet);
    TitleCandidate? contrast;
    if ((color?.confidence ?? 0) < .93) {
      try {
        final retry = retryQuad == null
            ? strip
            : _sample(source, retryQuad, onRead) ?? strip;
        _increaseContrast(retry);
        contrast = _recognize(session, retry.pixels, assets.alphabet);
      } catch (_) {
        if (color == null) rethrow;
        // Исходное чтение остаётся доступным, если повторный проход прервался.
      }
    }
    final first = color ?? contrast;
    if (first == null) return null;
    return (
      text: first.text,
      confidence: first.confidence,
      corners: quad,
      contrast: color == null ? null : contrast,
    );
  } finally {
    session.release();
  }
}

_Strip? _sample(
  im.Image source,
  List<double> quad,
  void Function(List<double>)? onRead,
) {
  if (quad.length != 8) return null;
  const bounds = titleRegion;
  final topLeft = cardPoint(quad, bounds.left, bounds.top);
  final topRight = cardPoint(quad, bounds.right, bounds.top);
  final bottomLeft = cardPoint(quad, bounds.left, bounds.bottom);
  final titleWidth = _distance(topLeft, topRight, source);
  final titleHeight = _distance(topLeft, bottomLeft, source);
  if (titleWidth < 12 || titleHeight < 5) return null;
  onRead?.call(quad);
  final columns = (_height * titleWidth / titleHeight).ceil().clamp(2, _width);
  final data = Float32List(3 * _plane);
  for (var y = 0; y < _height; y++) {
    final v = bounds.top + (bounds.bottom - bounds.top) * (y + .5) / _height;
    for (var x = 0; x < columns; x++) {
      final u = bounds.left + (bounds.right - bounds.left) * (x + .5) / columns;
      final (sx, sy) = cardPoint(quad, u, v);
      final pixel = source.getPixelInterpolate(
        (sx * source.width).clamp(0, source.width - 1.0),
        (sy * source.height).clamp(0, source.height - 1.0),
        interpolation: im.Interpolation.linear,
      );
      final i = y * _width + x;
      data[i] = pixel.b / 127.5 - 1;
      data[_plane + i] = pixel.g / 127.5 - 1;
      data[2 * _plane + i] = pixel.r / 127.5 - 1;
    }
  }
  return (pixels: data, columns: columns);
}

void _increaseContrast(_Strip strip) {
  final (pixels: data, :columns) = strip;
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < columns; x++) {
      final i = y * _width + x;
      final gray =
          .0722 * data[i] +
          .7152 * data[_plane + i] +
          .2126 * data[2 * _plane + i];
      data[i] = gray;
      histogram[((gray + 1) * 127.5).round().clamp(0, 255)]++;
    }
  }
  double percentile(double fraction) {
    final target = columns * _height * fraction;
    var count = 0;
    for (var i = 0; i < histogram.length; i++) {
      count += histogram[i];
      if (count >= target) return i / 127.5 - 1;
    }
    return 1;
  }

  final low = percentile(.05), high = percentile(.95);
  final center = (low + high) / 2;
  final gain = math.min(2.5, 1.8 / math.max(.08, high - low));
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < columns; x++) {
      final i = y * _width + x;
      final gray = ((data[i] - center) * gain).clamp(-1.0, 1.0);
      data[i] = data[_plane + i] = data[2 * _plane + i] = gray;
    }
  }
}

TitleCandidate? _recognize(
  Session session,
  Float32List data,
  List<String> alphabet,
) {
  final tensor = OrtTensor.fromData(OrtElementType.float32, data, [
    1,
    3,
    _height,
    _width,
  ]);
  var outputs = <String, OrtTensor>{};
  try {
    outputs = session.run({'x': tensor});
    final view = outputs.values.first.view;
    return _decode(view.float32s, view.shape.last, alphabet);
  } finally {
    for (final output in outputs.values) {
      output.release();
    }
    tensor.release();
  }
}

double _distance((double, double) a, (double, double) b, im.Image source) =>
    math.sqrt(
      math.pow((a.$1 - b.$1) * source.width, 2) +
          math.pow((a.$2 - b.$2) * source.height, 2),
    );

TitleCandidate? _decode(
  Float32List values,
  int classes,
  List<String> alphabet,
) {
  if (classes != alphabet.length + 1 && classes != alphabet.length + 2) {
    return null;
  }
  final text = StringBuffer();
  var score = 0.0, count = 0, previous = 0;
  for (var offset = 0; offset < values.length; offset += classes) {
    var best = 0;
    for (var i = 1; i < classes; i++) {
      if (values[offset + i] > values[offset + best]) best = i;
    }
    if (best != 0 && best != previous) {
      text.write(best <= alphabet.length ? alphabet[best - 1] : ' ');
      score += values[offset + best];
      count++;
    }
    previous = best;
  }
  final title = text.toString().trim();
  return title.isEmpty ? null : (text: title, confidence: score / count);
}
