import 'package:flutter/services.dart';

import 'catalog.dart';
import 'frame.dart';

class CardLanguage {
  static const _channel = MethodChannel('kartoved/android');
  static Future<Edition> identify({
    String? file,
    PreviewFrame? frame,
    required List<Edition> options,
    List<double> corners = const [],
  }) async {
    if (options.length == 1) return options.single;
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
        {...args, 'corners': corners},
      );
      return printing(result?['text'] ?? '', result?['language'], options);
    } on PlatformException {
      return printing('', null, options);
    }
  }

  static String? resolve(String text, String? detected, List<Edition> options) {
    final languages = options.map((e) => e.language).toSet();
    if (languages.length == 1) return languages.single;
    final printed = _footer(text, options, languages);
    if (printed != null) return printed;
    final rules = _rulesLanguage(text, languages);
    if (rules != null) return rules;
    if (text.trim().length < 15) return null;
    if (languages.contains(detected)) return detected;
    final cyrillic = RegExp(r'[А-Яа-яЁё]').allMatches(text).length;
    final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
    return cyrillic >= 12 && cyrillic > latin * 2 && languages.contains('ru')
        ? 'ru'
        : null;
  }

  static String? _footer(
    String text,
    List<Edition> options,
    Set<String> languages,
  ) {
    // В современных выпусках обозначение языка следует сразу за кодом набора.
    for (final set in options.map((e) => e.set.toUpperCase()).toSet()) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(set) + r'[\s•·.\-|:]{1,6}([A-Z]{2,3})\b',
        caseSensitive: false,
      );
      final code = pattern.firstMatch(text)?[1]?.toLowerCase();
      const aliases = {
        'jp': 'ja',
        'kr': 'ko',
        'cs': 'zhs',
        'ct': 'zht',
        'sp': 'es',
      };
      final printed = aliases[code] ?? code;
      if (languages.contains(printed)) return printed;
    }
    return null;
  }

  static String? _rulesLanguage(String text, Set<String> languages) {
    final words = text.toLowerCase().split(RegExp(r'[^a-zа-яё]+')).toSet();
    final english = words.intersection({
      'target',
      'creature',
      'until',
      'turn',
      'you',
      'control',
      'this',
      'spell',
    });
    final russian = words.intersection({
      'целевое',
      'существо',
      'получает',
      'хода',
      'вашим',
      'под',
      'если',
      'карта',
    });
    if (english.length >= 2 &&
        english.length > russian.length &&
        languages.contains('en')) {
      return 'en';
    }
    if (russian.length >= 2 &&
        russian.length > english.length &&
        languages.contains('ru')) {
      return 'ru';
    }
    return null;
  }

  static Edition printing(
    String text,
    String? detected,
    List<Edition> options,
  ) {
    final lang = resolve(text, detected, options);
    final tokens = RegExp(r'[A-Za-z0-9]+')
        .allMatches(text.toLowerCase())
        .map((m) => m[0]!)
        .toSet();
    final matchingLanguage = options
        .where((e) => lang == null || e.language == lang)
        .toList();
    final bySet = matchingLanguage
        .where((e) => tokens.contains(e.set))
        .toList();
    final editions = bySet.isEmpty ? matchingLanguage : bySet;
    final byNumber = editions
        .where(
          (e) =>
              tokens.contains(e.number.toLowerCase()) ||
              tokens.contains(e.number.padLeft(4, '0')),
        )
        .toList();
    return select(byNumber.isEmpty ? editions : byNumber, lang);
  }

  static Edition select(List<Edition> options, String? language) =>
      options.where((e) => e.language == language).firstOrNull ??
      options.first.withLanguage('und');
}
