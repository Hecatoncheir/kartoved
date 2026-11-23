import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
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
