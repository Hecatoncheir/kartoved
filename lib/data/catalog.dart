import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const _files = [
  'detector.onnx',
  'embed.onnx',
  'search.onnx',
  'cards.sqlite.gz',
];
const _repo = 'Hecatoncheir/kartoved';

class CatalogSpec {
  CatalogSpec(this.raw) {
    if (raw['schema'] != 1 ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,90}$').hasMatch(version) ||
        count <= 0) {
      throw const FormatException('Неподдерживаемая версия каталога');
    }
    for (final name in _files) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash(name)) ||
          size(name) <= 0 ||
          size(name) > 128 * 1024 * 1024) {
        throw const FormatException('Некорректное описание файла');
      }
    }
  }
  final Map<String, dynamic> raw;
  String get version => raw['version'] as String;
  int get count => raw['count'] as int;
  DateTime get created => DateTime.parse(raw['created'] as String);
  String hash(String name) => raw['files'][name]['sha256'] as String;
  int size(String name) => raw['files'][name]['bytes'] as int;
  static CatalogSpec parse(String text) =>
      CatalogSpec(jsonDecode(text) as Map<String, dynamic>);
}

class Catalog {
  const Catalog(this.directory, this.spec);
  final Directory directory;
  final CatalogSpec spec;
  Future<List<Edition>> editions(int index) async {
    final db = await openReadOnlyDatabase(
      p.join(directory.path, 'cards.sqlite'),
      singleInstance: false,
    );
    try {
      final rows = await db.query(
        'editions',
        where: 'art = ?',
        whereArgs: [index],
        orderBy: 'rowid',
      );
      return rows.map(Edition.fromRow).toList();
    } finally {
      await db.close();
    }
  }
}

class Edition {
  const Edition(this.id, this.name, this.set, this.number, this.language);
  final String id, name, set, number, language;
  String get detail =>
      '${set.toUpperCase()}  ·  № $number  ·  ${language.toUpperCase()}';
  factory Edition.fromRow(Map<String, Object?> row) => Edition(
    row['id'] as String,
    row['name'] as String,
    row['set_code'] as String,
    row['number'] as String,
    row['lang'] as String,
  );
  Map<String, Object?> get row => {
    'id': id,
    'name': name,
    'set_code': set,
    'number': number,
    'lang': language,
  };
}

typedef _FileSource = Future<Stream<List<int>>> Function(String name);

class CatalogStore {
  late Directory root;
  Future<Catalog> initialize() async {
    root = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'catalogs'),
    );
    await root.create(recursive: true);
    final seed = CatalogSpec.parse(
      await rootBundle.loadString('assets/oracle/catalog.json'),
    );
    final pointer = File(p.join(root.path, 'active'));
    if (await pointer.exists()) {
      final version = (await pointer.readAsString()).trim();
      if (RegExp(r'^[a-zA-Z0-9_-]{1,90}$').hasMatch(version)) {
        final folder = Directory(p.join(root.path, version));
        final saved = File(p.join(folder.path, 'catalog.json'));
        if (await saved.exists()) {
          final spec = CatalogSpec.parse(await saved.readAsString());
          if (!spec.created.isBefore(seed.created))
            return Catalog(folder, spec);
        }
      }
    }
    return _install(seed, null, (name) async {
      final data = await rootBundle.load('assets/oracle/$name');
      return Stream.value(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    });
  }

  Future<Catalog> update(Catalog current) async {
    final http = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'Kartoved-Android';
    Future<HttpClientResponse> request(Uri url) async {
      final req = await http.getUrl(url).timeout(const Duration(seconds: 20));
      final response = await req.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200)
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      return response;
    }

    Future<String> read(Uri url) async => utf8.decoder
        .bind((await request(url)).timeout(const Duration(seconds: 30)))
        .join();
    try {
      final commits = jsonDecode(
        await read(
          Uri.https('api.github.com', '/repos/$_repo/commits', {
            'sha': 'main',
            'path': 'assets/oracle/catalog.json',
            'per_page': '1',
          }),
        ),
      ) as List;
      final sha = commits.first['sha'] as String;
      if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha))
        throw const FormatException('Некорректная версия');
      final base = Uri.https(
        'raw.githubusercontent.com',
        '/$_repo/$sha/assets/oracle/',
      );
      final spec = CatalogSpec.parse(await read(base.resolve('catalog.json')));
      if (!spec.created.isAfter(current.spec.created)) return current;
      return await _install(
        spec,
        current,
        (name) async =>
            (await request(base.resolve(name)))
                .timeout(const Duration(seconds: 45)),
      );
    } finally {
      http.close(force: true);
    }
  }

  Future<Catalog> _install(
    CatalogSpec spec,
    Catalog? previous,
    _FileSource source,
  ) async {
    final target = Directory(p.join(root.path, spec.version));
    final staging = await root.createTemp('install-');
    try {
      for (final name in _files) {
        final file = File(p.join(staging.path, name));
        if (previous != null &&
            name != 'cards.sqlite.gz' &&
            previous.spec.hash(name) == spec.hash(name)) {
          await File(p.join(previous.directory.path, name)).copy(file.path);
        } else {
          var bytes = 0;
          await (await source(name))
              .map((chunk) {
                bytes += chunk.length;
                if (bytes > spec.size(name))
                  throw const FormatException('Превышен размер файла');
                return chunk;
              })
              .pipe(file.openWrite());
        }
        if (await file.length() != spec.size(name) ||
            (await sha256.bind(file.openRead()).first).toString() !=
                spec.hash(name)) {
          throw const FormatException('Не совпала контрольная сумма');
        }
      }
      final packed = File(p.join(staging.path, 'cards.sqlite.gz'));
      final database = File(p.join(staging.path, 'cards.sqlite'));
      await packed
          .openRead()
          .transform(gzip.decoder)
          .pipe(database.openWrite());
      await packed.delete();
      final db = await openReadOnlyDatabase(
        database.path,
        singleInstance: false,
      );
      try {
        final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT count(*) FROM arts'),
        );
        if (count != spec.count)
          throw const FormatException('Неполный каталог');
      } finally {
        await db.close();
      }
      await File(p.join(staging.path, 'catalog.json'))
          .writeAsString(jsonEncode(spec.raw), flush: true);
      // Готовый каталог мог остаться после прерывания между переименованием и сменой указателя.
      if (!await target.exists()) await staging.rename(target.path);
      final pointer = File(p.join(root.path, 'active.next'));
      await pointer.writeAsString(spec.version, flush: true);
      await pointer.rename(p.join(root.path, 'active'));
      if (previous != null && previous.directory.path != target.path) {
        try {
          await previous.directory.delete(recursive: true);
        } on FileSystemException {
          /* Повторная очистка возможна позже. */
        }
      }
      return Catalog(target, spec);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}

class History {
  late Database _db;
  Future<void> open() async {
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'collection.sqlite'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE cards(id TEXT PRIMARY KEY,name TEXT,set_code TEXT,number TEXT,lang TEXT,qty INTEGER,touched INTEGER)',
      ),
    );
  }

  Future<void> add(Edition card) async {
    await _db.transaction((tx) async {
      await tx.insert('cards', {
        ...card.row,
        'qty': 0,
        'touched': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.rawUpdate('UPDATE cards SET qty=qty+1,touched=? WHERE id=?', [
        DateTime.now().microsecondsSinceEpoch,
        card.id,
      ]);
    });
  }

  Future<List<({Edition card, int quantity})>> list() async =>
      (await _db.query('cards', orderBy: 'touched DESC'))
          .map(
            (row) => (card: Edition.fromRow(row), quantity: row['qty'] as int),
          )
          .toList();
}
