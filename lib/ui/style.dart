import 'package:material_ui/material_ui.dart';

const headingFont = 'Nunito';
const bodyFont = 'Nunito Sans';
const monoFont = 'JetBrains Mono';
const codeText = TextStyle(fontFamily: monoFont);
const noticeDuration = Duration(seconds: 3);

ThemeData appTheme(ColorScheme colors) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  final theme = ThemeData(
    colorScheme: colors,
    fontFamily: bodyFont,
    scaffoldBackgroundColor: colors.surface,
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.surface.withValues(alpha: .78),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(
          fontFamily: bodyFont,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
  final text = theme.textTheme;
  return theme.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(
        fontFamily: headingFont,
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontFamily: headingFont,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class Mark extends StatelessWidget {
  const Mark({super.key, this.size = 44, required this.color});
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

class SheetHeading extends StatelessWidget {
  const SheetHeading(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: headingFont,
              fontSize: 24,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -.5,
            ),
          ),
        ),
      ),
      if (ModalRoute.of(context) is PopupRoute)
        IconButton(
          tooltip: 'Закрыть',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
    ],
  );
}
