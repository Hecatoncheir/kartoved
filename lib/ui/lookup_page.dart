import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'library_style.dart';
import 'scanner_style.dart';
import 'style.dart';

/// Поиск в каталоге, среди изданий и в списке сканера.
class LookupPage extends StatelessWidget {
  const LookupPage({
    super.key,
    required this.title,
    required this.header,
    required this.results,
    this.actions,
    this.scanner = false,
  });

  final String title;
  final Widget header;
  final Widget results;
  final List<Widget>? actions;
  final bool scanner;

  @override
  Widget build(BuildContext context) {
    final theme = scanner ? scannerTheme : libraryTheme;
    return Theme(
      data: theme,
      child: DecoratedBox(
        decoration: scanner
            ? const BoxDecoration(gradient: scanBackdrop)
            : librarySky,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            forceMaterialTransparency: true,
            systemOverlayStyle: scanner
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            foregroundColor: theme.colorScheme.onSurface,
            title: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: headingFont,
                fontWeight: FontWeight.w900,
                fontSize: 21,
                height: 1.12,
              ),
            ),
            actions: actions,
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: NestedScrollView(
                    headerSliverBuilder: (_, _) => [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: header,
                        ),
                      ),
                    ],
                    body: scanner
                        ? ScanSurface(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: results,
                            ),
                          )
                        : LibraryGlass(child: results),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LookupHint extends StatelessWidget {
  const LookupHint(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
