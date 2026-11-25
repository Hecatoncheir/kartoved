import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/ui/picture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('Повреждённые изображения Scryfall не скрывают снимок', (
    tester,
  ) async {
    const card = Edition(
      '54772e15-d99d-4eec-ba8d-b9202a7e318b',
      "Bouncer's Beatdown",
      'snc',
      '135',
      'en',
      foil: true,
    );
    final root = Directory.systemTemp.createTempSync('kartoved-picture-');
    final pictures = Directory(p.join(root.path, 'pictures'))..createSync();
    final scan = File(p.join(pictures.path, '${card.id}.scan.jpg'))
      ..writeAsBytesSync(
        File('test/fixtures/bouncers-beatdown.jpg').readAsBytesSync(),
      );
    for (final name in [card.id, '${card.id}.normal']) {
      File(p.join(pictures.path, '$name.jpg'))
          .writeAsStringSync('Некорректный JPEG');
    }
    final messenger = tester.binding.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(paths, null);
      await root.delete(recursive: true);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 168,
            child: CardPicture(card, large: true),
          ),
        ),
      ),
    );
    final decoded = find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image != null,
    );
    for (var i = 0; decoded.evaluate().isEmpty && i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(decoded, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image == FileImage(scan),
      ),
      findsOneWidget,
    );
    expect(find.text(card.name), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await tester.pump();
  });
}
