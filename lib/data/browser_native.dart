import 'dart:typed_data';

import 'catalog.dart';

CatalogStore createCatalogStore() => CatalogStore();
void unlockBrowserSound() {}
void releaseBrowserPhoto(String file) {}
void reloadBrowser() {}

Future<bool> browserGuide(bool? visible) => _unsupported();
Future<void> browserChime(bool targetFound) => _unsupported();
Future<Uint8List> browserCrop(String file, List<double> corners) =>
    _unsupported();
Future<String> browserUnmirror(String file) => _unsupported();
Future<String> browserReadText(String file, List<double> corners) =>
    _unsupported();
Future<Uint8List?> browserCacheRead(String key) => _unsupported();
Future<void> browserCacheWrite(String key, Uint8List bytes) => _unsupported();
void browserDownload(String name, String mime, Uint8List bytes) =>
    _unsupported();
Future<String?> browserPickBackup() => _unsupported();

Never _unsupported() => throw UnsupportedError('Функция доступна в браузере');
