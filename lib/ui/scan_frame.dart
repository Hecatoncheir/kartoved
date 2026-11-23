import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera_view_mask/mask/mask.dart';
import 'package:material_ui/material_ui.dart';

import 'style.dart';

class ScanFrame extends StatelessWidget {
  const ScanFrame({super.key, required this.window, required this.hasPreview});

  static const aspectRatio = 63 / 88;
  static const radius = 16.0;

  final Rect window;
  final bool hasPreview;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (hasPreview)
          ClipPath(
            clipper: _OutsideFrame(window),
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
        CustomPaint(painter: _Corners(window)),
      ],
    ),
  );
}

class _OutsideFrame extends CustomClipper<Path> {
  const _OutsideFrame(this.window);

  final Rect window;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addPath(
      Mask(
        offset: window.topLeft,
        size: window.size,
        borderRadius: ScanFrame.radius,
        border: Border.all(),
      ).toPath(),
      Offset.zero,
    );

  @override
  bool shouldReclip(_OutsideFrame old) => window != old.window;
}

class _Corners extends CustomPainter {
  const _Corners(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = ScanFrame.radius;
    final paint = Paint()
      ..color = butter
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
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

  @override
  bool shouldRepaint(_Corners old) => window != old.window;
}
