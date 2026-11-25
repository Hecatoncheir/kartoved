const cardLanguageNames = {
  'ru': 'Русский',
  'en': 'Английский',
  'de': 'Немецкий',
  'fr': 'Французский',
  'es': 'Испанский',
  'it': 'Итальянский',
  'pt': 'Португальский',
  'ja': 'Японский',
  'ko': 'Корейский',
  'zhs': 'Китайский (упрощённый)',
  'zht': 'Китайский (традиционный)',
};

String cardLanguageName(String code) =>
    cardLanguageNames[code] ?? code.toUpperCase();
