import 'dart:convert';
import 'dart:io';

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
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
