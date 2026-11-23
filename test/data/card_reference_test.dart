import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/card_reference.dart';

void main() {
  test('Справка сохраняет перевод, текст Oracle и правила обеих сторон', () {
    final card = CardReference.fromJson(
      {
        'card_faces': [
          {
            'name': 'Front',
            'printed_name': 'Лицевая сторона',
            'printed_type_line': 'Существо',
            'printed_text': 'Возьмите карту.',
            'oracle_text': 'Draw a card.',
            'power': '3',
            'toughness': '2',
          },
          {'name': 'Back', 'oracle_text': 'Discard a card.'},
        ],
        'cmc': 3.0,
        'legalities': {'commander': 'legal', 'legacy': 'banned'},
        'artist': 'Художник',
        'set_name': 'Тестовый выпуск',
      },
      [
        {'comment': 'Rules clarification.', 'published_at': '2024-01-01'},
      ],
    );
    expect(card.faces.first.name, 'Лицевая сторона');
    expect(card.faces.first.printed, 'Возьмите карту.');
    expect(card.faces.first.oracle, 'Draw a card.');
    expect(card.faces.first.stats, '3/2');
    expect(card.faces.last.oracle, 'Discard a card.');
    expect(card.rulings!.single.text, 'Rules clarification.');
    expect(card.legalities['legacy'], 'banned');
    expect(card.setName, 'Тестовый выпуск');
  });
}
