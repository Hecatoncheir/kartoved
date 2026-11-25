import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:onnxruntime_core/onnxruntime_core.dart';

import 'recognition_result.dart';
import 'scan_progress.dart';

const paddleTitleAssets = 'assets/paddleocr';
typedef PaddleTitleAssets = ({Uint8List graph, List<String> alphabet});

TitleRead? readPaddleTitle(
  im.Image source,
  List<double> quad,
  PaddleTitleAssets assets, {
  void Function()? onRead,
}) {
  if (quad.length != 8) return null;
  const height = 48, width = 320;
  const bounds = titleRegion;
  final topLeft = cardPoint(quad, bounds.left, bounds.top);
  final topRight = cardPoint(quad, bounds.right, bounds.top);
  final bottomLeft = cardPoint(quad, bounds.left, bounds.bottom);
  final titleWidth = _distance(topLeft, topRight, source);
  final titleHeight = _distance(topLeft, bottomLeft, source);
  if (titleWidth < 12 || titleHeight < 5) return null;
  onRead?.call();
  final available = (height * titleWidth / titleHeight).ceil().clamp(2, width);
  const plane = height * width;
  final data = Float32List(3 * plane);
  for (var y = 0; y < height; y++) {
    final v = bounds.top + (bounds.bottom - bounds.top) * (y + .5) / height;
    for (var x = 0; x < available; x++) {
      final u =
          bounds.left + (bounds.right - bounds.left) * (x + .5) / available;
      final (sx, sy) = cardPoint(quad, u, v);
      final pixel = source.getPixelInterpolate(
        (sx * source.width).clamp(0, source.width - 1.0),
        (sy * source.height).clamp(0, source.height - 1.0),
        interpolation: im.Interpolation.linear,
      );
      final i = y * width + x;
      data[i] = pixel.b / 127.5 - 1;
      data[plane + i] = pixel.g / 127.5 - 1;
      data[2 * plane + i] = pixel.r / 127.5 - 1;
    }
  }

  final session = Session.fromBytes(
    assets.graph,
    options: const SessionOptions(intraOpNumThreads: 2),
  );
  try {
    final tensor = OrtTensor.fromData(OrtElementType.float32, data, [
      1,
      3,
      height,
      width,
    ]);
    Map<String, OrtTensor> outputs = {};
    try {
      outputs = session.run({'x': tensor});
      final view = outputs.values.first.view;
      return _decode(view.float32s, view.shape.last, assets.alphabet, quad);
    } finally {
      for (final output in outputs.values) {
        output.release();
      }
      tensor.release();
    }
  } finally {
    session.release();
  }
}

double _distance((double, double) a, (double, double) b, im.Image source) =>
    math.sqrt(
      math.pow((a.$1 - b.$1) * source.width, 2) +
          math.pow((a.$2 - b.$2) * source.height, 2),
    );

TitleRead? _decode(
  Float32List values,
  int classes,
  List<String> alphabet,
  List<double> corners,
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
  return title.isEmpty
      ? null
      : (text: title, confidence: score / count, corners: corners);
}
