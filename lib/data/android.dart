import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as im;
import 'package:path/path.dart' as p;

import 'frame.dart';
import 'browser.dart';
import 'recognition_result.dart';
import 'tray.dart';

enum ScanSound { added, found, review }

class AndroidActions {
  static const _channel = MethodChannel('kartoved/android');
  static Future<void> chime(ScanSound sound) async {
    if (kIsWeb) return browserChime(sound.name);
    try {
      await _channel.invokeMethod<void>('chime', sound.name);
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
  }) async {
    if (kIsWeb) return browserCrop(file!, corners);
    try {
      final photo = await _channel.invokeMethod<Uint8List>(
        'scanPhoto',
        scanArguments(file: file, frame: frame, corners: corners),
      );
      if (photo != null && photo.isNotEmpty) return photo;
    } on Exception {
      // При сбое канала миниатюру можно получить из исходного кадра.
    }
    try {
      return await compute(_scanThumbnail, (
        file: file,
        frame: frame,
        corners: corners,
      ));
    } on Exception {
      return null;
    }
  }

  static Future<void> warmTray(
    RecognitionModel engine, {
    bool essentials = false,
  }) async {
    if (kIsWeb) return browserWarmTray(engine.name, essentials);
    if (!essentials) await _channel.invokeMethod<void>('warmTray');
  }

  static Future<TrayPhoto?> trayPhoto({
    String? file,
    PreviewFrame? frame,
    required TrayArea area,
    required bool readFooter,
  }) async {
    if (kIsWeb) return browserTrayPhoto(file!, area, readFooter);
    try {
      final photo = await _channel.invokeMapMethod<String, Object?>(
        'trayPhoto',
        {
          ...scanArguments(file: file, frame: frame, corners: const []),
          'tray': area.bounds,
          'readFooter': readFooter,
        },
      );
      final bytes = photo?['bytes'];
      return bytes is Uint8List && bytes.isNotEmpty
          ? (bytes: bytes, footer: photo?['footer'] as String? ?? '')
          : null;
    } on Exception {
      return null;
    }
  }

  static Future<({String text, String? language})> readTrayText(
    Uint8List bytes,
  ) async {
    if (kIsWeb) return (text: await browserReadTrayText(bytes), language: null);
    final result = await _channel.invokeMapMethod<String, String>(
      'readTrayText',
      bytes,
    );
    return (text: result?['text'] ?? '', language: result?['language']);
  }

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

  static Future<bool> scannerTray([bool? value]) async {
    if (kIsWeb) return browserTrayPreference(value);
    try {
      return await _channel.invokeMethod<bool>('scannerTray', value) ?? true;
    } on PlatformException {
      return value ?? true;
    } on MissingPluginException {
      return value ?? true;
    }
  }

  static Future<bool> scannerOption(String name, [bool? value]) async {
    if (kIsWeb) return browserScannerOption(name, value);
    try {
      return await _channel.invokeMethod<bool>('scannerOption', {
            'name': name,
            'value': value,
          }) ??
          false;
    } on PlatformException {
      return value ?? false;
    } on MissingPluginException {
      return value ?? false;
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

Uint8List? _scanThumbnail(
  ({String? file, PreviewFrame? frame, List<double> corners}) input,
) {
  final captured = input.frame;
  final file = input.file;
  final source = captured != null
      ? frameImage(captured, maxSide: 960)
      : file == null
      ? null
      : im.decodeImage(File(file).readAsBytesSync());
  if (source == null) return null;
  final image = captured == null ? im.bakeOrientation(source) : source;
  final points = input.corners;
  if (points.length == 8 && points.every((value) => value.isFinite)) {
    final corners = [
      for (var i = 0; i < points.length; i += 2)
        im.Point(points[i].clamp(0, 1), points[i + 1].clamp(0, 1)),
    ];
    final area =
        (corners[2].x - corners[0].x) * (corners[3].y - corners[1].y) -
        (corners[2].y - corners[0].y) * (corners[3].x - corners[1].x);
    if (area.abs() > .002) {
      im.Point at(int i) => im.Point(
        corners[i].x * (image.width - 1),
        corners[i].y * (image.height - 1),
      );
      final card = im.copyRectify(
        image,
        topLeft: at(0),
        topRight: at(1),
        bottomRight: at(2),
        bottomLeft: at(3),
        toImage: im.Image(width: 420, height: 587, numChannels: 3),
        interpolation: im.Interpolation.linear,
      );
      return im.encodeJpg(card, quality: 86);
    }
  }
  final thumbnail = image.width > 840 || image.height > 840
      ? im.copyResize(
          image,
          width: image.width >= image.height ? 840 : null,
          height: image.height > image.width ? 840 : null,
        )
      : image;
  return im.encodeJpg(thumbnail, quality: 86);
}
