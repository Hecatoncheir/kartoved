import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show compute;

import 'backup.dart';
import 'catalog.dart' show Edition;
import 'review.dart';

part 'move.dart';

typedef CardGroup = ({int id, String name, int count});
typedef ScanEntry = ({int sequence, Edition card, int quantity});
typedef LibraryAddition = ({int folder, Edition card, int quantity});
typedef CardCount = ({Edition card, int quantity});
typedef Holdings = Map<String, Map<int, int>>;
typedef RemovedPrinting = ({
  int folder,
  Edition card,
  List<({int sequence, int quantity})> scans,
  bool flagged,
});

const _printing =
    'folder=? AND id=? AND lang=? AND foil=? AND set_code=? AND review IS NULL';
List<Object> _printingArgs(int folder, Edition card) => [
  folder,
  card.id,
  card.language,
  card.foil ? 1 : 0,
  card.set,
];

class History {
  late Database _db;
  Future<void> open({String? path}) async {
    _db = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'collection.sqlite'),
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: (db, _) => _create(db),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion == 1) {
          await _create(db);
          await db.execute(
            'INSERT INTO scans(folder,id,name,set_code,number,lang,qty) SELECT 1,id,name,set_code,number,lang,qty FROM cards ORDER BY touched,rowid',
          );
          await db.execute('DROP TABLE cards');
          return;
        }
        if (oldVersion == 2) {
          await db.execute(
            'ALTER TABLE scans ADD COLUMN foil INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE scans ADD COLUMN flagged INTEGER NOT NULL DEFAULT 0',
          );
          await _indexPrintings(db);
        }
        await db.execute('ALTER TABLE scans ADD COLUMN review TEXT');
      },
    );
  }

  static Future<void> _create(Database db) async {
    await db.execute(
      'CREATE TABLE folders(folder INTEGER PRIMARY KEY, title TEXT NOT NULL)',
    );
    await db.insert('folders', {'folder': 1, 'title': 'Моя коллекция'});
    await db.execute(
      'CREATE TABLE scans(seq INTEGER PRIMARY KEY, folder INTEGER NOT NULL REFERENCES folders(folder), id TEXT NOT NULL, name TEXT NOT NULL, set_code TEXT NOT NULL, number TEXT NOT NULL, lang TEXT NOT NULL, foil INTEGER NOT NULL DEFAULT 0, qty INTEGER NOT NULL CHECK(qty>0), flagged INTEGER NOT NULL DEFAULT 0, review TEXT)',
    );
    await db.execute('CREATE INDEX scans_by_folder ON scans(folder,seq)');
    await _indexPrintings(db);
  }

  static Future<void> _indexPrintings(Database db) => db.execute(
    'CREATE INDEX scans_by_printing ON scans(folder,id,lang,foil)',
  );

  Future<void> writeBackup(String path) async {
    final snapshot = await _backupRows();
    await compute(LibraryBackup.write, (
      path: path,
      folders: snapshot.folders,
      scans: snapshot.scans,
    ));
  }

  Future<String> backupJson() async {
    final snapshot = await _backupRows();
    return LibraryBackup.encode(snapshot.folders, snapshot.scans);
  }

  Future<({List<BackupRow> folders, List<BackupRow> scans})> _backupRows() =>
      _db.transaction(
        (db) async => (
          folders: await db.query('folders', orderBy: 'folder'),
          scans: await db.query('scans', orderBy: 'seq'),
        ),
      );

  Future<void> restoreBackup(LibraryBackup backup) =>
      _db.transaction((db) async {
        await db.delete('scans');
        await db.delete('folders');
        final batch = db.batch();
        for (final folder in backup.folders) {
          batch.insert('folders', folder);
        }
        for (final scan in backup.scans) {
          batch.insert('scans', scan);
        }
        await batch.commit(noResult: true);
      });

  Future<int> create(String name) => _createFolder(_db, name);

  String _folderTitle(String name) {
    final title = name.trim();
    if (title.isEmpty) {
      throw const FormatException('Введите название коллекции');
    }
    return title;
  }

  Future<int> _createFolder(DatabaseExecutor db, String name) =>
      db.insert('folders', {'title': _folderTitle(name)});

  Future<void> renameFolder(int folder, String name) async {
    final changed = await _db.update(
      'folders',
      {'title': _folderTitle(name)},
      where: 'folder=?',
      whereArgs: [folder],
    );
    if (changed == 0) throw StateError('Коллекция уже удалена');
  }

  Future<void> deleteFolder(int folder, {int? moveTo}) => _db.transaction((
    db,
  ) async {
    if (moveTo == null) {
      await db.delete('scans', where: 'folder=?', whereArgs: [folder]);
    } else {
      if (moveTo == folder) throw ArgumentError('Выберите другую коллекцию');
      final target = await db.query(
        'folders',
        columns: ['folder'],
        where: 'folder=?',
        whereArgs: [moveTo],
      );
      if (target.isEmpty) {
        throw StateError('Коллекция для переноса уже удалена');
      }
      // Как при переносе одной карты, у совпадающих изданий сохраняем флажок получателя.
      await db.rawUpdate(
        '''
        UPDATE scans SET flagged = COALESCE((
          SELECT target.flagged FROM scans AS target
          WHERE target.folder = ? AND target.id = scans.id AND target.lang = scans.lang
            AND target.foil = scans.foil AND target.set_code = scans.set_code AND target.review IS NULL LIMIT 1
        ), flagged) WHERE folder = ? AND review IS NULL
      ''',
        [moveTo, folder],
      );
      await db.update(
        'scans',
        {'folder': moveTo},
        where: 'folder=?',
        whereArgs: [folder],
      );
    }
    final deleted = await db.delete(
      'folders',
      where: 'folder=?',
      whereArgs: [folder],
    );
    if (deleted == 0) throw StateError('Коллекция уже удалена');
  });

  Future<List<CardGroup>> folders() async {
    final rows = await _db.rawQuery(
      'SELECT f.folder,title,coalesce(sum(qty),0) AS n FROM folders f LEFT JOIN scans s ON s.folder=f.folder AND review IS NULL GROUP BY f.folder ORDER BY f.folder DESC',
    );
    return rows
        .map(
          (r) => (
            id: r['folder'] as int,
            name: r['title'] as String,
            count: r['n'] as int,
          ),
        )
        .toList();
  }

  Future<int> _flag(
    DatabaseExecutor db,
    int folder,
    Edition card, {
    bool fallback = false,
  }) async {
    final rows = await db.query(
      'scans',
      columns: ['flagged'],
      where: _printing,
      whereArgs: _printingArgs(folder, card),
      limit: 1,
    );
    return rows.firstOrNull?['flagged'] as int? ?? (fallback ? 1 : 0);
  }

  Future<Holdings> holdings() async {
    final rows = await _db.rawQuery(
      'SELECT name,folder,SUM(qty) AS total FROM scans WHERE review IS NULL GROUP BY name,folder',
    );
    final result = <String, Map<int, int>>{};
    for (final row in rows) {
      final locations = result.putIfAbsent(row['name'] as String, () => {});
      locations[row['folder'] as int] = row['total'] as int;
    }
    return result;
  }

  Future<int> add(
    Edition card, {
    int folder = 1,
    ScanReview? review,
    int quantity = 1,
  }) => _db.transaction((db) async {
    // Суммы в SQLite и файле резервной копии должны помещаться в 64 бита.
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT SUM(qty) FROM scans'),
        ) ??
        0;
    if (quantity < 1 || quantity > maxCardQuantity - total) {
      throw RangeError('Проверьте количество экземпляров');
    }
    return db.insert('scans', {
      ...card.row,
      'folder': folder,
      'qty': quantity,
      'flagged': review == null ? await _flag(db, folder, card) : 0,
      'review': review?.encode(),
    });
  });

  Future<void> confirm(int folder, int seq, Edition card) => _db.transaction((
    db,
  ) async {
    await db.update(
      'scans',
      {...card.row, 'review': null, 'flagged': await _flag(db, folder, card)},
      where: 'folder=? AND seq=? AND review IS NOT NULL',
      whereArgs: [folder, seq],
    );
  });

  Future<void> discard(int folder, int seq, {bool pendingOnly = false}) async {
    final condition = pendingOnly ? ' AND review IS NOT NULL' : '';
    await _db.delete(
      'scans',
      where: 'folder=? AND seq=? AND qty=1$condition',
      whereArgs: [folder, seq],
    );
  }

  Future<void> replace(
    int folder,
    int seq,
    Edition card, {
    ScanReview? review,
  }) => _db.transaction((db) async {
    final changed = await db.update(
      'scans',
      {
        ...card.row,
        'review': review?.encode(),
        'flagged': review == null ? await _flag(db, folder, card) : 0,
      },
      where: 'folder=? AND seq=?',
      whereArgs: [folder, seq],
    );
    if (changed != 1) throw StateError('Карта уже удалена');
  });

  Future<void> takeOne(int folder, Edition card) => _db.transaction((db) async {
    final rows = await db.query(
      'scans',
      columns: ['seq', 'qty'],
      where: _printing,
      whereArgs: _printingArgs(folder, card),
      orderBy: 'seq DESC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    final id = [rows.single['seq']];
    final quantity = rows.single['qty'] as int;
    if (quantity == 1) {
      await db.delete('scans', where: 'seq=?', whereArgs: id);
    } else {
      await db.update(
        'scans',
        {'qty': quantity - 1},
        where: 'seq=?',
        whereArgs: id,
      );
    }
  });

  Future<Set<String>> flags(int folder) async {
    final rows = await _db.query(
      'scans',
      distinct: true,
      columns: ['id', 'lang', 'foil', 'set_code', 'number'],
      where: 'folder=? AND flagged=1 AND review IS NULL',
      whereArgs: [folder],
    );
    return {
      for (final r in rows)
        Edition.keyOf(
          r['id'] as String,
          r['lang'] as String,
          r['foil'] == 1,
          needsPrinting: r['set_code'] == '' && r['number'] == '',
        ),
    };
  }

  Future<void> setFlag(int folder, Edition card, bool value) async {
    await _db.update(
      'scans',
      {'flagged': value ? 1 : 0},
      where: _printing,
      whereArgs: _printingArgs(folder, card),
    );
  }

  Future<RemovedPrinting> remove(int folder, Edition card) =>
      _db.transaction((db) async {
        final args = _printingArgs(folder, card);
        final rows = await db.query(
          'scans',
          columns: ['seq', 'qty', 'flagged'],
          where: _printing,
          whereArgs: args,
          orderBy: 'seq DESC',
        );
        await db.delete('scans', where: _printing, whereArgs: args);
        return (
          folder: folder,
          card: card,
          flagged: rows.firstOrNull?['flagged'] == 1,
          scans: [
            for (final row in rows)
              (sequence: row['seq'] as int, quantity: row['qty'] as int),
          ],
        );
      });

  Future<void> restore(RemovedPrinting removed) => _db.transaction((db) async {
    final card = removed.card;
    final flagged = await _flag(
      db,
      removed.folder,
      card,
      fallback: removed.flagged,
    );
    final batch = db.batch();
    for (final scan in removed.scans) {
      // Если номер уже занял новый скан, SQLite выдаст свободный номер.
      batch.rawInsert(
        '''INSERT INTO scans(seq,folder,id,name,set_code,number,lang,foil,qty,flagged)
          VALUES ((SELECT ? WHERE NOT EXISTS(SELECT 1 FROM scans WHERE seq=?)),?,?,?,?,?,?,?,?,?)''',
        [
          scan.sequence,
          scan.sequence,
          removed.folder,
          card.id,
          card.name,
          card.set,
          card.number,
          card.language,
          card.foil ? 1 : 0,
          scan.quantity,
          flagged,
        ],
      );
    }
    await batch.commit(noResult: true);
  });

  Future<({List<ScanEntry> recent, Map<int, ScanReview> reviews})> timeline(
    int folder,
  ) async {
    final rows = await _db.query(
      'scans',
      where: 'folder=?',
      whereArgs: [folder],
      orderBy: 'seq DESC',
    );
    return (
      recent: [
        for (final r in rows)
          (
            sequence: r['seq'] as int,
            card: Edition.fromRow(r),
            quantity: r['qty'] as int,
          ),
      ],
      reviews: {
        for (final r in rows)
          if (r['review'] case final String text)
            r['seq'] as int: ScanReview.decode(text),
      },
    );
  }

  Future<List<ScanEntry>> recent(int folder) async =>
      (await timeline(folder)).recent;

  Future<List<LibraryAddition>> latestAdditions() async {
    final rows = await _db.query(
      'scans',
      where: 'review IS NULL',
      orderBy: 'seq DESC',
      limit: 3,
    );
    return [
      for (final row in rows)
        (
          folder: row['folder'] as int,
          card: Edition.fromRow(row),
          quantity: row['qty'] as int,
        ),
    ];
  }

  Future<List<CardCount>> list({
    int folder = 1,
    bool flaggedOnly = false,
  }) async {
    final flagFilter = flaggedOnly ? 'AND flagged=1' : '';
    final rows = await _db.rawQuery(
      'SELECT id,name,set_code,number,lang,foil,sum(qty) AS total FROM scans WHERE folder=? AND review IS NULL $flagFilter GROUP BY id,lang,foil,set_code ORDER BY max(seq) DESC',
      [folder],
    );
    return rows
        .map((r) => (card: Edition.fromRow(r), quantity: r['total'] as int))
        .toList();
  }
}
