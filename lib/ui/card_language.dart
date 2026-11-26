import 'package:flutter/widgets.dart';

import '../l10n/strings.dart';

Map<String, String> cardLanguageNames(BuildContext context) => {
  'ru': context.strings.languageRussian,
  'en': context.strings.languageEnglish,
  'de': context.strings.languageGerman,
  'fr': context.strings.languageFrench,
  'es': context.strings.languageSpanish,
  'it': context.strings.languageItalian,
  'pt': context.strings.languagePortuguese,
  'ja': context.strings.languageJapanese,
  'ko': context.strings.languageKorean,
  'zhs': context.strings.languageChineseSimplified,
  'zht': context.strings.languageChineseTraditional,
};

String cardLanguageName(BuildContext context, String code) =>
    cardLanguageNames(context)[code] ?? code.toUpperCase();
