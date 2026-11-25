import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera_view_mask/mask/mask.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'style.dart';

class ScanFrame extends StatelessWidget {
  const ScanFrame({
    super.key,
    required this.window,
    required this.hasPreview,
    this.outline,
    this.focus,
  });

  static const aspectRatio = 63 / 88;
  static const radius = 16.0;

  final Rect window;
  final bool hasPreview;
  final List<Offset>? outline;
  final List<Offset>? focus;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (hasPreview)
          ClipPath(
            clipper: _OutsideFrame(window, outline),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      raised.withValues(alpha: .30),
                      dark.withValues(alpha: .56),
                    ],
                  ),
                ),
              ),
            ),
          ),
        CustomPaint(painter: _Corners(window, focus ?? outline)),
      ],
    ),
  );
}

class _OutsideFrame extends CustomClipper<Path> {
  const _OutsideFrame(this.window, this.outline);

  final Rect window;
  final List<Offset>? outline;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addPath(_hole(), Offset.zero);

  Path _hole() {
    if (outline case final points?) return Path()..addPolygon(points, true);
    return Mask(
      offset: window.topLeft,
      size: window.size,
      borderRadius: ScanFrame.radius,
      border: Border.all(),
    ).toPath();
  }

  @override
  bool shouldReclip(_OutsideFrame old) =>
      window != old.window || !listEquals(outline, old.outline);
}

class _Corners extends CustomPainter {
  const _Corners(this.window, this.outline);

  final Rect window;
  final List<Offset>? outline;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = ScanFrame.radius;
    final paint = Paint()
      ..color = butter
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    if (outline case final points?) {
      for (var i = 0; i < 4; i++) {
        final point = points[i];
        final before = points[(i - 1) % 4];
        final after = points[(i + 1) % 4];
        final entry = _towards(point, before, 23);
        final exit = _towards(point, after, 23);
        final start = _towards(point, before, 5);
        final end = _towards(point, after, 5);
        canvas.drawPath(
          Path()
            ..moveTo(entry.dx, entry.dy)
            ..lineTo(start.dx, start.dy)
            ..quadraticBezierTo(point.dx, point.dy, end.dx, end.dy)
            ..lineTo(exit.dx, exit.dy),
          paint,
        );
      }
      return;
    }
    final corner = Path()
      ..moveTo(0, 29)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(29, 0);
    final points = [
      window.topLeft,
      window.topRight,
      window.bottomRight,
      window.bottomLeft,
    ];
    for (final (index, point) in points.indexed) {
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(index * math.pi / 2);
      canvas.drawPath(corner, paint);
      canvas.restore();
    }
  }

  Offset _towards(Offset from, Offset to, double length) => Offset.lerp(
    from,
    to,
    length / math.max((to - from).distance, length * 2),
  )!;

  @override
  bool shouldRepaint(_Corners old) =>
      window != old.window || !listEquals(outline, old.outline);
}
