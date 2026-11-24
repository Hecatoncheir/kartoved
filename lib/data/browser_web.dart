import 'dart:js_interop';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'catalog.dart';

@JS('kartoved.readCache')
external JSPromise<JSUint8Array?> _readCache(String key);
@JS('kartoved.writeCache')
external JSPromise<JSAny?> _writeCache(String key, JSUint8Array data);
@JS('kartoved.unpack')
external JSPromise<JSUint8Array> _unpack(JSUint8Array data);
@JS('kartoved.crop')
external JSPromise<JSUint8Array> _crop(String file, JSArray<JSNumber> corners);
@JS('kartoved.unmirror')
external JSPromise<JSString> _unmirror(String file);
@JS('kartoved.readCardText')
external JSPromise<JSString> _readText(String file, JSArray<JSNumber> corners);
@JS('kartoved.guide')
external bool _guide(JSBoolean? visible);
@JS('kartoved.download')
external void _download(String name, String mime, JSUint8Array data);
@JS('kartoved.pickBackup')
external JSPromise<JSString?> _pickBackup();
@JS('kartoved.unlockSound')
external void unlockBrowserSound();
@JS('kartoved.chime')
external JSPromise<JSAny?> _chime(bool targetFound);
@JS('URL.revokeObjectURL')
external void releaseBrowserPhoto(String file);
@JS('kartoved.reload')
external void reloadBrowser();

CatalogStore createCatalogStore() {
  databaseFactory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(indexedDbName: 'kartoved'),
  );
  return _BrowserCatalogStore();
}

class _BrowserCatalogStore extends CatalogStore {
  @override
  Future<Catalog> initialize() async {
    final spec = CatalogSpec.parse(
      await rootBundle.loadString('assets/oracle/catalog.json'),
    );
    const pack = 'cards.sqlite.pack';
    final suffix = spec.hash(pack).substring(0, 12);
    final path = 'catalog-$suffix.sqlite';
    if (!await databaseFactory.databaseExists(path)) {
      final packed = await rootBundle.load('assets/oracle/$pack');
      final bytes = packed.buffer.asUint8List(
        packed.offsetInBytes,
        packed.lengthInBytes,
      );
      if (sha256.convert(bytes).toString() != spec.hash(pack)) {
        throw const FormatException('Не совпала контрольная сумма каталога');
      }
      final data = (await _unpack(bytes.toJS).toDart).toDart;
      await databaseFactory.writeDatabaseBytes(path, data);
    }
    final db = await openDatabase(path, readOnly: true);
    if (Sqflite.firstIntValue(await db.rawQuery('SELECT count(*) FROM arts')) !=
        spec.count) {
      await db.close();
      throw const FormatException('Неполный каталог');
    }
    return Catalog.opened(db, spec);
  }

  @override
  Future<Catalog> update(Catalog current) async {
    reloadBrowser();
    return current;
  }
}

Future<bool> browserGuide(bool? visible) async => _guide(visible?.toJS);
Future<void> browserChime(bool targetFound) async =>
    await _chime(targetFound).toDart;

Future<Uint8List> browserCrop(String file, List<double> corners) async =>
    (await _crop(file, corners.map((v) => v.toJS).toList().toJS).toDart).toDart;
Future<String> browserUnmirror(String file) async =>
    (await _unmirror(file).toDart).toDart;
Future<String> browserReadText(String file, List<double> corners) async =>
    (await _readText(
      file,
      corners.map((v) => v.toJS).toList().toJS,
    ).toDart).toDart;

Future<Uint8List?> browserCacheRead(String key) async =>
    (await _readCache(key).toDart)?.toDart;
Future<void> browserCacheWrite(String key, Uint8List bytes) async =>
    await _writeCache(key, bytes.toJS).toDart;
void browserDownload(String name, String mime, Uint8List bytes) =>
    _download(name, mime, bytes.toJS);
Future<String?> browserPickBackup() async =>
    (await _pickBackup().toDart)?.toDart;
