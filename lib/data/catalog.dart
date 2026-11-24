import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

export 'collections.dart';

const _files = [
  'detector.onnx',
  'embed.onnx',
  'search.onnx',
  'cards.sqlite.pack',
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
  bool get printingMetadata => raw['printingMetadata'] == true;
  bool supersedes(CatalogSpec other) =>
      created.isAfter(other.created) ||
      (created.isAtSameMomentAs(other.created) &&
          printingMetadata &&
          !other.printingMetadata);
  int get count => raw['count'] as int;
  DateTime get created => DateTime.parse(raw['created'] as String);
  String hash(String name) => raw['files'][name]['sha256'] as String;
  int size(String name) => raw['files'][name]['bytes'] as int;
  static CatalogSpec parse(String text) =>
      CatalogSpec(jsonDecode(text) as Map<String, dynamic>);
}

class Catalog {
  const Catalog(Directory directory, this.spec)
    : _directory = directory,
      _database = null;
  const Catalog.opened(Database database, this.spec)
    : _database = database,
      _directory = null;

  final Directory? _directory;
  final Database? _database;
  Directory get directory => _directory!;
  final CatalogSpec spec;
  Future<List<Map<String, Object?>>> _query(
    String sql,
    List<Object?> args,
  ) async {
    if (_database case final db?) return db.rawQuery(sql, args);
    final db = await openReadOnlyDatabase(
      p.join(directory.path, 'cards.sqlite'),
      singleInstance: false,
    );
    try {
      return await db.rawQuery(sql, args);
    } finally {
      await db.close();
    }
  }

