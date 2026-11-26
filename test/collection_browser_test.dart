import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/collection_rows.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/review.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/collection_card.dart';
import 'package:kartoved/ui/collection_detail.dart';
import 'package:kartoved/ui/catalog_search.dart';
import 'package:kartoved/ui/card_destination.dart';
import 'package:kartoved/ui/glass_sheet.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const en = Edition('opt-en', 'Opt', 'eld', '59', 'en');
const ru = Edition('opt-ru', 'Opt', 'dom', '60', 'ru', foil: true);
const island = Edition('island', 'Island', 'eld', '256', 'en');

void main() {
  late Directory root;
  late Catalog catalog;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('kartoved-browser-');
    const assets = 'assets/oracle';
    catalog = Catalog(
      root,
      CatalogSpec.parse(await File('$assets/catalog.json').readAsString()),
    );
    await File('$assets/cards.sqlite.pack')
        .openRead()
        .transform(gzip.decoder)
        .pipe(File(p.join(root.path, 'cards.sqlite')).openWrite());
  });
  tearDownAll(() => root.delete(recursive: true));

  testWidgets(
    'Карточка переносит длинное название и показывает выбранный вариант на разных экранах',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const card = Edition(
        'first',
        'The Book of Exalted Deeds',
        'afr',
        '4',
        'en',
      );
      final shiny = card.withFoil(true);
      final model = AppModel(
        CatalogStore(),
        History(),
        initial: LibraryState(
          recent: [
            (sequence: 1, card: card, quantity: 2),
            (sequence: 2, card: shiny, quantity: 1),
          ],
        ),
      );
      addTearDown(model.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: model,
          child: MaterialApp(
            home: CollectionDetail(CollectionRow(model.state.printings)),
          ),
        ),
      );
      final title = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.header == true,
        ),
        matching: find.text(card.name),
      );
      final art = find.byType(Hero);
      expect(tester.widget<Text>(title).maxLines, isNull);
      expect(tester.getSize(title).height, greaterThan(60));
      expect(
        tester.getBottomLeft(title).dy,
        lessThan(tester.getTopLeft(art).dy),
      );
      final variant = find.widgetWithText(
        ListTile,
        '${shiny.detail}  ·  Фольга',
      );
      await tester.scrollUntilVisible(variant.hitTestable(), 200);
      await tester.pumpAndSettle();
      await tester.tap(variant);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Экземпляров: 1'), findsOneWidget);
      tester.view.physicalSize = const Size(960, 720);
      await tester.pumpAndSettle();
      expect(tester.getTopRight(art).dx, lessThan(tester.getTopLeft(title).dx));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'При выборе новой коллекции нужны название и допустимое количество',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CardDestination(
              card: ru,
              groups: [(id: 2, name: 'Альбом', count: 0)],
              initialFolder: 2,
              available: 2,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Альбом'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать коллекцию').last);
      await tester.pumpAndSettle();
      FilledButton submit() => tester.widget(
        find.widgetWithText(FilledButton, 'Создать и переместить'),
      );
      expect(submit().onPressed, isNull);
      await tester.enterText(find.byType(TextFormField).last, 'Новая');
      await tester.pump();
      expect(submit().onPressed, isNotNull);
      await tester.enterText(find.widgetWithText(TextField, 'Количество'), '3');
      await tester.pump();
      expect(submit().onPressed, isNull);
    },
  );

  testWidgets('Перемещение с открытой клавиатурой на узком экране', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    CardSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showGlassSheet<CardSelection>(
                  context,
                  const CardDestination(
                    card: ru,
                    groups: [],
                    initialFolder: null,
                    available: 3,
                  ),
                  library: true,
                );
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Создать и переместить');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    final name = find.widgetWithText(TextFormField, 'Название новой коллекции');
    await tester.enterText(name, ' Обмен ');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final all = find.text('Выбрать все (3)');
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pump();
    final plus = find.widgetWithIcon(IconButton, Icons.add);
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    final minus = find.byTooltip('Уменьшить количество');
    await tester.ensureVisible(minus);
    await tester.tap(minus);
    await tester.pump();
    expect(tester.widget<IconButton>(plus).onPressed, isNotNull);
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(submit).dy, lessThanOrEqualTo(640 - 280));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(result?.quantity, 2);
    expect(result?.folderName, 'Обмен');
    expect(result?.folderId, isNull);
    expect(result?.card.printingKey, ru.printingKey);
    expect(tester.takeException(), isNull);
  });

  for (final createDestination in [false, true]) {
    testWidgets(
      'Из каталога в коллекцию, перемещение и отмена (${createDestination ? "новая коллекция" : "существующая коллекция"})',
      (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final path = p.join(root.path, 'inventory-$createDestination.sqlite');
        final history = History();
        final model = AppModel(
          CatalogStore(),
          history,
          initial: LibraryState(catalog: catalog),
        );
        late Edition ring;
        await tester.runAsync(() async {
          await history.open(path: path);
          if (!createDestination) await history.create('На обмен');
          await model.select(1);
          ring = (await catalog.byName('Sol Ring'))
              .firstWhere((e) => e.set == 'mps' && e.language == 'en');
        });
        addTearDown(() async {
          await model.close();
          await (await openDatabase(path)).close();
        });
        await tester.pumpWidget(
          BlocProvider.value(
            value: model,
            child: MaterialApp(home: CatalogSearchPage(catalog, model)),
          ),
        );
        Future<void> waitFor(bool Function() found) async {
          for (int i = 0; !found() && i < 150; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 25));
          }
          expect(found(), isTrue);
        }

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await waitFor(() => finder.hitTestable().evaluate().isNotEmpty);
          await tester.tap(finder.hitTestable());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
        }

        await tester.enterText(find.byType(TextField), 'солнечное кольцо');
        await waitFor(() => find.text('Sol Ring').evaluate().isNotEmpty);
        await tap(find.text('Sol Ring'));
        await waitFor(() => find.byType(TextField).evaluate().isNotEmpty);
        await tester.enterText(find.byType(TextField), 'mps');
        await waitFor(() => find.text(ring.detail).evaluate().isNotEmpty);
        await tap(find.text(ring.detail).first);
        final quantity = find.descendant(
          of: find.byType(CardDestination),
          matching: find.byType(TextField),
        );
        await tester.enterText(quantity, '4');
        await tap(find.text('В коллекцию'));
        await waitFor(() => model.state.owned('Sol Ring') == 4);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tap(find.text('Мои карты'));
        final location = find.widgetWithText(ActionChip, 'Моя коллекция · 4');
        await waitFor(() => location.evaluate().isNotEmpty);
        expect(find.text('×4'), findsOneWidget);
        await tap(location);
        final tile = find.byKey(ValueKey(ring.printingKey));
        await waitFor(() => tile.evaluate().isNotEmpty);
        await tap(tile);
        await tap(find.text('Переместить'));
        if (createDestination) {
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Название новой коллекции'),
            'На обмен',
          );
        }
        await tester.enterText(
          find.widgetWithText(TextField, 'Количество'),
          '2',
        );
        await tap(
          find.descendant(
            of: find.byType(CardDestination),
            matching: find.text(
              createDestination ? 'Создать и переместить' : 'Переместить',
            ),
          ),
        );
        await waitFor(
          () =>
              model.state.groups.first.name == 'На обмен' &&
              model.state.groups.first.count == 2,
        );
        expect(model.state.owned('Sol Ring'), 4);
        await waitFor(() => find.text('Отменить').evaluate().isNotEmpty);
        await tap(find.text('Отменить'));
        await waitFor(() => model.state.holdings['Sol Ring']?[1] == 4);
        expect(model.state.printings.single.card.row, ring.row);
      },
    );
  }

  test(
    'Старые строки с несколькими экземплярами уменьшаются по одному',
    () async {
      final path = p.join(root.path, 'history.sqlite');
      final history = History();
      await history.open(path: path);
      final db = await openDatabase(path);
      addTearDown(db.close);
      await db.insert('scans', {
        ...en.row,
        'folder': 1,
        'qty': 3,
        'flagged': 1,
      });
      final other = await history.create('Обмен');
      await history.add(en, folder: other);
      await history.add(ru);
      await history.takeOne(1, en);
      expect((await history.list(flaggedOnly: true)).single.quantity, 2);
      await Future.wait([
        history.takeOne(1, en),
        history.takeOne(1, en),
        history.takeOne(1, en),
      ]);
      expect((await history.list()).single.card.printingKey, ru.printingKey);
      expect((await history.list(folder: other)).single.quantity, 1);
    },
  );

  testWidgets('Поиск, группировка, точный счётчик и варианты экспорта', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final path = p.join(root.path, 'ui.sqlite');
    final history = History();
    final model = AppModel(
      CatalogStore(),
      history,
      initial: LibraryState(catalog: catalog),
    );
    await tester.runAsync(() async {
      await history.open(path: path);
      for (final card in [island, en, ru]) {
        await history.add(card);
      }
      await history.setFlag(1, ru, true);
      await model.select(1);
    });
    addTearDown(() async {
      await model.close();
      await (await openDatabase(path)).close();
    });
    MethodCall? saved;
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('kartoved/android');
    messenger.setMockMethodCallHandler(channel, (call) async {
      saved = call;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: model, child: const CollectionPage()),
      ),
    );
    Future<void> tap(Finder f) async {
      await tester.tap(f);
      await tester.pump();
    }

    Future<void> waitFor(bool Function() condition) async {
      for (int i = 0; !condition() && i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 12)),
        );
        await tester.pump(const Duration(milliseconds: 12));
      }
      expect(condition(), isTrue);
    }

    Future<void> query(String term, int expected) async {
      await tester.enterText(find.byType(TextField), term);
      await tester.pump(const Duration(milliseconds: 190));
      await waitFor(
        () => find.byType(CollectionCard).evaluate().length == expected,
      );
    }

    await tap(find.byTooltip('Группировать по названию'));
    expect(find.byType(CollectionCard), findsNWidgets(2));
    expect(find.text('×2'), findsOneWidget);
    await tap(find.text('Найти карту'));
    await query('OPT', 1);
    await query('Выбор', 1);
    await query('Нет такой карты', 0);
    await tester.pump(const Duration(milliseconds: 200));
    await waitFor(() => find.text('Совпадений нет').evaluate().isNotEmpty);
    await query('Выбор', 1);
    await tap(find.byTooltip('Только отмеченные'));
    expect(find.byKey(ValueKey(ru.printingKey)), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
    await tap(find.byTooltip('Только отмеченные'));
    await tap(find.byTooltip('Закрыть поиск'));
    await tap(find.byKey(const ValueKey('name/opt')));
    await tester.pumpAndSettle();
    await tap(find.byTooltip('Добавить один экземпляр'));
    await waitFor(
      () =>
          model.state.printings
              .firstWhere((p) => p.card.printingKey == ru.printingKey)
              .quantity ==
          2,
    );
    final english = find.widgetWithText(ListTile, '${en.detail}  ·  Обычная');
    await tester.ensureVisible(english);
    await tap(english);
    await tester.ensureVisible(find.byTooltip('Убрать один экземпляр'));
    await tap(find.byTooltip('Убрать один экземпляр'));
    await waitFor(
      () => !model.state.printings.any(
        (p) => p.card.printingKey == en.printingKey,
      ),
    );
    await tap(find.byTooltip('Добавить один экземпляр'));
    await waitFor(
      () => model.state.printings.any(
        (p) => p.card.printingKey == en.printingKey,
      ),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('×3'), findsOneWidget);
    await tap(find.byTooltip('Только отмеченные'));
    Future<String> export(String choice, {bool? includePending}) async {
      saved = null;
      await tap(find.byTooltip('Экспорт для Moxfield'));
      await tester.pumpAndSettle();
      if (includePending != null) {
        final checkbox = find.widgetWithText(
          CheckboxListTile,
          'Включить карты на проверке',
        );
        expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
        if (!includePending) await tap(checkbox);
      }
      await tap(find.text(choice));
      await tester.pumpAndSettle();
      await waitFor(() => saved != null);
      expect(saved!.method, 'saveCsv');
      return saved!.arguments['csv'] as String;
    }

    final flagged = await export('Только отмеченные');
    expect(flagged.trim().split('\n'), hasLength(2));
    expect(flagged, contains('"2","Opt","DOM","","Russian","foil","60"'));
    final all = await export('Вся коллекция');
    expect(all.trim().split('\n'), hasLength(4));
    expect(all, contains('"1","Opt","ELD","","English","","59"'));
    expect(all, contains('"2","Opt","DOM","","Russian","foil","60"'));
    expect(all, contains('"1","Island"'));
    await tap(find.byTooltip('Группировать по названию'));
    await tap(find.byTooltip('Только отмеченные'));
    expect(find.byType(CollectionCard), findsNWidgets(3));
    saved = null;
    await tap(find.byTooltip('Экспорт для Moxfield'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.runAsync(() => model.setFlag(ru, false));
    await tester.pump();
    await tap(find.byTooltip('Экспорт для Moxfield'));
    await waitFor(() => saved != null);
    expect(saved!.arguments['csv'], all);

    await tester.runAsync(() async {
      final folder = await history.create('Новые снимки');
      await history.add(
        ru,
        folder: folder,
        review: const ScanReview(ReviewReason.printing, [en, ru]),
      );
      await model.select(folder);
    });
    await tester.pump();
    expect(find.text('0 карт'), findsOneWidget);
    final withPending = await export('Экспортировать', includePending: true);
    expect(withPending.trim().split('\n'), hasLength(2));
    expect(withPending, contains('"1","Opt","DOM","","Russian","foil","60"'));
    expect(model.state.reviews, hasLength(1));
    expect(model.state.printings, isEmpty);
    await tester.runAsync(() => model.save(island));
    await tester.pump();
    final confirmed = await export('Экспортировать', includePending: false);
    expect(confirmed.trim().split('\n'), hasLength(2));
    expect(confirmed, contains('"1","Island"'));
    final nextExport = await export('Экспортировать', includePending: true);
    expect(nextExport, contains('"1","Opt","DOM","","Russian","foil","60"'));
  });
}
