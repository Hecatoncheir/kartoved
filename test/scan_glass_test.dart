import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/ui/scan_frame.dart';
import 'package:kartoved/ui/scan_glass.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Матовое стекло размывает фон вокруг рамки камеры', (
    tester,
  ) async {
    const size = Size(280, 340);
    const window = Rect.fromLTWH(55, 50, 126, 176);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: const Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.black),
              Positioned(
                top: 119,
                height: 4,
                left: 0,
                right: 0,
                child: ColoredBox(color: Colors.white),
              ),
              ScanFrame(window: window, hasPreview: true),
            ],
          ),
        ),
      ),
    );
    final mask = tester.widget<ClipPath>(find.byType(ClipPath)).clipper!;
    final path = mask.getClip(size);
    expect(window.width / window.height, ScanFrame.aspectRatio);
    expect(path.contains(window.center), isFalse);
    expect(path.contains(window.topLeft + const Offset(1, 1)), isTrue);
    expect(path.contains(const Offset(25, 120)), isTrue);

    final pixels = (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int red(int x, int y) => data.getUint8((y * image.width + x) * 4);
      final result = (
        clear: red(100, 120),
        dark: red(100, 125),
        blurred: red(25, 120),
      );
      image.dispose();
      return result;
    }))!;
    expect(pixels.clear, 255);
    expect(pixels.dark, 0);
    expect(pixels.blurred, inInclusiveRange(5, 140));
  });

  final refracts = ui.ImageFilter.isShaderFilterSupported;
  for (final density in [1.0, 2.0]) {
    testWidgets(
      'Стекло при плотности $density: ${refracts ? 'преломление' : 'матовый фон'}',
      (tester) async {
        tester.view.devicePixelRatio = density;
        tester.view.physicalSize = const Size(220, 140) * density;
        addTearDown(tester.view.reset);
        if (refracts) {
          await tester.runAsync(
            () => ui.FragmentProgram.fromAsset('shaders/scan_glass.frag'),
          );
        }
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  const Positioned(
                    top: 48,
                    height: 22,
                    left: 0,
                    right: 0,
                    child: ColoredBox(color: Colors.white),
                  ),
                  Positioned(
                    left: 23,
                    top: 34,
                    width: 160,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: const ScanGlass(child: SizedBox.expand()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        final pixels = (await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: density);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int red(int x, int y) => data.getUint8(
            ((y * density).round() * image.width + (x * density).round()) * 4,
          );
          final values = (
            edge: red(100, 38),
            center: red(100, 58),
            outside: red(12, 38),
          );
          image.dispose();
          return values;
        }))!;
        expect(pixels.outside, 0);
        expect(pixels.center, greaterThan(220));
        // Кромка смещает белую полосу как минимум на 10 логических пикселей.
        expect(
          pixels.edge,
          refracts ? greaterThan(180) : inInclusiveRange(2, 55),
        );
      },
    );
  }
}
