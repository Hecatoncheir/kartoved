import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Холодный старт и добавление карты без сети', (tester) async {
    final model = AppModel(CatalogStore(), History());
    await model.initialize();
    expect(model.initialError, isNull);
    expect(model.catalog!.spec.count, greaterThan(50000));
    final temp = await Directory.systemTemp.createTemp('kartoved-test');
    try {
      final photo = File(p.join(temp.path, 'sample.jpg'));
      await photo.writeAsBytes(
        base64Decode(const String.fromEnvironment('CARD_JPEG')),
      );
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
        expect(name, 'cards.sqlite.gz');
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
  }, timeout: const Timeout(Duration(minutes: 4)));
}
