import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/ui/card_tilt.dart';
import 'package:kartoved/ui/catalog_search.dart';
import 'package:material_ui/material_ui.dart';

class _Catalog extends Fake implements Catalog {
  final early = Completer<List<String>>();
  @override
  Future<List<String>> searchNames(String text, {int limit = 61}) async =>
      text == 'к' ? early.future : ['Sol Ring'];

  @override
  Future<List<Edition>> byName(String name) async => [
    Edition('sample', name, 'mps', '24', 'en', foil: true),
  ];
}

void main() {
  testWidgets('Поздний ответ не замещает новый поиск, издание открывается', (
    tester,
  ) async {
    final catalog = _Catalog();
    await tester.pumpWidget(MaterialApp(home: CatalogSearchPage(catalog)));
    final field = find.byType(TextField);
    await tester.enterText(field, 'к');
    await tester.pump(const Duration(milliseconds: 180));
    await tester.enterText(field, 'кольцо');
    await tester.pump(const Duration(milliseconds: 180));
    catalog.early.complete(['Другая карта']);
    await tester.pump();
    await tester.tap(find.text('Sol Ring'));
    await tester.pumpAndSettle();
    expect(find.text('Только фольга'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pump();
    expect(find.text('Введите название карты'), findsOneWidget);
  });

  testWidgets('Соседние миниатюры наклоняются под разными углами', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            TiltCard(
              slot: 0,
              foil: true,
              child: SizedBox(width: 80, height: 100),
            ),
            TiltCard(
              slot: 1,
              foil: false,
              child: SizedBox(width: 80, height: 100),
            ),
          ],
        ),
      ),
    );
    final tiles = find.byType(TiltCard);
    Matrix4 transform(int i) => tester
        .widget<AnimatedContainer>(
          find.descendant(
            of: tiles.at(i),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .transform!;
    final neutral = transform(0);
    final touch = await tester.startGesture(tester.getCenter(tiles.first));
    await touch.moveBy(const Offset(15, 8));
    await tester.pump();
    expect(transform(0), isNot(neutral));
    expect(transform(1), isNot(transform(0)));
    await touch.up();
    await tester.pumpAndSettle();
    expect(transform(0), neutral);
  });
}
