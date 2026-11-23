import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

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
        await CardLanguage.read(
          file: photo.path,
          options: cards.first.editions,
        ),
        'en',
      );
      final russian = File(p.join(temp.path, 'ru.jpg'));
      await russian.writeAsBytes(base64Decode(russianPhoto));
      final candidates = (await model.recognize(russian.path)).first.editions;
      final lang = await CardLanguage.read(
        file: russian.path,
        options: candidates,
      );
      expect(lang, 'ru');
      final ru = CardLanguage.select(candidates, lang);
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
