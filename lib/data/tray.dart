import 'dart:math' as math;
import 'dart:typed_data';

typedef TrayPhoto = ({Uint8List bytes, String footer});

class TrayArea {
  const TrayArea(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  List<double> get bounds => [left, top, right, bottom];
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
