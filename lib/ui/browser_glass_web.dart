import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class BrowserGlass extends StatefulWidget {
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
  State<BrowserGlass> createState() => _BrowserGlassState();
}

class _BrowserGlassState extends State<BrowserGlass> {
  web.HTMLElement? _glass;

  @override
  void didUpdateWidget(BrowserGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) _updateVisibility();
    if (widget.window != oldWidget.window ||
        widget.viewport != oldWidget.viewport ||
        !listEquals(widget.outline, oldWidget.outline)) {
      _updatePath();
    }
  }

  void _create(Object element) {
    final glass = element as web.HTMLElement;
    _glass = glass;
    glass.style
      ..width = '100%'
      ..height = '100%'
      ..pointerEvents = 'none'
      ..backgroundImage = 'linear-gradient(140deg, #5049454d, #1d20218f)'
      ..setProperty('backdrop-filter', 'blur(15px)')
      ..setProperty('-webkit-backdrop-filter', 'blur(15px)');
    _updateVisibility();
    _updatePath();
  }

  void _updateVisibility() {
    _glass?.style.visibility = widget.visible ? 'visible' : 'hidden';
  }

  void _updatePath() {
    final viewport = widget.viewport;
    final frame = widget.window;
    final l = frame.left, t = frame.top, r = frame.right, b = frame.bottom;
    const radius = 16;
    final outside = 'M 0 0 H ${viewport.width} V ${viewport.height} H 0 Z';
    if (widget.outline case final points?) {
      final polygon = points
          .map((point) => '${point.dx} ${point.dy}')
          .join(' L ');
      _glass?.style.clipPath = 'path(evenodd, "$outside M $polygon Z")';
      return;
    }
    final hole =
        'M ${l + radius} $t H ${r - radius} Q $r $t $r ${t + radius} '
        'V ${b - radius} Q $r $b ${r - radius} $b '
        'H ${l + radius} Q $l $b $l ${b - radius} '
        'V ${t + radius} Q $l $t ${l + radius} $t Z';
    _glass?.style.clipPath = 'path(evenodd, "$outside $hole")';
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: _create,
    ),
  );
}
