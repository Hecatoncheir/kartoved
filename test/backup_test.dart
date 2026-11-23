import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/backup.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/review.dart';
import 'package:kartoved/model.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const en = Edition('one', 'Opt', 'eld', '59', 'en');
  const ru = Edition('two', 'Opt', 'dom', '60', 'ru', foil: true);
  const review = ScanReview(ReviewReason.batch, [
    ru,
    en,
  ], batchLabel: 'RU · ELD');

  test(
    'Перенос между двумя базами через файловый канал сохраняет все экземпляры',
    () async {
      final dir = await Directory.systemTemp.createTemp('kartoved-test-');
      addTearDown(() => dir.delete(recursive: true));
      Future<AppModel> phone(String name) async {
        final path = p.join(dir.path, name);
        final history = History();
        await history.open(path: path);
        final db = await openDatabase(path);
        addTearDown(db.close);
        final model = AppModel(CatalogStore(), history);
        addTearDown(model.close);
        return model;
      }

      final source = await phone('source.db');
      final target = await phone('target.db');
      final archive = File(p.join(dir.path, 'на обмен.json'));
      const channel = MethodChannel('kartoved/android');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final file = File(call.arguments['path'] as String);
        if (call.method == 'saveBackup') {
          expect(call.arguments['name'], endsWith('.json'));
          await file.copy(archive.path);
        } else {
          expect(call.method, 'openBackup');
          await archive.copy(file.path);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await source.create('Пустая');
      await source.create('На обмен 🃏');
      final folder = source.state.folder;
      final seq = await source.save(en);
      await source.save(ru);
      await source.save(ru);
      await source.setFlag(ru, true);
      final pending = await source.save(ru.withLanguage('und'), review: review);
      // В старых базах одна запись могла содержать несколько экземпляров.
      final db = await openDatabase(p.join(dir.path, 'source.db'));
      await db.update('scans', {'qty': 3}, where: 'seq=?', whereArgs: [seq]);
      await target.create('До восстановления');
      expect(await source.saveBackup(), isTrue);
      final originalFile = await archive.readAsString();
      final backup = (await target.openBackup())!;
      expect(backup.folders.length, 3);
      expect(backup.copies, 5);
      expect(backup.pending, 1);
      expect(target.state.title, 'До восстановления');
      await target.restoreBackup(backup);
      await target.restoreBackup(backup);
      expect(target.state.groups.map((g) => g.name), [
        'На обмен 🃏',
        'Пустая',
        'Моя коллекция',
      ]);
      await target.select(folder);
      expect(target.state.recent.map((s) => s.quantity), [1, 1, 1, 3]);
      expect(target.state.recent.first.card.language, 'und');
      expect(
        target.state.printings.map((s) => (s.card.printingKey, s.quantity)),
        [(ru.printingKey, 2), (en.printingKey, 3)],
      );
      expect(target.state.flags, {ru.printingKey});
      expect(target.state.reviews[pending]?.encode(), review.encode());
      expect(await target.saveBackup(), isTrue);
      expect(
        jsonDecode(await archive.readAsString()),
        jsonDecode(originalFile),
      );

      final bad = jsonDecode(originalFile) as Map<String, dynamic>;
      final scans = bad['scans'] as List;
      scans.last['folder'] = 999;
      await archive.writeAsString(jsonEncode(bad));
      await expectLater(target.openBackup(), throwsFormatException);
      await archive.writeAsString('{');
      await expectLater(target.openBackup(), throwsFormatException);
      final targetDb = await openDatabase(p.join(dir.path, 'target.db'));
      await targetDb.execute(
        "CREATE TRIGGER stop_restore BEFORE INSERT ON scans BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        target.restoreBackup(backup),
        throwsA(isA<DatabaseException>()),
      );
      expect(await target.saveBackup(), isTrue);
      expect(
        jsonDecode(await archive.readAsString()),
        jsonDecode(originalFile),
      );
    },
  );

  test('Повторный идентификатор, неизвестная версия или повреждённая очередь отклоняются', () {
    final row = {
      ...en.row,
      'seq': 1,
      'qty': 1,
      'flagged': 0,
      'folder': 1,
      'review': null,
    };
    final data = {
      'format': 'kartoved',
      'version': 1,
      'folders': [
        {'folder': 1, 'title': 'Альбом'},
      ],
      'scans': [row],
    };
    for (final invalid in [
      {...data, 'version': 2},
      {
        ...data,
        'scans': [row, row],
      },
      {
        ...data,
        'scans': [
          {...row, 'qty': 0},
        ],
      },
      {
        ...data,
        'scans': [
          {
            ...row,
            'review': {'reason': 'batch', 'choices': []},
          },
        ],
      },
      {
        ...data,
        'scans': [
          {...row, 'foil': 'да'},
        ],
      },
    ]) {
      expect(() => LibraryBackup.fromJson(invalid), throwsFormatException);
    }
  });
}