  Future<List<String>> searchNames(String input, {int limit = 61}) async {
    final term = input.trim().toLowerCase().replaceAll('’', "'");
    if (term.isEmpty) return [];
    final names = spec.printingMetadata
        ? 'search_names'
        : '(SELECT DISTINCT name, lower(name) AS term FROM editions)';
    final rows = await _query(
      '''
      SELECT name FROM $names WHERE instr(term, ?) > 0 GROUP BY name
      ORDER BY MIN(CASE WHEN term=? THEN 0 WHEN instr(term,?)=1 THEN 1 ELSE 2 END), name COLLATE NOCASE
      LIMIT ?''',
      [term, term, term, limit],
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<Edition>> byName(String name) async {
    final rows = await _query(
      'SELECT * FROM editions WHERE name=? GROUP BY id ORDER BY lang != ?, lang != ?, set_code, number',
      [name, 'ru', 'en'],
    );
    return rows.map(Edition.fromRow).toList();
  }

  Future<Edition> front(Edition card) async {
    if (!card.id.endsWith('-1')) return card;
    final id = card.id.substring(0, card.id.length - 2);
    final rows = await _query('SELECT * FROM editions WHERE id=? LIMIT 1', [
      id,
    ]);
    return rows.isEmpty ? card : Edition.fromRow(rows.first);
  }

  Future<List<Edition>> variants(Edition card) => editionsForPrinting(card.id);

  Future<List<Edition>> editionsForPrinting(String id) async {
    final rows = await _query(
      'SELECT * FROM editions WHERE art = (SELECT art FROM editions WHERE id = ? LIMIT 1) ORDER BY rowid',
      [id],
    );
    return rows.map(Edition.fromRow).toList();
  }

  Future<List<Edition>> inSet(String code, String language) async {
    final rows = await _query(
      'SELECT * FROM editions WHERE set_code=? AND lang=?',
      [code, language],
    );
    return rows.map(Edition.fromRow).toList();
  }

  Future<List<String>> setCodes() async {
    final rows = await _query(
      'SELECT DISTINCT set_code FROM editions ORDER BY set_code',
      [],
    );
    return [for (final row in rows) row['set_code'] as String];
  }

  Future<List<String>> languages() async {
    final rows = await _query(
      "SELECT DISTINCT lang FROM editions WHERE lang != 'und' ORDER BY lang",
      [],
    );
    return [for (final row in rows) row['lang'] as String];
  }

  Future<List<Edition>> editions(int index) async {
    final rows = await _query(
      'SELECT * FROM editions WHERE art=? ORDER BY rowid',
      [index],
    );
    return rows.map(Edition.fromRow).toList();
  }
}

class Edition {
  const Edition(
    this.id,
    this.name,
    this.set,
    this.number,
    this.language, {
    this.foil = false,
  });
  final String id, name, set, number, language;
  final bool foil;
  Edition withLanguage(String lang) =>
      Edition(id, name, set, number, lang, foil: foil);
  Edition withFoil(bool value) =>
      Edition(id, name, set, number, language, foil: value);
  static String keyOf(String id, String language, bool foil) =>
      '$id/$language/$foil';
  String get printingKey => keyOf(id, language, foil);
  Uri get scryfallPage => Uri(
    scheme: 'https',
    host: 'scryfall.com',
    pathSegments: [
      'card',
      set.toLowerCase(),
      number,
      if (language != 'en' && language != 'und') language,
    ],
  );
  String get detail =>
      '${set.toUpperCase()}  ·  № $number  ·  ${language == 'und' ? 'язык не определён' : language.toUpperCase()}';
  factory Edition.fromRow(Map<String, Object?> row) => Edition(
    row['id'] as String,
    row['name'] as String,
    row['set_code'] as String,
    row['number'] as String,
    row['lang'] as String,
    foil: row['foil'] == 1,
  );
  Map<String, Object?> get row => {
    'id': id,
    'name': name,
    'set_code': set,
    'number': number,
    'lang': language,
    'foil': foil ? 1 : 0,
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
          if (!seed.supersedes(spec)) {
            return Catalog(folder, spec);
          }
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
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
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
      if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
        throw const FormatException('Некорректная версия');
      }
      final base = Uri.https(
        'raw.githubusercontent.com',
        '/$_repo/$sha/assets/oracle/',
      );
      final spec = CatalogSpec.parse(await read(base.resolve('catalog.json')));
      return await installUpdate(
        current,
        spec,
        (name) async =>
            (await request(base.resolve(name)))
                .timeout(const Duration(seconds: 45)),
      );
    } finally {
      http.close(force: true);
    }
  }

  Future<Catalog> installUpdate(
    Catalog current,
    CatalogSpec spec,
    Future<Stream<List<int>>> Function(String name) source,
  ) async {
    if (!spec.supersedes(current.spec)) return current;
    return _install(spec, current, source);
  }

  Future<void> _stageFile(
    Directory staging,
    String name,
    CatalogSpec spec,
    Catalog? previous,
    _FileSource source,
  ) async {
    final file = File(p.join(staging.path, name));
    if (previous != null &&
        name != 'cards.sqlite.pack' &&
        previous.spec.hash(name) == spec.hash(name)) {
      await File(p.join(previous.directory.path, name)).copy(file.path);
    } else {
      var bytes = 0;
      await (await source(name))
          .map((chunk) {
            bytes += chunk.length;
            if (bytes > spec.size(name)) {
              throw const FormatException('Превышен размер файла');
            }
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

  Future<void> _unpack(Directory staging, CatalogSpec spec) async {
    final packed = File(p.join(staging.path, 'cards.sqlite.pack'));
    final database = File(p.join(staging.path, 'cards.sqlite'));
    await packed.openRead().transform(gzip.decoder).pipe(database.openWrite());
    await packed.delete();
    final db = await openReadOnlyDatabase(database.path, singleInstance: false);
    try {
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT count(*) FROM arts'),
      );
      if (count != spec.count) {
        throw const FormatException('Неполный каталог');
      }
    } finally {
      await db.close();
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
        await _stageFile(staging, name, spec, previous, source);
      }
      await _unpack(staging, spec);
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
