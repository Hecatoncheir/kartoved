import 'dart:typed_data';

import 'catalog.dart';
import 'tray.dart';

CatalogStore createCatalogStore() => CatalogStore();
void unlockBrowserSound() {}
void releaseBrowserPhoto(String file) {}
void reloadBrowser() {}
String? browserInterfaceLanguage(String? code) => _unsupported();
void browserPageLanguage(String code) => _unsupported();
Future<bool> browserOfflineScanner({required bool prepare}) => _unsupported();
void openBrowserScryfall(String url) => _unsupported();

Future<bool> browserGuide(bool? visible) => _unsupported();
String browserScannerModel(String? model) => _unsupported();
bool browserTrayPreference(bool? value) => _unsupported();
Future<void> browserChime(String sound) => _unsupported();
Future<Uint8List> browserCrop(String file, List<double> corners) =>
    _unsupported();
Future<String> browserUnmirror(String file) => _unsupported();
Future<String> browserReadText(String file, List<double> corners) =>
    _unsupported();
Future<TrayPhoto> browserTrayPhoto(
  String file,
  TrayArea area,
  bool readFooter,
) => _unsupported();
Future<String> browserReadTrayText(Uint8List bytes) => _unsupported();
Future<void> browserWarmTray(String engine, bool essentials) => _unsupported();
Future<String> browserEnglishTitle(Uint8List bytes) => _unsupported();
Future<Uint8List?> browserTraySample(
  String file,
  TrayArea area, {
  bool details = false,
}) => _unsupported();
bool browserScannerOption(String name, bool? value) => _unsupported();
Future<Uint8List?> browserCacheRead(String key) => _unsupported();
Future<void> browserCacheWrite(String key, Uint8List bytes) => _unsupported();
void browserDownload(String name, String mime, Uint8List bytes) =>
    _unsupported();
Future<String?> browserPickBackup() => _unsupported();

Never _unsupported() => throw UnsupportedError('Функция доступна в браузере');
