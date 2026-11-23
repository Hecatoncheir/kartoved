import 'package:flutter/services.dart';

import 'catalog.dart';
import 'frame.dart';

class CardLanguage {
  static const _channel = MethodChannel('kartoved/android');
  static Future<String?> read({
    String? file,
    PreviewFrame? frame,
    required List<Edition> options,
  }) async {
    final languages = options.map((e) => e.language).toSet();
    if (languages.length == 1) return languages.single;
    final args = frame == null
        ? {'file': file}
        : {
            'bytes': frame.bytes,
            'width': frame.width,
            'height': frame.height,
            'rotation': frame.rotation,
          };
    try {
      final result = await _channel.invokeMapMethod<String, String>(
        'readText',
        args,
      );
      return resolve(result?['text'] ?? '', result?['language'], options);
    } on PlatformException {
      return null;
    }
  }

  static String? resolve(String text, String? detected, List<Edition> options) {
    final languages = options.map((e) => e.language).toSet();
    // В современных выпусках обозначение языка следует сразу за кодом набора.
    for (final set in options.map((e) => e.set.toUpperCase()).toSet()) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(set) + r'[\s•·.\-|:]{1,6}([A-Z]{2,3})\b',
        caseSensitive: false,
      );
      final printed = pattern.firstMatch(text)?[1]?.toLowerCase();
      if (languages.contains(printed)) return printed;
    }
    if (RegExp(r'[А-Яа-яЁё]').allMatches(text).length >= 8 &&
        languages.contains('ru')) {
      return 'ru';
    }
    if (text.trim().length < 15) return null;
    return languages.contains(detected) ? detected : null;
  }

  static Edition select(List<Edition> options, String? language) =>
      options.where((e) => e.language == language).firstOrNull ??
      options.first.withLanguage('und');
}
