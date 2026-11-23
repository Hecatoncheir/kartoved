import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

const ink = Color(0xff282828),
    paper = Color(0xfffbf1c7),
    cream = Color(0xfff2e5bc);
const butter = Color(0xfffabd2f),
    muted = Color(0xff665c54),
    dark = Color(0xff1d2021);
ThemeData kartovedTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: butter).copyWith(
    primary: ink,
    onPrimary: paper,
    surface: paper,
    onSurface: ink,
    secondary: butter,
    outline: muted,
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Nunito Sans',
    scaffoldBackgroundColor: paper,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        textStyle: const TextStyle(
          fontFamily: 'Nunito Sans',
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class Mark extends StatelessWidget {
  const Mark({super.key, this.size = 44, this.color = butter});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: _Mark(color)),
  );
}

class _Mark extends CustomPainter {
  _Mark(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    final paint = Paint()..color = color;
    final back = Path()
      ..moveTo(12, 23)
      ..lineTo(54, 13)
      ..lineTo(56, 18)
      ..lineTo(19, 28)
      ..lineTo(27, 77)
      ..lineTo(23, 79)
      ..close();
    canvas.drawPath(back, paint);
    final face = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(26, 26)
      ..lineTo(76, 17)
      ..quadraticBezierTo(80, 16, 81, 21)
      ..lineTo(90, 74)
      ..quadraticBezierTo(91, 78, 86, 80)
      ..lineTo(38, 90)
      ..quadraticBezierTo(34, 90, 33, 85)
      ..close();
    face.moveTo(43, 61);
    face.cubicTo(45, 48, 56, 46, 57, 35);
    face.cubicTo(65, 42, 63, 48, 62, 50);
    face.cubicTo(67, 47, 70, 42, 70, 40);
    face.cubicTo(79, 62, 67, 73, 54, 74);
    face.cubicTo(60, 69, 62, 63, 61, 58);
    face.cubicTo(55, 66, 47, 68, 43, 61);
    face.close();
    canvas.drawPath(face, paint);
  }

  @override
  bool shouldRepaint(_Mark old) => old.color != color;
}

class Frost extends StatelessWidget {
  const Frost({super.key, required this.child, this.radius = 26});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 17, sigmaY: 17),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: paper.withValues(alpha: .20)),
        ),
        child: child,
      ),
    ),
  );
}

class RoundAction extends StatelessWidget {
  const RoundAction(this.icon, this.label, this.tap, {super.key});
  final IconData icon;
  final String label;
  final VoidCallback? tap;
  @override
  Widget build(BuildContext context) => Frost(
    child: IconButton(
      tooltip: label,
      onPressed: tap,
      icon: Icon(icon, color: paper),
      constraints: const BoxConstraints.tightFor(width: 50, height: 50),
    ),
  );
}

class SheetHeading extends StatelessWidget {
  const SheetHeading(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      fontFamily: 'Nunito',
      fontSize: 30,
      height: 1.15,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.0,
    ),
  );
}

class Folio extends StatelessWidget {
  const Folio({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(190, 140), painter: _Folio());
}

class _Folio extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 190, s.height / 140);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    final shadow = Paint()..color = ink;
    c.drawOval(const Rect.fromLTWH(18, 98, 153, 18), shadow);
    void card(double x, double y, double tilt, Color color, bool mark) {
      c.save();
      c.translate(x, y);
      c.rotate(tilt);
      final r = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-30, -43, 60, 86),
        const Radius.circular(5),
      );
      c.drawRRect(r, Paint()..color = color);
      c.drawRRect(r, pen);
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-24, -35, 48, 61),
          const Radius.circular(3),
        ),
        pen,
      );
      if (mark) {
        c.save();
        c.translate(-23, -30);
        _Mark(ink).paint(c, const Size.square(48));
        c.restore();
      }
      c.drawLine(const Offset(-22, 32), const Offset(-4, 32), pen);
      c.restore();
    }

    card(71, 62, -.34, cream, false);
    card(95, 57, -.05, paper, false);
    card(117, 61, .22, butter, true);
    for (final pt in [const Offset(29, 42), const Offset(156, 32)]) {
      final star = Path()
        ..moveTo(pt.dx, pt.dy - 8)
        ..quadraticBezierTo(pt.dx + 1, pt.dy - 1, pt.dx + 7, pt.dy)
        ..quadraticBezierTo(pt.dx + 1, pt.dy + 1, pt.dx, pt.dy + 8)
        ..quadraticBezierTo(pt.dx - 1, pt.dy + 1, pt.dx - 7, pt.dy)
        ..quadraticBezierTo(pt.dx - 1, pt.dy - 1, pt.dx, pt.dy - 8)
        ..close();
      c.drawPath(star, shadow);
    }
  }

  @override
  bool shouldRepaint(_Folio old) => false;
}
