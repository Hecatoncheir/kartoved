import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:kartoved/data/frame.dart';
import 'package:kartoved/scan_cubit.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:kartoved/data/language.dart';

void main() => runOfflineTests(
  const String.fromEnvironment('CARD_JPEG'),
  const String.fromEnvironment('RUSSIAN_JPEG'),
);
void runOfflineTests(String englishPhoto, String russianPhoto) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Холодный старт и добавление карты без сети', (tester) async {
    final model = AppModel(CatalogStore(), History());
    await model.initialize();
    expect(model.initialError, isNull);
    expect(model.catalog!.spec.count, greaterThan(50000));
    final temp = await Directory.systemTemp.createTemp('kartoved-test');
    try {
      final photo = File(p.join(temp.path, 'sample.jpg'));
      await photo.writeAsBytes(base64Decode(englishPhoto));
      final cards = await model.recognize(photo.path);
      expect(cards.first.editions.first.name, "Bouncer's Beatdown");
      final english = cards.first.editions.firstWhere(
        (e) => e.language == 'en',
      );
      expect(english.set, 'snc');
      expect(english.number, '135');
      await model.save(english);
      final saved = await model.history.list();
      expect(saved.first.card.id, english.id);
      expect(
        (await CardLanguage.identify(
          file: photo.path,
          corners: cards.first.corners,
          options: cards.first.editions,
        )).language,
        'en',
      );
      final russian = File(p.join(temp.path, 'ru.jpg'));
      await russian.writeAsBytes(base64Decode(russianPhoto));
      final russianMatch = (await model.recognize(russian.path)).first;
      final candidates = russianMatch.editions;
      final ru = await CardLanguage.identify(
        file: russian.path,
        corners: russianMatch.corners,
        options: candidates,
      );
      expect(ru.language, 'ru');
      final frame = _cameraFrame(await russian.readAsBytes());
      final liveMatches = await model.recognizeFrame(frame);
      final scan = ScanCubit()..toggle();
      expect(scan.evaluate(liveMatches), isNull);
      expect(scan.evaluate(liveMatches)?.name, "Bouncer's Beatdown");
      final live = await CardLanguage.identify(
        frame: frame,
        corners: liveMatches.first.corners,
        options: liveMatches.first.editions,
      );
      expect(live.id, ru.id);
      scan.gate.saved(live);
      expect(scan.evaluate(liveMatches), isNull);
      scan.shutter();
      expect(scan.evaluate(liveMatches), isNotNull);
      await scan.close();
      await model.create('Русские карты');
      await model.save(ru);
      await model.save(ru);
      expect(model.state.recent.length, 2);
      expect(
        await model.export(),
        contains('"2","Bouncer\'s Beatdown","SNC","","Russian","","135"'),
      );
      await model.select(1);
      expect(model.state.recent.single.card.id, english.id);
      final old = model.catalog!;
      final next = CatalogSpec({
        ...old.spec.raw,
        'version': 'acceptance-update',
        'created': old.spec.created
            .add(const Duration(days: 1))
            .toIso8601String(),
      });
      await expectLater(
        model.store.installUpdate(old, next, (_) async => Stream.value([0])),
        throwsFormatException,
      );
      expect((await model.store.initialize()).spec.version, old.spec.version);
      final updated = await model.store.installUpdate(old, next, (name) async {
        expect(name, 'cards.sqlite.pack');
        final bytes = await rootBundle.load('assets/oracle/$name');
        return Stream.value(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      });
      expect(
        (await model.store.initialize()).spec.version,
        updated.spec.version,
      );
      expect((await model.history.list()).first.card.id, english.id);
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
  testWidgets('Старая коллекция переезжает с исходным количеством', (_) async {
    final path = p.join(await getDatabasesPath(), 'migration.sqlite');
    final old = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE cards(id TEXT PRIMARY KEY,name TEXT,set_code TEXT,number TEXT,lang TEXT,qty INTEGER,touched INTEGER)',
      ),
    );
    await old.rawInsert(
      "INSERT INTO cards VALUES ('a','Opt','eld','59','ru',3,123)",
    );
    await old.close();
    final history = History();
    await history.open(path: path);
    expect((await history.list()).single.quantity, 3);
    expect((await history.folders()).single.count, 3);
  });
}

PreviewFrame _cameraFrame(Uint8List jpg) {
  final source = img.decodeJpg(jpg)!;
  final width = source.width & ~1, height = source.height & ~1;
  final output = Uint8List(width * height * 3 ~/ 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = source.getPixel(x, y);
      final r = pixel.r, g = pixel.g, b = pixel.b;
      output[y * width + x] = (16 + .257 * r + .504 * g + .098 * b)
          .round()
          .clamp(0, 255);
      if (x.isEven && y.isEven) {
        final idx = width * height + (y ~/ 2) * width + x;
        output[idx] = (128 + .439 * r - .368 * g - .071 * b).round().clamp(
          0,
          255,
        );
        output[idx + 1] = (128 - .148 * r - .291 * g + .439 * b).round().clamp(
          0,
          255,
        );
      }
    }
  }
  return (bytes: output, width: width, height: height, rotation: 0);
}
