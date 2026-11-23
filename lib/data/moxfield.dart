import 'catalog.dart';

const _languages = {
  'und': '',
  'en': 'English',
  'ru': 'Russian',
  'de': 'German',
  'fr': 'French',
  'it': 'Italian',
  'ja': 'Japanese',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'ko': 'Korean',
  'zhs': 'Chinese Simplified',
  'zht': 'Chinese Traditional',
  'he': 'Hebrew',
  'ar': 'Arabic',
  'grc': 'Ancient Greek',
  'la': 'Latin',
  'sa': 'Sanskrit',
  'ph': 'Phyrexian',
  'qya': 'Quenya',
  'tlh': 'Klingon',
  'dw': 'Dwarven',
};

String moxfieldCsv(List<CardCount> rows) {
  String quote(String value) => '"${value.replaceAll('"', '""')}"';
  final out = StringBuffer(
    'Count,Name,Edition,Condition,Language,Foil,Collector Number\r\n',
  );
  for (final row in rows) {
    final c = row.card;
    out.write(
      [
        '${row.quantity}',
        c.name,
        c.set.toUpperCase(),
        '',
        _languages[c.language] ?? c.language,
        c.foil ? 'foil' : '',
        c.number,
      ].map(quote).join(','),
    );
    out.write('\r\n');
  }
  return out.toString();
}
