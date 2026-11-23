import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';

final _tilt = _Tilt();

class _Tilt extends ValueNotifier<Offset> with WidgetsBindingObserver {
  _Tilt() : super(Offset.zero);
  StreamSubscription<AccelerometerEvent>? sensor;
  Offset? baseline;

  @override
  void addListener(VoidCallback listener) {
    final first = !hasListeners;
    super.addListener(listener);
    if (first) {
      WidgetsBinding.instance.addObserver(this);
      _start();
    }
  }

  void _start() {
    if (kIsWeb || !Platform.isAndroid) return;
    sensor ??=
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 60),
        ).listen((event) {
          final reading = Offset(event.x, event.y);
          baseline ??= reading;
          final delta = (reading - baseline!) / 4;
          final target = Offset(delta.dx.clamp(-1, 1), delta.dy.clamp(-1, 1));
          if ((target - value).distance > .025) {
            value = Offset.lerp(value, target, .4)!;
          }
        }, onError: (Object _) {});
  }

  void _stop() {
    sensor?.cancel();
    sensor = null;
    baseline = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      WidgetsBinding.instance.removeObserver(this);
      _stop();
      value = Offset.zero;
    }
  }
}

class TiltCard extends StatelessWidget {
  const TiltCard({
    super.key,
    required this.child,
    required this.slot,
    required this.foil,
  });
  final Widget child;
  final int slot;
  final bool foil;

  Widget _face(Offset tilt, Widget image) {
    if (!foil) return image;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        image,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(
                  begin: Alignment(-1.4 + tilt.dx, -1 + tilt.dy),
                  end: Alignment(1.4 + tilt.dx, 1 + tilt.dy),
                  colors: const [
                    Color(0x0083a598),
                    Color(0x478fe7dd),
                    Color(0x48fee390),
                    Color(0x51d899ba),
                    Color(0x007daea3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      return _face(Offset.zero, child);
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (e) => _tilt.value = Offset(
        (_tilt.value.dx + e.delta.dx / 35).clamp(-1, 1),
        (_tilt.value.dy + e.delta.dy / 35).clamp(-1, 1),
      ),
      onPointerUp: (_) => _tilt.value = Offset.zero,
      onPointerCancel: (_) => _tilt.value = Offset.zero,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _tilt,
        child: child,
        builder: (_, offset, image) {
          final angle = (slot % 8) * 2.4;
          final x = offset.dx * math.cos(angle) - offset.dy * math.sin(angle);
          final y = offset.dx * math.sin(angle) + offset.dy * math.cos(angle);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            transformAlignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0015)
              ..translateByDouble(x * 2, y * 2, 0, 1)
              ..rotateX(-y * .12)
              ..rotateY(x * .15)
              ..rotateZ(x * .028),
            child: _face(Offset(x, y), image!),
          );
        },
      ),
    );
  }
}
