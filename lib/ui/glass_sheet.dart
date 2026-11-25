import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'library_style.dart';
import 'scanner_style.dart';

Future<T?> showLibrarySheet<T>(BuildContext context, Widget child) =>
    showGlassSheet<T>(context, child, library: true);

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
      data: library ? libraryTheme : scannerTheme,
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
