import 'package:flutter/widgets.dart';

class BrowserGlass extends StatelessWidget {
  const BrowserGlass(
    this.window,
    this.viewport, {
    required this.visible,
    this.outline,
    super.key,
  });

  final Rect window;
  final Size viewport;
  final bool visible;
  final List<Offset>? outline;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
