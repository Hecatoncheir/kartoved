import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/sheets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:kartoved/ui/style.dart';
import 'package:kartoved/ui/scan_strip.dart';

void main() {
  testWidgets('Выбор языка и выпуска работает без подключения', (tester) async {
    const en = Edition('a', 'Counterspell', 'lea', '54', 'en');
    const ru = Edition('b', 'Counterspell', '7ed', '67', 'ru');
    await tester.pumpWidget(
      MaterialApp(
        theme: kartovedTheme(),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () =>
                  panel<Edition>(c, const EditionPicker([en, ru], en)),
              child: const Text('Выбрать'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ru');
    await tester.pump();
    expect(find.text(ru.detail), findsOneWidget);
    expect(find.text(en.detail), findsNothing);
    await tester.tap(find.text(ru.detail));
    await tester.pumpAndSettle();
    expect(find.byType(EditionPicker), findsNothing);
  });
  testWidgets('Лента возвращается к только что добавленному экземпляру', (
    tester,
  ) async {
    const card = Edition('fixture', 'Opt', 'eld', '59', 'en');
    final rows = [
      for (var i = 20; i > 0; i--) (sequence: i, card: card, quantity: 1),
    ];
    Widget strip(List<ScanEntry> entries) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 250,
          height: 80,
          child: ScanStrip(entries, (_) {}),
        ),
      ),
    );
    await tester.pumpWidget(strip(rows));
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));
    await tester.pumpWidget(
      strip([(sequence: 21, card: card, quantity: 1), ...rows]),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    expect(find.byKey(const ValueKey(21)), findsOneWidget);
  });
  testWidgets('В пустой коллекции есть переход к сканеру', (tester) async {
    final model = AppModel(CatalogStore(), History());
    await tester.pumpWidget(
      MaterialApp(
        theme: kartovedTheme(),
        home: BlocProvider.value(value: model, child: const CollectionPage()),
      ),
    );
    expect(find.text('Сканировать карту'), findsOneWidget);
  });
}
