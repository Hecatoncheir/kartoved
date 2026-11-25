import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/data/review.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory folder;
  late Catalog catalog;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('kartoved-printings-');
    final asset = Directory('assets/oracle');
    final manifest = await File(p.join(asset.path, 'catalog.json'))
        .readAsString();
    catalog = Catalog(folder, CatalogSpec.parse(manifest));
    await File(p.join(asset.path, 'cards.sqlite.pack'))
        .openRead()
        .transform(gzip.decoder)
        .pipe(File(p.join(folder.path, 'cards.sqlite')).openWrite());
  });
  tearDownAll(() => folder.delete(recursive: true));

  test('Название с камеры сопоставляется с каталогом целиком', () async {
    expect(
      await catalog.nameForScannedTitle('ЖрицаЗабытых Богов1'),
      'Priest of Forgotten Gods',
    );
    expect(
      await catalog.nameForScannedTitle('Marauding Blight-Priest 2'),
      'Marauding Blight-Priest',
    );
    expect(await catalog.nameForScannedTitle('Fatal'), isNull);
    expect(await catalog.nameForScannedTitle('Marauding Bight-Priest'), isNull);
    expect(
      await catalog.nameForScannedTitle(
        'Marauding Bight-Priest',
        allowOneEdit: true,
      ),
      'Marauding Blight-Priest',
    );
    expect(
      await catalog.nameForScannedTitle(
        'Дявольский Наставник 2',
        allowOneEdit: true,
      ),
      'Diabolic Tutor',
    );
    expect(await catalog.nameForScannedTitle(''), isNull);
  });

  test('Очередь переживает обновление и перезапуск, подтверждение и отмена меняют ровно один экземпляр', () async {
    const en = Edition('en', 'Opt', 'eld', '59', 'en');
    const ru = Edition('ru', 'Opt', 'dom', '60', 'ru');
    const review = ScanReview(ReviewReason.language, [en, ru]);
    final path = p.join(folder.path, 'review.sqlite');
    final previous = await openDatabase(
      path,
      version: 4,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE folders(folder INTEGER PRIMARY KEY, title TEXT NOT NULL)',
        );
        await db.execute("INSERT INTO folders VALUES(1,'Коллекция')");
        await db.execute(
          'CREATE TABLE scans(seq INTEGER PRIMARY KEY,folder INTEGER,id TEXT,name TEXT,set_code TEXT,number TEXT,lang TEXT,foil INTEGER,qty INTEGER,flagged INTEGER)',
        );
        await db.insert('scans', {
          ...en.row,
          'folder': 1,
          'qty': 2,
          'flagged': 1,
        });
      },
    );
    await previous.close();
    final old = History();
    await old.open(path: path);
    final pending = await old.add(en, review: review);
    final other = await old.create('Другая');
    await old.add(ru, folder: other, review: review);
    await (await openDatabase(path)).close();
    final history = History();
    await history.open(path: path);
    addTearDown(() async => (await openDatabase(path)).close());
    final model = AppModel(
      CatalogStore(),
      history,
      initial: LibraryState(catalog: catalog),
    );
    addTearDown(model.close);
    await model.select(1);
    expect(model.state.reviews.keys, [pending]);
    expect(
      model.state.reviews[pending]!.choices.last.printingKey,
      ru.printingKey,
    );
    expect(model.state.printings.single.quantity, 2);
    expect(model.state.groups.first.count, 0);
    expect(await model.export(), isNot(contains('Russian')));
    final saved = await model.save(en);
    await model.discardScan(saved);
    expect(model.state.printings.single.quantity, 2);
    expect(model.state.flags, contains(en.printingKey));
    expect(model.state.reviews, contains(pending));
    await Future.wait([
      model.confirmReview(pending, ru),
      model.confirmReview(pending, ru),
    ]);
    expect(model.state.reviews, isEmpty);
    expect(
      await model.export(),
      contains('"1","Opt","DOM","","Russian","","60"'),
    );
    final later = await model.save(en, review: review);
    await model.discardScan(later, pendingOnly: true);
    await model.discardScan(pending, pendingOnly: true);
    expect(model.state.printings.length, 2);
    await model.select(other);
    expect(model.state.reviews.length, 1);
    expect(model.state.printings, isEmpty);
  });

  test(
    'Названия и покрытия читаются из базы, которую получает телефон',
    () async {
      expect(
        (await catalog.searchNames(' СОЛНЕЧНОЕ КОЛЬЦО ')).first,
        'Sol Ring',
      );
      expect((await catalog.searchNames('sol ring')).first, 'Sol Ring');
      expect(await catalog.searchNames('ВЫБОР', limit: -1), contains('Opt'));
      expect((await catalog.searchNames('a')).length, 61);
      expect(
        (await catalog.searchNames('a', limit: -1)).length,
        greaterThan(61),
      );
      expect(await catalog.searchNames('%'), isNot(contains('Sol Ring')));
      expect(await catalog.setCodes(), contains('snc'));
      expect(await catalog.languages(), containsAll(['en', 'ru']));
      final rings = await catalog.byName('Sol Ring');
      expect(
        rings.firstWhere((e) => e.set == 'mps' && e.number == '24').foil,
        isTrue,
      );
      expect(rings.any((e) => !e.foil), isTrue);
    },
  );

  test('Коллекция версии 2 сохраняет обычные и фольгированные экземпляры раздельно', () async {
    final path = p.join(folder.path, 'collection.sqlite');
    final previous = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE scans(seq INTEGER PRIMARY KEY, folder INTEGER, id TEXT, name TEXT, set_code TEXT, number TEXT, lang TEXT, qty INTEGER)',
        );
        await db.execute(
          "INSERT INTO scans VALUES (1,1,'sample','Opt','eld','59','en',3)",
        );
      },
    );
    await previous.close();
    final history = History();
    await history.open(path: path);
    addTearDown(() async => (await openDatabase(path)).close());
    final normal = (await history.list()).single;
    await history.add(normal.card.withFoil(true));
    final model = AppModel(
      CatalogStore(),
      history,
      initial: LibraryState(catalog: catalog),
    );
    addTearDown(model.close);
    final csv = await model.export();
    expect(csv, contains('"3","Opt","ELD","","English","","59"'));
    expect(csv, contains('"1","Opt","ELD","","English","foil","59"'));
    expect((await history.recent(1)).first.card.foil, isTrue);
  });
}
