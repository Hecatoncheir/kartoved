import 'package:material_ui/material_ui.dart';

import 'style.dart';

const scanInk = Color(0xff11162b);
const scanPaper = Color(0xfffff0df);
const scanMuted = Color(0xffd9cbe5);
const scanOrange = Color(0xffff942f);
const scanBackdrop = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xff533357), Color(0xff251e45), Color(0xff132d48)],
);

class ScanSurface extends StatelessWidget {
  const ScanSurface({super.key, required this.child, this.radius = 18});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xe24a3759), Color(0xf02b2943), Color(0xeb253951)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x667f91b5)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x32100e20),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

final scannerTheme =
    appTheme(
      ColorScheme.fromSeed(
        seedColor: scanOrange,
        brightness: Brightness.dark,
      ).copyWith(
        onPrimary: scanInk,
        primary: scanOrange,
        onSurface: scanPaper,
        onSurfaceVariant: scanMuted,
        surface: scanInk,
        outlineVariant: const Color(0xff66647c),
        outline: const Color(0xff9792aa),
        secondaryContainer: const Color(0xff4b405c),
      ),
    ).copyWith(
      dividerColor: const Color(0x557f849f),
      listTileTheme: const ListTileThemeData(
        textColor: scanPaper,
        iconColor: scanMuted,
        titleTextStyle: TextStyle(
          fontFamily: bodyFont,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: scanPaper,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: bodyFont,
          fontSize: 14,
          color: scanMuted,
        ),
      ),
    );
