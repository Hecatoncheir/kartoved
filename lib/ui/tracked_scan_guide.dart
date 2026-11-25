import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'browser_glass.dart';
import 'scan_frame.dart';
import 'scan_mesh.dart';

class TrackedScanGuide extends StatefulWidget {
  const TrackedScanGuide({
    super.key,
    required this.viewport,
    required this.window,
    required this.outline,
    this.focus,
    required this.showGuide,
    required this.hasPreview,
    required this.reading,
  });

  final Size viewport;
  final Rect window;
  final List<Offset>? outline;
  final List<Offset>? focus;
  final bool showGuide, hasPreview, reading;

  @override
  State<TrackedScanGuide> createState() => _TrackedScanGuideState();
}

class _TrackedScanGuideState extends State<TrackedScanGuide>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 155),
  );
  List<Offset>? _from;
  List<Offset>? _fromFocus;

  List<Offset> _corners(Rect rect) => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  List<Offset>? _shape(List<Offset>? start, List<Offset>? end, Rect window) {
    if (start == null || _motion.isCompleted) return end;
    final target = end ?? _corners(window);
    final progress = Curves.easeOutCubic.transform(_motion.value);
    return [
      for (var i = 0; i < 4; i++) Offset.lerp(start[i], target[i], progress)!,
    ];
  }

  List<Offset>? _outline(TrackedScanGuide guide) =>
      _shape(_from, guide.outline, guide.window);

  List<Offset>? _focus(TrackedScanGuide guide) =>
      _shape(_fromFocus, guide.focus ?? guide.outline, guide.window);

  @override
  void didUpdateWidget(TrackedScanGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(widget.outline, oldWidget.outline) &&
        listEquals(widget.focus, oldWidget.focus)) {
      return;
    }
    if (!widget.hasPreview ||
        (!widget.showGuide && !widget.reading) ||
        widget.viewport != oldWidget.viewport ||
        MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 1;
      return;
    }
    final fallback = _corners(oldWidget.window);
    _from = _outline(oldWidget) ?? fallback;
    _fromFocus = _focus(oldWidget) ?? fallback;
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (_, _) {
      final outline = _outline(widget);
      final focus = widget.showGuide ? _focus(widget) : outline;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (kIsWeb && widget.hasPreview)
            BrowserGlass(
              widget.window,
              widget.viewport,
              visible: widget.showGuide,
              outline: outline,
            ),
          if (widget.showGuide)
            ScanFrame(
              window: widget.window,
              hasPreview: !kIsWeb && widget.hasPreview,
              outline: outline,
              focus: focus,
            ),
          if (focus != null) ScanMesh(outline: focus, reading: widget.reading),
        ],
      );
    },
  );
}
