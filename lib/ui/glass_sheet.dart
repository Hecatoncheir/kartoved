import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'library_style.dart';
import 'scanner_style.dart';
import 'style.dart';

Future<T?> showGlassSheet<T>(
  BuildContext context,
  Widget child, {
  bool library = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 600),
  builder: (_) => GlassSheet(library: library, child: child),
);

class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child, this.library = false});

  final Widget child;
  final bool library;

  @override
  Widget build(BuildContext context) {
    final content = Theme(
      data: library ? libraryTheme : _scannerTheme(Theme.of(context)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: child,
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: double.infinity,
          maxHeight: (MediaQuery.sizeOf(context).height * .53)
              .clamp(430, 560)
              .toDouble(),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: library
                ? LibraryGlass(radius: 24, child: content)
                : ScanSurface(radius: 24, child: content),
          ),
        ),
      ),
    );
  }
}

ThemeData _scannerTheme(ThemeData base) => base.copyWith(
  colorScheme: base.colorScheme.copyWith(
    primary: scanOrange,
    onSurface: scanPaper,
    onSurfaceVariant: scanMuted,
    surface: scanInk,
    outlineVariant: const Color(0xff66647c),
    outline: const Color(0xff9792aa),
    secondaryContainer: const Color(0xff4b405c),
  ),
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
