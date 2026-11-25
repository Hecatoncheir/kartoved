import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:kartoved/data/android.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/pictures.dart';
import 'package:kartoved/ui/picture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

const _card = Edition(
  '54772e15-d99d-4eec-ba8d-b9202a7e318b',
  "Bouncer's Beatdown",
  'snc',
  '135',
  'en',
);

void main() {
  testWidgets('При сбоях кэша и загрузки видна миниатюра кадра Android', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('kartoved-android-photo-');
    final pictures = Directory(p.join(root.path, 'pictures'))..createSync();
    final cached = File(p.join(pictures.path, '${_card.id}.scan.jpg'));
    final blocked = Directory('${cached.path}.part')..createSync();
    final messenger = tester.binding.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const android = MethodChannel('kartoved/android');
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    messenger.setMockMethodCallHandler(android, (_) async => null);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(android, null);
      await root.delete(recursive: true);
    });
    await tester.runAsync(() => Pictures.shared.scanThumbnail(_card.id));

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(width: 120, height: 168, child: CardPicture(_card)),
        ),
      ),
    );
    expect(find.text(_card.name), findsOneWidget);

    final photo = (await tester.runAsync(() async {
      final photo = await AndroidActions.scanPhoto(
        file: 'test/fixtures/bouncers-beatdown.jpg',
        corners: const [.1, .1, .9, .1, .9, .9, .1, .9],
      );
      expect(im.decodeJpg(photo!)?.width, 420);
      await Pictures.shared.saveScan(_card.id, photo);
      return photo;
    }))!;
    final decoded = find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image != null,
    );
    for (var i = 0; i < 50 && decoded.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(decoded, findsOneWidget);
    expect(find.text(_card.name), findsNothing);
    expect(cached.existsSync(), isFalse);
    expect(await Pictures.shared.scanThumbnail(_card.id), isA<MemoryImage>());
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await tester.pump();

    await tester.runAsync(() async {
      await blocked.delete();
      await cached.writeAsString('Недописанный снимок');
      await Pictures.shared.saveScan(_card.id, photo);
      expect(await cached.readAsBytes(), photo);
      expect(await Pictures.shared.scanThumbnail(_card.id), FileImage(cached));
    });
  });

  test(
    'При сбое канала резервная миниатюра строится из цветного NV21',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const android = MethodChannel('kartoved/android');
      messenger.setMockMethodCallHandler(android, (_) async {
        throw PlatformException(code: 'thumbnail_failed');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(android, null));
      const width = 32, height = 48, luma = width * height;
      final bytes = Uint8List(luma * 3 ~/ 2)..fillRange(0, luma, 120);
      for (var i = luma; i < bytes.length; i += 2) {
        bytes[i] = 168;
        bytes[i + 1] = 91;
      }
      final photo = await AndroidActions.scanPhoto(
        frame: (bytes: bytes, width: width, height: height, rotation: 90),
        corners: const [.1, .1, .9, .1, .9, .9, .1, .9],
      );
      final image = im.decodeJpg(photo!)!;
      final pixel = image.getPixel(image.width ~/ 2, image.height ~/ 2);
      expect(image.height, 587);
      expect(pixel.r - pixel.b, greaterThan(70));
    },
  );
}
