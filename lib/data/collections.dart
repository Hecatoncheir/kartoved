import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'catalog.dart' show Edition;

typedef CardGroup = ({int id, String name, int count});
typedef ScanEntry = ({int sequence, Edition card, int quantity});
typedef CardCount = ({Edition card, int quantity});

class History {
  late Database _db;
  Future<void> open({String? path}) async {
    _db = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'collection.sqlite'),
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: (db, _) => _create(db),
      onUpgrade: (db, oldVersion, _) async {
        await _create(db);
        await db.execute(
          'INSERT INTO scans(folder,id,name,set_code,number,lang,qty) SELECT 1,id,name,set_code,number,lang,qty FROM cards ORDER BY touched,rowid',
        );
        await db.execute('DROP TABLE cards');
      },
    );
  }

  static Future<void> _create(Database db) async {
    await db.execute(
      'CREATE TABLE folders(folder INTEGER PRIMARY KEY, title TEXT NOT NULL)',
    );
    await db.insert('folders', {'folder': 1, 'title': 'Моя коллекция'});
    await db.execute(
      'CREATE TABLE scans(seq INTEGER PRIMARY KEY, folder INTEGER NOT NULL REFERENCES folders(folder), id TEXT NOT NULL, name TEXT NOT NULL, set_code TEXT NOT NULL, number TEXT NOT NULL, lang TEXT NOT NULL, qty INTEGER NOT NULL CHECK(qty>0))',
    );
    await db.execute('CREATE INDEX scans_by_folder ON scans(folder,seq)');
  }

  Future<int> create(String name) {
    final title = name.trim();
    if (title.isEmpty) {
      throw const FormatException('Введите название коллекции');
    }
    return _db.insert('folders', {'title': title});
  }

  Future<List<CardGroup>> folders() async {
    final rows = await _db.rawQuery(
      'SELECT f.folder,title,coalesce(sum(qty),0) AS n FROM folders f LEFT JOIN scans s ON s.folder=f.folder GROUP BY f.folder ORDER BY f.folder DESC',
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

  Future<int> add(Edition card, {int folder = 1}) =>
      _db.insert('scans', {...card.row, 'folder': folder, 'qty': 1});

  Future<void> replace(int folder, int seq, Edition card) async {
    await _db.update(
      'scans',
      card.row,
      where: 'folder=? AND seq=?',
      whereArgs: [folder, seq],
    );
  }

  Future<List<ScanEntry>> recent(int folder) async {
    final rows = await _db.query(
      'scans',
      where: 'folder=?',
      whereArgs: [folder],
      orderBy: 'seq DESC',
    );
    return rows
        .map(
          (r) => (
            sequence: r['seq'] as int,
            card: Edition.fromRow(r),
            quantity: r['qty'] as int,
          ),
        )
        .toList();
  }

  Future<List<CardCount>> list({int folder = 1}) async {
    final rows = await _db.rawQuery(
      'SELECT id,name,set_code,number,lang,sum(qty) AS total FROM scans WHERE folder=? GROUP BY id,lang ORDER BY max(seq) DESC',
      [folder],
    );
    return rows
        .map((r) => (card: Edition.fromRow(r), quantity: r['total'] as int))
        .toList();
  }
}
