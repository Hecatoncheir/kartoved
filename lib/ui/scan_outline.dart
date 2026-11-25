import 'package:flutter/painting.dart';

class ScanOutline {
  const ScanOutline(this.points);

  final List<Offset> points;

  static ScanOutline? fromCamera(
    List<double> corners, {
    required bool mirror,
    double minTurn = .001,
  }) {
    if (corners.length != 8 ||
        corners.any(
          (value) => !value.isFinite || value < -.25 || value > 1.25,
        )) {
      return null;
    }
    final points = [
      for (var i = 0; i < corners.length; i += 2)
        Offset(mirror ? 1 - corners[i] : corners[i], corners[i + 1]),
    ];
    final start = points.reduce((a, b) => a.dx + a.dy < b.dx + b.dy ? a : b);
    final index = points.indexOf(start);
    final after = points[(index + 1) % 4] - start;
    final before = points[(index - 1) % 4] - start;
    final turn = after.dx * before.dy - after.dy * before.dx;
    if (turn.abs() < minTurn) return null;
    final direction = turn > 0 ? 1 : -1;
    return ScanOutline([
      for (var i = 0; i < 4; i++) points[(index + direction * i) % 4],
    ]);
  }

  ScanOutline follow(ScanOutline next) {
    final gaps = [
      for (var i = 0; i < 4; i++) (points[i] - next.points[i]).distance,
    ];
    if (gaps.every((gap) => gap < .004)) return this;
    if (gaps.any((gap) => gap > .08)) return next;
    return ScanOutline([
      for (var i = 0; i < 4; i++) Offset.lerp(points[i], next.points[i], .65)!,
    ]);
  }

  List<Offset> project(Size source, Size viewport) {
    final fit = applyBoxFit(BoxFit.cover, source, viewport);
    final crop = Alignment.center.inscribe(fit.source, Offset.zero & source);
    return [
      for (final point in points)
        Offset(
          (point.dx * source.width - crop.left) * viewport.width / crop.width,
          (point.dy * source.height - crop.top) * viewport.height / crop.height,
        ),
    ];
  }
}
