import 'dart:math' as math;
import 'dart:typed_data';

import 'frame.dart';

typedef TrayPhoto = ({Uint8List bytes, String footer});

// Эталон меняем только при распознавании: медленный сдвиг карты не потеряется.
class TrayChangeDetector {
  Uint8List? _last;
  int _checked = 0;
  int? _session;

  bool shouldInspect(
    Uint8List sample,
    int now,
    int session, {
    bool force = false,
  }) {
    final last = _last;
    if (!force &&
        _session == session &&
        last != null &&
        last.length == sample.length &&
        now - _checked < 2000) {
      var changed = 0;
      for (var i = 0; i < sample.length; i++) {
        if ((sample[i] - last[i]).abs() >= 12) changed++;
      }
      if (changed < sample.length ~/ 12) return false;
    }
    _last = sample;
    _checked = now;
    _session = session;
    return true;
  }
}

bool sameTrayPrinting(Uint8List saved, Uint8List current) {
  const pixels = TrayArea.detailSide * TrayArea.detailSide;
  if (saved.length != 4 * pixels || saved.length != current.length) {
    return false;
  }
  for (var start = 0; start < saved.length; start += pixels) {
    var changed = 0;
    for (var i = start; i < start + pixels; i++) {
      if ((saved[i] - current[i]).abs() >= 10) changed++;
      // Несколько изменившихся букв в одной строке уже требуют чтения.
      if (changed >= 6) return false;
    }
  }
  return true;
}

class TrayArea {
  const TrayArea(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  List<double> get bounds => [left, top, right, bottom];
  // Для повтора сравниваем также название, текст правил и выходные данные.
  List<double> sampleRegions(bool details) {
    final regions = [
      (.14, .18, .86, .48),
      if (details) ...[
        (.07, .043, .76, .095),
        (.08, .65, .91, .85),
        (.045, .922, .46, .977),
      ],
    ];
    return [
      for (final (l, t, r, b) in regions) ...[
        left + l * (right - left),
        top + t * (bottom - top),
        left + r * (right - left),
        top + b * (bottom - top),
      ],
    ];
  }

  static const detailSide = 32;
  static int sampleSide(bool details) => details ? detailSide : 16;

  Uint8List sampleFrame(PreviewFrame frame, {bool details = false}) {
    final bounds = sampleRegions(details);
    final side = sampleSide(details);
    final pixels = side * side;
    final sample = Uint8List(pixels * (bounds.length ~/ 4));
    for (var region = 0; region < bounds.length; region += 4) {
      final l = bounds[region], t = bounds[region + 1];
      final w = bounds[region + 2] - l, h = bounds[region + 3] - t;
      for (var i = 0; i < pixels; i++) {
        final x = l + w * ((i % side) + .5) / side;
        final y = t + h * ((i ~/ side) + .5) / side;
        final (sx, sy) = switch (frame.rotation) {
          90 => (y, 1 - x),
          180 => (1 - x, 1 - y),
          270 => (1 - y, x),
          _ => (x, y),
        };
        sample[(region ~/ 4) * pixels + i] =
            frame.bytes[(sy * frame.height).floor() * frame.width +
                (sx * frame.width).floor()];
      }
    }
    return sample;
  }

  List<double> get corners => [
    left,
    top,
    right,
    top,
    right,
    bottom,
    left,
    bottom,
  ];

  static TrayArea? calibrate(List<double> points) {
    if (points.length != 8 || points.any((p) => !p.isFinite)) return null;
    final xs = [points[0], points[2], points[4], points[6]];
    final ys = [points[1], points[3], points[5], points[7]];
    final area = TrayArea(
      xs.reduce(math.min).clamp(0.0, 1.0),
      ys.reduce(math.min).clamp(0.0, 1.0),
      xs.reduce(math.max).clamp(0.0, 1.0),
      ys.reduce(math.max).clamp(0.0, 1.0),
    );
    final width = area.right - area.left, height = area.bottom - area.top;
    if (width < .08 || height < .08) return null;
    final expected = area.corners;
    for (var i = 0; i < points.length; i++) {
      final tolerance = (i.isEven ? width : height) * .10;
      if ((points[i] - expected[i]).abs() > tolerance) return null;
    }
    return area;
  }
}
