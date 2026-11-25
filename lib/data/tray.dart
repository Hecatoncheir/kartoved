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

class TrayArea {
  const TrayArea(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  List<double> get bounds => [left, top, right, bottom];
  // Смотрим внутрь иллюстрации, чтобы движение руки у края лотка не мешало.
  List<double> get artwork => [
    left + .14 * (right - left),
    top + .18 * (bottom - top),
    left + .86 * (right - left),
    top + .48 * (bottom - top),
  ];
  static const sampleSide = 16;

  Uint8List sampleFrame(PreviewFrame frame) {
    final [l, t, r, b] = artwork;
    final sample = Uint8List(sampleSide * sampleSide);
    for (var i = 0; i < sample.length; i++) {
      final x = l + (r - l) * ((i % sampleSide) + .5) / sampleSide;
      final y = t + (b - t) * ((i ~/ sampleSide) + .5) / sampleSide;
      final (sx, sy) = switch (frame.rotation) {
        90 => (y, 1 - x),
        180 => (1 - x, 1 - y),
        270 => (1 - y, x),
        _ => (x, y),
      };
      sample[i] =
          frame.bytes[(sy * frame.height).floor() * frame.width +
              (sx * frame.width).floor()];
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
