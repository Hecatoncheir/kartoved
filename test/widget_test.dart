import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/sheets.dart';
import 'package:kartoved/ui/picture.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kartoved/ui/album.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:kartoved/ui/style.dart';
import 'package:kartoved/ui/scan_strip.dart';

void main() {
  testWidgets('Список коллекций появляется с учётом настроек движения', (
    tester,
  ) async {
    final model = AppModel(
      CatalogStore(),
      History(),
      initial: const LibraryState(
        groups: [(id: 1, name: 'На обмен', count: 3)],
      ),
    );
    addTearDown(model.close);
    Future<void> open() => tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: model,
          child: CollectionsPage(key: UniqueKey()),
        ),
      ),
    );
    double opacity() =>
        tester.widget<SliverOpacity>(find.byType(SliverOpacity)).opacity;

    await open();
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity(), 1);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await open();
    expect(opacity(), 1);
  });

  testWidgets('Библиотека помещается на узком экране с крупным текстом', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 680);
    addTearDown(tester.view.reset);
    final model = AppModel(
      CatalogStore(),
      History(),
      initial: const LibraryState(
        groups: [(id: 1, name: 'Основная коллекция', count: 426)],
      ),
    );
    addTearDown(model.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: kartovedTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: BlocProvider.value(value: model, child: const CollectionsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final heading = find.text('Мои коллекции');
    final album = find.text('Основная коллекция');
    expect(heading, findsOneWidget);
    await tester.scrollUntilVisible(
      album,
      120,
      scrollable: find.ancestor(of: heading, matching: find.byType(Scrollable)),
    );
    expect(album, findsOneWidget);
    final shelf = tester.getRect(find.byType(ListView));
    expect(shelf.left, 0);
    expect(shelf.right, 320);
    expect(tester.getRect(find.byKey(const ValueKey(1))).left, 16);

    tester.view.padding = const FakeViewPadding(left: 8, right: 20);
    await tester.pump();
    final shelfWithInsets = tester.getRect(find.byType(ListView));
    expect(shelfWithInsets.left, 0);
    expect(shelfWithInsets.right, 320);
    expect(tester.getRect(find.byKey(const ValueKey(1))).left, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Обложка и недавние карты сохраняют одинаковые боковые поля', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(left: 8, right: 20);
    addTearDown(tester.view.reset);
    final model = AppModel(
      CatalogStore(),
      History(),
      initial: const LibraryState(
        groups: [(id: 1, name: 'Моя коллекция', count: 0)],
      ),
    );
    addTearDown(model.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: kartovedTheme(),
        home: BlocProvider.value(value: model, child: const CollectionsPage()),
      ),
    );
    final recent = find.ancestor(
      of: find.text('Подтверждённые карты появятся здесь'),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.color == surface,
      ),
    );
    for (final area in [find.byType(AlbumHeader), recent]) {
      final rect = tester.getRect(area);
      expect(rect.left, 16);
      expect(rect.right, 374);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Заголовок альбомов прокручивается под акриловой шапкой', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 520);
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    final model = AppModel(
      CatalogStore(),
      History(),
      initial: const LibraryState(groups: [(id: 1, name: 'Альбом', count: 3)]),
    );
    addTearDown(model.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: kartovedTheme(),
        home: BlocProvider.value(value: model, child: const CollectionsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final bar = find.byType(AppBar);
    final bounds = tester.getRect(bar);
    final title = find.text('Альбомы');
    expect(
      tester.getTopLeft(find.byType(AlbumHeader)).dy,
      greaterThan(bounds.bottom),
    );
    final scroll = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    final titleCenter = tester.getCenter(title).dy;
    expect(titleCenter, greaterThan(bounds.bottom));
    final position = tester.state<ScrollableState>(scroll).position;
    position.jumpTo(titleCenter - bounds.bottom + 12);
    await tester.pump();
    expect(tester.getRect(bar), bounds);
    expect(
      tester.getCenter(title).dy,
      inExclusiveRange(bounds.top, bounds.bottom),
    );
    final acrylic = find.descendant(
      of: bar,
      matching: find.byType(BackdropFilter),
    );
    expect(tester.getRect(acrylic), bounds);
  });

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

  testWidgets('При быстрой съёмке каждая новая карта занимает первое место', (
    tester,
  ) async {
    const card = Edition('fixture', 'Opt', 'eld', '59', 'en');
    int? edited;
    Future<void> show(List<int> ids) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 80,
            child: ScanStrip([
              for (final id in ids) (sequence: id, card: card, quantity: 1),
            ], (entry) => edited = entry.sequence),
          ),
        ),
      ),
    );
    double width(int id) =>
        tester.getSize(find.byKey(ValueKey(id), skipOffstage: false)).width;

    await show([]);
    await show([1]);
    await tester.pump(const Duration(milliseconds: 50));
    final entering = width(1);
    await show([2, 1]);
    expect(entering, greaterThan(0));
    expect(entering, lessThan(width(1)));
    expect(width(2), 0);
    await tester.pump(const Duration(milliseconds: 60));
    final secondWidth = width(2);
    await show([2, 1]);
    expect(width(2), secondWidth);
    await tester.pumpAndSettle();
    expect(width(2), width(1));
    expect(
      tester.getCenter(find.byKey(const ValueKey(2))).dx,
      lessThan(tester.getCenter(find.byKey(const ValueKey(1))).dx),
    );
    final tile = find.byKey(const ValueKey(2));
    final picture = find.descendant(
      of: tile,
      matching: find.byType(CardPicture),
    );
    final rescan = find.descendant(of: tile, matching: find.byType(TextButton));
    expect(
      tester.getTopLeft(rescan).dy - tester.getBottomLeft(picture).dy,
      greaterThanOrEqualTo(8),
    );
    await tester.tap(picture);
    expect(edited, 2);
  });

  testWidgets('При отключённых анимациях новая карта сразу видна целиком', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    const card = Edition('fixture', 'Opt', 'eld', '59', 'en');
    Future<void> show(int newest) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 250,
            height: 80,
            child: ScanStrip([
              for (var id = newest; id > 0; id--)
                (sequence: id, card: card, quantity: 1),
            ], (_) {}),
          ),
        ),
      ),
    );
    await show(20);
    final fullWidth = tester.getSize(find.byKey(const ValueKey(20))).width;
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));
    await show(21);
    expect(position.pixels, 0);
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey(21))).width, fullWidth);
  });
}
