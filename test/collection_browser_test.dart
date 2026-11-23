import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/collection_card.dart';
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

  testWidgets('Поиск, группировка, точный счётчик и оба варианта экспорта', (
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
    Future<String> export(String choice) async {
      saved = null;
      await tap(find.byTooltip('Экспорт для Moxfield'));
      await tester.pumpAndSettle();
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
  });
}
