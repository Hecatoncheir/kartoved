import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'style.dart';

class ScanParticles extends StatefulWidget {
  const ScanParticles({
    super.key,
    required this.outline,
    required this.reading,
  });

  final List<Offset> outline;
  final bool reading;

  @override
  State<ScanParticles> createState() => _ScanParticlesState();
}

class _ScanParticlesState extends State<ScanParticles> {
  final _field = _AttractorField();
  Timer? _motion;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _updateSweep();
  }

  @override
  void didUpdateWidget(ScanParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reading != oldWidget.reading) _updateSweep();
  }

  void _updateSweep() {
    if (widget.reading && !_reducedMotion) {
      if (_motion == null) {
        _field.reset();
        final elapsed = Stopwatch()..start();
        _motion = Timer.periodic(const Duration(milliseconds: 42), (_) {
          _field.advance(elapsed.elapsedMilliseconds);
        });
      }
    } else {
      _motion?.cancel();
      _motion = null;
    }
  }

  @override
  void dispose() {
    _motion?.cancel();
    _field.dispose();
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
          painter: _ParticlePainter(widget.outline, _field, _reducedMotion),
        ),
      ),
    ),
  );
}

class _Particle {
  _Particle(
    this.origin,
    this.radius,
    this.pull,
    this.orbitRadius,
    this.orbitPhase,
    this.orbitSpeed,
  ) : point = origin,
      previous = origin;

  final Offset origin;
  final double radius, pull, orbitRadius, orbitPhase, orbitSpeed;
  Offset point, previous;
  Offset velocity = Offset.zero;
}

class _AttractorField extends ChangeNotifier {
  static const _route = [
    Offset(.13, .09),
    Offset(.80, .16),
    Offset(.21, .37),
    Offset(.78, .54),
    Offset(.19, .75),
    Offset(.83, .91),
    Offset(.13, .09),
  ];
  static final _path = TweenSequence<Offset>([
    for (var i = 0; i < _route.length - 1; i++)
      TweenSequenceItem(
        tween: Tween(
          begin: _route[i],
          end: _route[i + 1],
        ).chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: i.isEven ? 25 : 12,
      ),
  ]);

  late List<_Particle> particles = _createParticles();
  int _lastTick = 0;
  double opacity = 0;

  static List<_Particle> _createParticles() {
    final random = math.Random();
    return List.generate(
      50,
      (_) => _Particle(
        Offset(
          .08 + random.nextDouble() * .84,
          .08 + random.nextDouble() * .80,
        ),
        .45 + random.nextDouble() * 1.05,
        42 + random.nextDouble() * 30,
        .045 + random.nextDouble() * .22,
        random.nextDouble() * 2 * math.pi,
        (random.nextBool() ? 1 : -1) * (4.0 + random.nextDouble() * 8),
      ),
    );
  }

  void reset() {
    _lastTick = 0;
    opacity = 0;
    particles = _createParticles();
    notifyListeners();
  }

  void advance(int elapsed) {
    const period = 1520;
    final phase = (elapsed % period) / period;
    final step = math.min(.08, (elapsed - _lastTick) / 1000);
    _lastTick = elapsed;
    final attraction = _path.transform(phase);
    final seconds = elapsed / 1000;
    final drag = math.exp(-6 * step);
    opacity = (math.sin(phase * math.pi) * 2.2).clamp(.20, 1.0);
    for (final particle in particles) {
      final angle = particle.orbitPhase + seconds * particle.orbitSpeed;
      final radius = particle.orbitRadius * (1 + .25 * math.sin(angle * .63));
      final orbit = Offset(math.cos(angle), math.sin(angle)) * radius;
      final force = (attraction + orbit - particle.point) * particle.pull;
      particle.previous = particle.point;
      particle.velocity = (particle.velocity + force * step) * drag;
      particle.point += particle.velocity * step;
    }
    notifyListeners();
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.outline, this.field, this.reducedMotion)
    : super(repaint: field);

  final List<Offset> outline;
  final _AttractorField field;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final [topLeft, topRight, bottomRight, bottomLeft] = outline;
    Offset screen(Offset p) => Offset.lerp(
      Offset.lerp(topLeft, bottomLeft, p.dy)!,
      Offset.lerp(topRight, bottomRight, p.dy)!,
      p.dx,
    )!;
    final paint = Paint()..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipPath(Path()..addPolygon(outline, true));
    for (final (i, particle) in field.particles.indexed) {
      final point = screen(reducedMotion ? particle.origin : particle.point);
      final color = i.isEven ? butter : paper;
      final alpha = (reducedMotion ? .28 : field.opacity * .66);
      if (!reducedMotion) {
        final tail = screen(
          Offset.lerp(particle.point, particle.previous, .42)!,
        );
        paint
          ..color = color.withValues(alpha: alpha * .34)
          ..strokeWidth = particle.radius;
        canvas.drawLine(tail, point, paint);
      }
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(point, particle.radius, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      !listEquals(outline, old.outline) || reducedMotion != old.reducedMotion;
}
