import 'package:flutter/widgets.dart';

class BrowserGlass extends StatelessWidget {
  const BrowserGlass(this.window, this.viewport, {super.key});

  final Rect window;
  final Size viewport;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
