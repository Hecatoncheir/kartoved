import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'frame.dart';
import 'browser.dart';
import 'recognition_result.dart';

class AndroidActions {
  static const _channel = MethodChannel('kartoved/android');
  static Future<void> chime({bool targetFound = false}) async {
    if (kIsWeb) return browserChime(targetFound);
    try {
      await _channel.invokeMethod<void>('chime', targetFound);
    } on PlatformException {
      /* Звук может быть отключён. */
    } on MissingPluginException {
      /* Звуковой канал доступен на Android. */
    }
  }

  static Future<bool> openScryfall(Uri page) async {
    if (kIsWeb) {
      openBrowserScryfall(page.toString());
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'openScryfall',
            page.toString(),
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<Uint8List?> scanPhoto({
    String? file,
    PreviewFrame? frame,
    required List<double> corners,
  }) => kIsWeb
      ? browserCrop(file!, corners)
      : _channel.invokeMethod<Uint8List>(
          'scanPhoto',
          scanArguments(file: file, frame: frame, corners: corners),
        );

  static Future<bool?> scannerGuide([bool? visible]) async {
    if (kIsWeb) return browserGuide(visible);
    try {
      return await _channel.invokeMethod<bool>('scannerGuide', visible);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<RecognitionModel> scannerModel([
    RecognitionModel? model,
  ]) async {
    if (kIsWeb) {
      return RecognitionModel.fromName(browserScannerModel(model?.name));
    }
    try {
      final name = await _channel.invokeMethod<String>(
        'scannerModel',
        model?.name,
      );
      return RecognitionModel.fromName(name);
    } on PlatformException {
      return model ?? RecognitionModel.oracle;
    } on MissingPluginException {
      return model ?? RecognitionModel.oracle;
    }
  }

  static Future<bool> saveCsv(String name, String csv) async {
    if (kIsWeb) {
      browserDownload(name, 'text/csv;charset=utf-8', utf8.encode(csv));
      return true;
    }
    return await _channel.invokeMethod<bool>('saveCsv', {
          'name': name,
          'csv': csv,
        }) ??
        false;
  }

  static Future<T> withBackupFile<T>(
    Future<T> Function(String path) action,
  ) async {
    final dir = await Directory.systemTemp.createTemp('kartoved-backup-');
    try {
      return await action(p.join(dir.path, 'collections.json'));
    } finally {
      await dir.delete(recursive: true);
    }
  }

  static Future<bool> saveBackup(String path) async {
    final date = DateTime.now().toIso8601String().split('T').first;
    return await _channel.invokeMethod<bool>('saveBackup', {
          'path': path,
          'name': 'kartoved-$date.json',
        }) ??
        false;
  }

  static Future<bool> openBackup(String path) async =>
      await _channel.invokeMethod<bool>('openBackup', {'path': path}) ?? false;
}
