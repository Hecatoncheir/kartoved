import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:kartoved/data/frame.dart';
import 'package:kartoved/data/android.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/scan_decision.dart';
import 'package:kartoved/scan_processing.dart';
import 'package:kartoved/data/review.dart';
import 'package:kartoved/data/tray.dart';

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
    debugPrint('Автономная проверка: загрузка каталога');
    await model.initialize();
    expect(model.initialError, isNull);
    expect(model.catalog!.spec.count, greaterThan(50000));
    final temp = await Directory.systemTemp.createTemp('kartoved-test');
    try {
      debugPrint('Автономная проверка: распознавание контрольного фото');
      final photo = File(p.join(temp.path, 'sample.jpg'));
      await photo.writeAsBytes(base64Decode(englishPhoto));
      final cards = await model.recognize(photo.path);
      expect(cards.first.editions.first.name, "Bouncer's Beatdown");
      final english = cards.first.editions.firstWhere(
        (e) => e.language == 'en',
      );
      final thumbnail = await AndroidActions.scanPhoto(
        file: photo.path,
        corners: cards.first.corners,
      );
      expect(img.decodeJpg(thumbnail!)?.width, 600);
      final trayText = await AndroidActions.readTrayText(thumbnail);
      expect(
        trayText.text.trim(),
        isNotEmpty,
        reason: 'OCR должен прочитать текст за пределами иллюстрации',
      );
      debugPrint('Автономная проверка: карта у края кадра NV21');
      final edgeFrame = _cameraFrame(_offsetPhoto(await photo.readAsBytes()));
      final edgeMatches = await model.recognizeFrame(edgeFrame);
      expect(edgeMatches.first.editions.first.name, "Bouncer's Beatdown");
      expect(edgeMatches.first.corners[1], lessThan(.10));
      final edgeThumbnail = await AndroidActions.scanPhoto(
        frame: edgeFrame,
        corners: edgeMatches.first.corners,
      );
      expect(img.decodeJpg(edgeThumbnail!)?.height, 840);
      final catalog = model.catalog!;
      expect((await catalog.searchNames('солнечное кольцо')).first, 'Sol Ring');
      expect((await catalog.searchNames('sol ring')).first, 'Sol Ring');
      final rings = await catalog.byName('Sol Ring');
      expect(
        rings.firstWhere((e) => e.set == 'mps' && e.number == '24').foil,
        isTrue,
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
      for (final (file, matches, language) in [
        (photo, cards, 'en'),
        (russian, [russianMatch], 'ru'),
      ]) {
        final quick = await prepareScan(
          matches,
          library: model,
          batch: const BatchSettings(),
          isCurrent: () => true,
          rescan: false,
          essentials: true,
          file: file.path,
        );
        expect(quick?.decision.card.language, language);
        expect(quick?.decision.card.name, english.name);
        final repeat = await prepareScan(
          matches,
          library: model,
          batch: const BatchSettings(),
          isCurrent: () => true,
          rescan: false,
          essentials: true,
          repeatCheck: TrayRepeatCheck.replacement,
          tray: const TrayArea(0, 0, 1, 1),
          file: file.path,
        );
        expect(
          repeat?.decision.review,
          isNull,
          reason:
              '$language: ${repeat?.decision.review?.reason}, ${repeat?.decision.card.detail}, оценка ${matches.first.score}',
        );
        expect(repeat?.decision.card.language, language);
        expect(repeat?.decision.card.name, english.name);
      }
      final candidates = russianMatch.editions;
      final ru = await CardLanguage.identify(
        file: russian.path,
        corners: russianMatch.corners,
        options: candidates,
      );
      expect(ru.language, 'ru');
      debugPrint('Автономная проверка: распознавание кадра NV21');
      final frame = _cameraFrame(await russian.readAsBytes());
      const area = TrayArea(.1, .1, .9, .9);
      final detector = TrayChangeDetector();
      final timer = Stopwatch()..start();
      expect(detector.shouldInspect(area.sampleFrame(frame), 0, 1), isTrue);
      final liveMatches = await model.recognizeFrame(frame);
      final recognitionMs = timer.elapsedMilliseconds;
      timer.reset();
      for (var i = 1; i <= 10; i++) {
        expect(
          detector.shouldInspect(area.sampleFrame(frame), i * 100, 1),
          isFalse,
        );
      }
      debugPrint(
        'Лоток NV21: распознавание $recognitionMs мс, пропущено 10 одинаковых кадров за ${timer.elapsedMicroseconds} мкс',
      );
      final scan = ScanCubit()..toggle();
      expect(scan.evaluate(liveMatches), isNull);
      expect(scan.evaluate(liveMatches)?.name, "Bouncer's Beatdown");
      final evidence = await CardLanguage.readOptions(
        frame: frame,
        corners: liveMatches.first.corners,
        options: liveMatches.first.editions,
      );
      final live = decideScan(
        liveMatches,
        evidence,
        const BatchSettings(language: 'ru', setCode: 'snc'),
      ).card;
      expect(live.id, ru.id);
      scan.gate.saved(live);
      expect(scan.evaluate(liveMatches), isNull);
      scan.shutter();
      expect(scan.evaluate(liveMatches), isNotNull);
      await scan.close();
      await model.create('Русские карты');
      final conflict = decideScan(
        liveMatches,
        evidence,
        const BatchSettings(setCode: 'eld'),
      );
      expect(conflict.review?.reason, ReviewReason.batch);
      final seq = await model.save(conflict.card, review: conflict.review);
      expect(model.state.reviews[seq]?.batchLabel, 'ELD');
      final russianFolder = model.state.folder;
      debugPrint('Автономная проверка: системный диалог сохранения');
      expect(await model.saveBackup(), isTrue);
      await model.create('После копирования');
      debugPrint('Автономная проверка: системный диалог восстановления');
      final backup = await model.openBackup();
      expect(backup?.pending, 1);
      await model.restoreBackup(backup!);
      expect(
        model.state.groups.map((g) => g.name),
        isNot(contains('После копирования')),
      );
      expect(model.state.recent.single.card.id, english.id);
      await model.select(russianFolder);
      expect(model.state.reviews[seq]?.batchLabel, 'ELD');
      expect(await model.export(), contains("Bouncer's Beatdown"));
      expect(
        await model.export(includePending: false),
        isNot(contains("Bouncer's Beatdown")),
      );
      expect(model.state.owned(english.name), 1);
      await model.confirmReview(seq, live);
      expect(model.state.printings.single.card.language, 'ru');
      await model.discardScan(seq);
      expect(model.state.recent, isEmpty);
      await model.save(ru);
      await model.save(ru);
      expect(model.state.recent.length, 2);
      expect(
        await model.export(),
        contains('"2","Bouncer\'s Beatdown","SNC","","Russian","","135"'),
      );
      final ring = rings.firstWhere((e) => e.set == 'mps' && e.number == '24');
      await model.addFromCatalog(russianFolder, ring, 4);
      final move = await model.moveCards(1, ring, 2);
      expect(model.state.holdings['Sol Ring'], {russianFolder: 2, 1: 2});
      expect(model.state.owned(english.name), 3);
      await model.undoMove(move);
      expect(model.state.holdings['Sol Ring'], {russianFolder: 4});
      await model.select(1);
      expect(model.state.recent.single.card.id, english.id);
      final old = model.catalog!;
      debugPrint('Автономная проверка: обновление каталога');
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

  testWidgets('Миграция обычных карт и раздельный учёт фольги', (_) async {
    final path = p.join(await getDatabasesPath(), 'foil-migration.sqlite');
    final old = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE scans(seq INTEGER PRIMARY KEY, folder INTEGER, id TEXT, name TEXT, set_code TEXT, number TEXT, lang TEXT, qty INTEGER)',
        );
        await db.execute(
          "INSERT INTO scans VALUES (1,1,'opt','Opt','eld','59','en',3)",
        );
      },
    );
    await old.close();
    final history = History();
    await history.open(path: path);
    final plain = (await history.list()).single;
    expect(plain.card.foil, isFalse);
    await history.add(plain.card.withFoil(true));
    final rows = await history.list();
    expect(rows.where((r) => r.card.foil).single.quantity, 1);
    expect(rows.where((r) => !r.card.foil).single.quantity, 3);
  });
}

Uint8List _offsetPhoto(Uint8List jpg) {
  final scene = img.Image(width: 800, height: 1100);
  img.fill(scene, color: img.ColorRgb8(82, 77, 67));
  final card = img.copyResize(
    img.bakeOrientation(img.decodeJpg(jpg)!),
    width: 300,
  );
  img.compositeImage(scene, card, dstX: 490, dstY: 24);
  return img.encodeJpg(scene, quality: 93);
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
