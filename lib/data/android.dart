import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class AndroidActions {
  static const _channel = MethodChannel('kartoved/android');
  static Future<void> chime() async {
    try {
      await _channel.invokeMethod<void>('chime');
    } on PlatformException {
      /* Звук может быть отключён. */
    }
  }

  static Future<bool> saveCsv(String name, String csv) async =>
      await _channel.invokeMethod<bool>('saveCsv', {
        'name': name,
        'csv': csv,
      }) ??
      false;

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
