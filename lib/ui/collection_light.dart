import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'style.dart';

class CollectionLight extends StatefulWidget {
  const CollectionLight({super.key, required this.child});
  final Widget child;

  @override
  State<CollectionLight> createState() => _CollectionLightState();
}

class _CollectionLightState extends State<CollectionLight>
    with SingleTickerProviderStateMixin {
  late final light = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      light.stop();
    } else if (!light.isAnimating) {
      light.repeat();
    }
  }

  @override
  void dispose() {
    light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: dark,
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: CustomPaint(painter: _Glow(light))),
        widget.child,
      ],
    ),
  );
}

class _Glow extends CustomPainter {
  _Glow(this.light) : super(repaint: light);
  final Animation<double> light;
  @override
  void paint(Canvas canvas, Size size) {
    final phase = light.value * math.pi * 2;
    // Мягкий край и более яркая складка дают глубину под полупрозрачными картами.
    void ribbon(double x, double y, double angle, Color color, double width) {
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.rotate(angle);
      final side = math.min(size.width, size.height) * width;
      canvas.scale(side);
      final path = Path()
        ..moveTo(-.82, .35)
        ..cubicTo(-.89, -.05, -.5, -.52, -.20, -.51)
        ..cubicTo(-.04, -.51, -.18, -.09, .10, -.13)
        ..cubicTo(.40, -.18, .45, -.59, .75, -.49)
        ..cubicTo(.68, -.12, .43, .42, .04, .48)
        ..cubicTo(-.32, .55, -.48, .16, -.82, .35)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .085)
          ..shader = ui.Gradient.linear(
            const Offset(-.52, -.4),
            const Offset(.44, .45),
            [
              color.withValues(alpha: .055),
              color.withValues(alpha: .30),
              color.withValues(alpha: .04),
            ],
            const [0, .48, 1],
          ),
      );
      canvas.restore();
    }

    ribbon(
      .77 + .18 * math.sin(phase),
      .16 + .09 * math.cos(phase),
      -.5 + .22 * math.sin(phase),
      const Color(0xffb8bb26),
      .88,
    );
    ribbon(
      .01 + .20 * math.cos(phase),
      .72 + .10 * math.sin(phase),
      1 + .35 * math.cos(phase),
      const Color(0xffd79921),
      .68,
    );
    ribbon(
      .93 + .10 * math.cos(phase),
      .91 + .07 * math.sin(phase),
      -.7,
      const Color(0xff689d6a),
      .53,
    );
  }

  @override
  bool shouldRepaint(_Glow old) => old.light != light;
}
