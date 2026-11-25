import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class ScanMesh extends StatefulWidget {
  const ScanMesh({super.key, required this.outline, required this.reading});

  final List<Offset> outline;
  final bool reading;

  @override
  State<ScanMesh> createState() => _ScanMeshState();
}

class _ScanMeshState extends State<ScanMesh>
    with SingleTickerProviderStateMixin {
  final _elapsed = ValueNotifier(Duration.zero);
  late final Ticker _ticker = createTicker((time) => _elapsed.value = time);
  _Mesh _mesh = _makeMesh();
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _updateMotion();
  }

  @override
  void didUpdateWidget(ScanMesh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reading != oldWidget.reading) {
      if (widget.reading) _mesh = _makeMesh();
      _updateMotion();
    }
  }

  void _updateMotion() {
    if (widget.reading && !_reducedMotion) {
      if (!_ticker.isActive) {
        _elapsed.value = Duration.zero;
        _ticker.start();
      }
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedOpacity(
        duration: _reducedMotion
            ? Duration.zero
            : Duration(milliseconds: widget.reading ? 150 : 380),
        opacity: widget.reading ? 1 : 0,
        child: CustomPaint(
          painter: _MeshPainter(
            widget.outline,
            _mesh,
            _elapsed,
            _reducedMotion,
          ),
        ),
      ),
    ),
  );
}

const _columns = 7, _rows = 5;
typedef _Mesh = ({List<_Node> nodes, List<(int, int)> links});

class _Node {
  const _Node(this.origin, this.phase, this.speed);

  final Offset origin;
  final Offset phase;
  final double speed;

  Offset at(double seconds) =>
      origin +
      Offset(
        math.sin(phase.dx + seconds * speed) * .23 / _columns,
        math.sin(phase.dy + seconds * speed * .79) * .23 / _rows,
      );
}

_Mesh _makeMesh() {
  final random = math.Random();
  double offset() => .5 + (random.nextDouble() - .5) * .49;
  final nodes = [
    for (var y = 0; y < _rows; y++)
      for (var x = 0; x < _columns; x++)
        _Node(
          Offset((x + offset()) / _columns, (y + offset()) / _rows),
          Offset(
            random.nextDouble() * 2 * math.pi,
            random.nextDouble() * 2 * math.pi,
          ),
          1.1 + random.nextDouble() * 2.2,
        ),
  ];
  final links = <(int, int)>[];
  for (var y = 0; y < _rows; y++) {
    for (var x = 0; x < _columns; x++) {
      final node = y * _columns + x;
      if (x + 1 < _columns) links.add((node, node + 1));
      if (y + 1 < _rows) {
        links.add((node, node + _columns));
        if (x + 1 < _columns) {
          links.add(
            random.nextBool()
                ? (node, node + _columns + 1)
                : (node + 1, node + _columns),
          );
        }
      }
    }
  }
  return (nodes: nodes, links: links);
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.outline, this.mesh, this.elapsed, this.reducedMotion)
    : super(repaint: elapsed);

  final List<Offset> outline;
  final _Mesh mesh;
  final ValueNotifier<Duration> elapsed;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final [topLeft, topRight, bottomRight, bottomLeft] = outline;
    Offset screen(Offset point) => Offset.lerp(
      Offset.lerp(topLeft, bottomLeft, point.dy)!,
      Offset.lerp(topRight, bottomRight, point.dy)!,
      point.dx,
    )!;

    final seconds =
        elapsed.value.inMicroseconds / Duration.microsecondsPerSecond;
    final pass = seconds / .72 % 3;
    final center = Offset(-.34 + 1.68 * (pass % 1), .10 + .80 * pass / 3);
    double light(Offset point) {
      if (reducedMotion) return 0;
      final x = (point.dx - center.dx) / .36;
      final y = (point.dy - center.dy) / .43;
      final strength = math.max(0.0, 1 - x * x - y * y);
      return strength * strength;
    }

    final nodes = [
      for (final node in mesh.nodes)
        reducedMotion ? node.origin : node.at(seconds),
    ];
    final projected = nodes.map(screen).toList();
    const white = Color(0xffffffff);
    final paint = Paint()..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipPath(Path()..addPolygon(outline, true));
    for (final (a, b) in mesh.links) {
      final brightness = light((nodes[a] + nodes[b]) * .5);
      paint
        ..strokeWidth = .65 + .65 * brightness
        ..color = white.withValues(alpha: .16 + .46 * brightness);
      canvas.drawLine(projected[a], projected[b], paint);
    }
    for (final (index, point) in nodes.indexed) {
      final brightness = light(point);
      paint.color = white.withValues(alpha: .35 + .52 * brightness);
      canvas.drawCircle(projected[index], 1.05 + .95 * brightness, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      !listEquals(outline, old.outline) ||
      old.mesh != mesh ||
      old.reducedMotion != reducedMotion;
}
