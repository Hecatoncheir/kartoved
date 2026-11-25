import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../data/pictures.dart';
import 'library_style.dart';

class CollectionLight extends StatelessWidget {
  const CollectionLight({
    super.key,
    required this.cardIds,
    required this.child,
  });

  final Iterable<String> cardIds;
  final Widget child;

  static const _centers = [
    Alignment(.90, -.85),
    Alignment(-.95, .86),
    Alignment(-.88, -.30),
    Alignment(.95, .32),
    Alignment(.75, 1.05),
    Alignment(-.70, -.92),
  ];

  @override
  Widget build(BuildContext context) {
    final samples = cardIds.toSet().take(_centers.length);
    return DecoratedBox(
      decoration: librarySky,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final (index, id) in samples.indexed)
            _CardGlow(id, _centers[index], key: ValueKey(id)),
          child,
        ],
      ),
    );
  }
}

class _CardGlow extends StatefulWidget {
  const _CardGlow(this.id, this.center, {required super.key});

  final String id;
  final Alignment center;

  @override
  State<_CardGlow> createState() => _CardGlowState();
}

class _CardGlowState extends State<_CardGlow> {
  late Future<Color?> color = _readColor(widget.id);
  late final StreamSubscription<String> photos;

  @override
  void initState() {
    super.initState();
    photos = Pictures.shared.photos.listen((id) {
      if (id != widget.id) return;
      setState(() {
        color = _readColor(id);
      });
    });
  }

  @override
  void dispose() {
    photos.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Color?>(
    future: color,
    builder: (context, snapshot) {
      final shade = snapshot.data ?? Colors.transparent;
      return AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: widget.center,
            radius: 1.05,
            colors: [
              shade.withValues(alpha: shade.a * .14),
              shade.withValues(alpha: 0),
            ],
          ),
        ),
      );
    },
  );
}

Future<Color?> _readColor(String id) async {
  try {
    final bytes = await Pictures.shared.thumbnailBytes(id);
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 20);
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    final image = frame.image;
    try {
      final pixels = await image.toByteData();
      return pixels == null
          ? null
          : _artColor(pixels, image.width, image.height);
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

Color _artColor(ByteData pixels, int width, int height) {
  var red = 0, green = 0, blue = 0, weightSum = 0;
  // Берём область иллюстрации между названием карты и текстом правил.
  for (var y = height ~/ 6; y < (height * .54).ceil(); y++) {
    for (var x = width ~/ 7; x < (width * .85).ceil(); x++) {
      final offset = (y * width + x) * 4;
      final r = pixels.getUint8(offset);
      final g = pixels.getUint8(offset + 1);
      final b = pixels.getUint8(offset + 2);
      final lightest = math.max<int>(r, math.max(g, b));
      final darkest = math.min<int>(r, math.min(g, b));
      final weight = 32 + lightest - darkest;
      red += r * weight;
      green += g * weight;
      blue += b * weight;
      weightSum += weight;
    }
  }
  return Color.fromARGB(
    255,
    red ~/ weightSum,
    green ~/ weightSum,
    blue ~/ weightSum,
  );
}
