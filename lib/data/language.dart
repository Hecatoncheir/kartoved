import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'browser.dart';
import 'android.dart';
import 'catalog.dart';
import 'frame.dart';
import 'tray.dart';

class CardLanguage {
  static bool matchesEnglishTitle(String? text, String name) {
    if (text == null || text.trim().isEmpty) return false;
    String normalize(String value) =>
        value.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'\s+'), '');
    final read = normalize(text);
    final expected = normalize(name);
    return read == expected ||
        read.replaceFirst(RegExp(r'[0-9]+[©¢@®™*.+]*$'), '') == expected;
  }

  static const _channel = MethodChannel('kartoved/android');
  static Future<Edition> identify({
    String? file,
    PreviewFrame? frame,
    required List<Edition> options,
    List<double> corners = const [],
  }) async {
    final choices = await readOptions(
      file: file,
      frame: frame,
      options: options,
      corners: corners,
    );
    final languages = choices.map((e) => e.language).toSet();
    return select(choices, languages.length == 1 ? languages.single : null);
  }

  static Future<List<Edition>> readOptions({
    String? file,
    PreviewFrame? frame,
    required List<Edition> options,
    List<double> corners = const [],
    void Function()? onRead,
    bool languageOnly = false,
  }) async {
    if (options.length == 1) return options;
    onRead?.call();
    if (kIsWeb) {
      try {
        return candidates(
          await browserReadText(file!, corners),
          null,
          options,
          languageOnly: languageOnly,
        );
      } catch (e) {
        debugPrint('Не удалось прочитать текст карты в браузере: $e');
        return options;
      }
    }
    try {
      final result = await _channel.invokeMapMethod<String, String>(
        'readText',
        scanArguments(file: file, frame: frame, corners: corners),
      );
      return candidates(
        result?['text'] ?? '',
        result?['language'],
        options,
        languageOnly: languageOnly,
      );
    } on PlatformException {
      return options;
    }
  }

  static String? resolve(String text, String? detected, List<Edition> options) {
    final languages = options.map((e) => e.language).toSet();
    if (languages.length == 1) return languages.single;
    final printed = _footer(text, options, languages);
    if (printed != null) return printed.language;
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

  static ({String set, String language})? _footer(
    String text,
    List<Edition> options,
    Set<String> languages, {
    bool fromTray = false,
  }) {
    // В современных выпусках обозначение языка следует сразу за кодом набора.
    for (final set in options.map((e) => e.set.toUpperCase()).toSet()) {
      final pattern = RegExp(
        r'\b' +
            RegExp.escape(set) +
            (fromTray ? r'[\s•·.+\-|:]' : r'[\s•·.\-|:]') +
            r'{1,6}([A-Z]{2,3})\b',
        caseSensitive: false,
      );
      const aliases = {
        'jp': 'ja',
        'kr': 'ko',
        'cs': 'zhs',
        'ct': 'zht',
        'sp': 'es',
      };
      for (final match in pattern.allMatches(text)) {
        final code = match[1]!.toLowerCase();
        final printed = aliases[code] ?? code;
        if (languages.contains(printed)) {
          return (set: set.toLowerCase(), language: printed);
        }
      }
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

  static List<Edition> candidates(
    String text,
    String? detected,
    List<Edition> options, {
    bool languageOnly = false,
  }) {
    final lang = resolve(text, detected, options);
    final matchingLanguage = options
        .where((e) => lang == null || e.language == lang)
        .toList();
    if (languageOnly) return matchingLanguage;
    // Слова из текста правил могут совпасть с кодом набора (например, ONE).
    // Используем только обозначения, похожие на выходные данные карты.
    final footer = _footer(
      text,
      options,
      options.map((e) => e.language).toSet(),
    );
    final numbers = _numbers(text);
    final bySet = matchingLanguage.where((e) => e.set == footer?.set).toList();
    final editions = bySet.isEmpty ? matchingLanguage : bySet;
    final byNumber = editions
        .where((e) => numbers.contains(_number(e.number)))
        .toList();
    return byNumber.isEmpty ? editions : byNumber;
  }

  static List<Edition> trayCandidates(String text, List<Edition> options) {
    final footer = _footer(
      text,
      options,
      options.map((e) => e.language).toSet(),
      fromTray: true,
    );
    final numbers = _numbers(text);
    if (footer == null || numbers.length != 1) return [];
    return [
      for (final option in options)
        if (option.set == footer.set &&
            option.language == footer.language &&
            _number(option.number) == numbers.single)
          option,
    ];
  }

  static Future<List<Edition>> readTrayOptions(
    TrayPhoto photo,
    List<Edition> options, {
    void Function()? onRead,
    bool languageOnly = false,
  }) async {
    if (options.length == 1) return options;
    final quick = trayCandidates(photo.footer, options);
    if (quick.isNotEmpty) return quick;
    onRead?.call();
    try {
      final result = await AndroidActions.readTrayText(photo.bytes);
      return candidates(
        result.text,
        result.language,
        options,
        languageOnly: languageOnly,
      );
    } catch (_) {
      return options;
    }
  }

  static Set<String> _numbers(String text) => RegExp(
    r'\b([0-9]{1,4}[a-z]?)\s*/\s*[0-9]{3,4}\b|\b[curmspl]\s+([0-9]{3,4}[a-z]?)\b',
    caseSensitive: false,
  ).allMatches(text).map((m) => _number(m[1] ?? m[2]!)).toSet();

  static String _number(String value) =>
      value.toLowerCase().replaceFirst(RegExp(r'^0+(?=\d)'), '');

  static Edition select(List<Edition> options, String? language) {
    final matching = options.where((e) => e.language == language).toList();
    final possible = matching.isEmpty ? options : matching;
    final selected = matching.isEmpty
        ? options.first.withLanguage('und')
        : matching.first;
    if (selected.foil && possible.any((printing) => !printing.foil)) {
      return selected.withFoil(false);
    }
    return selected;
  }
}
