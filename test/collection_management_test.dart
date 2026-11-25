import 'dart:convert';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/backup.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/review.dart';
import 'package:kartoved/data/moxfield.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const opt = Edition('opt', 'Opt', 'eld', '59', 'en');
const foil = Edition('opt-ru', 'Opt', 'eld', '59', 'ru', foil: true);
const review = ScanReview(ReviewReason.language, [opt, foil]);

void main() {
  late History history;
  late AppModel model;
  late String path;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp(
      'kartoved-folders-',
    );
    path = p.join(directory.path, 'collection.db');
    history = History();
    await history.open(path: path);
    model = AppModel(CatalogStore(), history);
    await model.select(1);
    addTearDown(() async {
      await model.close();
      await (await openDatabase(path)).close();
      await directory.delete(recursive: true);
    });
  });

  test('Неуточнённые экземпляры учитываются отдельно, переживают перенос и копирование, уточняются по одному', () async {
    final unknown = opt.withoutPrinting();
    final seq = await history.add(unknown, quantity: 3);
    await model.save(opt);
    await model.setFlag(unknown, true);
    expect(model.state.flags, {unknown.printingKey});
    expect(model.state.printings.length, 2);
    expect(model.state.owned('Opt'), 4);
    expect(
      moxfieldCsv(await history.list(flaggedOnly: true)),
      contains('"3","Opt","","","English","",""'),
    );
    final backup = LibraryBackup.fromJson(
      jsonDecode(await history.backupJson()),
    );
    await model.restoreBackup(backup);
    final to = await history.create('Обмен');
    final receipt = await model.moveCards(to, unknown, 1);
    expect((await history.list(folder: to)).single.card.needsPrinting, isTrue);
    await model.undoMove(receipt);
    await model.resolvePrinting(1, unknown, opt, sequence: seq);
    final rows = model.state.printings;
    expect(rows.singleWhere((row) => row.card.needsPrinting).quantity, 2);
    expect(rows.singleWhere((row) => !row.card.needsPrinting).quantity, 2);
    expect(model.state.owned('Opt'), 4);
    expect(model.state.reviews, isEmpty);
  });

  test('Переименование и перенос сохраняют экземпляры, флажки и очередь после открытия базы', () async {
    final dest = await history.create('Обмен');
    await history.add(opt, folder: dest, quantity: 2);
    await model.addFromCatalog(1, opt, 3);
    await model.setFlag(opt, true);
    final shiny = await model.save(foil);
    await model.setFlag(foil, true);
    final pending = await model.save(opt, review: review);
    final otherPending = await history.add(foil, folder: dest, review: review);
    await model.renameFolder(1, '  Основная  ');
    expect(model.state.title, 'Основная');
    expect(model.state.groups.last.count, 4);
    final before = await history.backupJson();
    await expectLater(model.renameFolder(1, '   '), throwsFormatException);
    await expectLater(model.deleteFolder(1, moveTo: 1), throwsArgumentError);
    await expectLater(model.deleteFolder(1, moveTo: 999), throwsStateError);
    expect(await history.backupJson(), before);

    await model.deleteFolder(1, moveTo: dest);
    expect(model.state.folder, dest);
    expect(model.state.groups.single, (id: dest, name: 'Обмен', count: 6));
    await expectLater(model.deleteFolder(1, moveTo: dest), throwsStateError);
    await (await openDatabase(path)).close();
    await history.open(path: path);
    final restarted = AppModel(CatalogStore(), history);
    addTearDown(restarted.close);
    await restarted.select(1);
    expect(restarted.state.folder, dest);
    expect(restarted.state.holdings['Opt'], {dest: 6});
    expect(restarted.state.flags, {foil.printingKey});
    expect(
      (await history.list(folder: dest, flaggedOnly: true)).single.quantity,
      1,
    );
    expect(
      restarted.state.recent
          .singleWhere((s) => s.sequence == shiny)
          .card
          .printingKey,
      foil.printingKey,
    );
    expect(
      restarted.state.reviews.keys,
      unorderedEquals([pending, otherPending]),
    );
    expect(restarted.state.reviews[pending]!.encode(), review.encode());
    final snapshot = await history.backupJson();
    await restarted.restoreBackup(LibraryBackup.fromJson(jsonDecode(snapshot)));
    expect(restarted.state.folder, dest);
    expect(await history.backupJson(), snapshot);
    await restarted.confirmReview(pending, opt);
    expect(restarted.state.owned('Opt'), 7);
    expect(restarted.state.reviews.keys, [otherPending]);
  });

  test('Обложки содержат три последние разные карты каждого альбома', () async {
    const forest = Edition('forest', 'Forest', 'lea', '1', 'en');
    const island = Edition('island', 'Island', 'lea', '2', 'en');
    const plains = Edition('plains', 'Plains', 'lea', '3', 'en');
    for (final card in [opt, forest, island, plains, foil]) {
      await model.save(card);
    }
    await model.save(forest, review: review);
    Iterable<String> cover(int folder) =>
        model.state.covers[folder]!.map((card) => card.id);
    expect(cover(1), [foil.id, plains.id, island.id]);
    final other = await history.create('Обмен');
    await model.select(other);
    await model.save(forest);
    final pending = await model.save(island, review: review);
    await model.select(1);
    expect(cover(1), [foil.id, plains.id, island.id]);
    expect(cover(other), [forest.id]);
    expect(model.state.pendingByFolder, {1: 1, other: 1});
    await model.select(other);
    await model.confirmReview(pending, island);
    expect(cover(other), [island.id, forest.id]);
    expect(model.state.pendingByFolder, {1: 1});
  });

  test('Удаление очищает только выбранную коллекцию, пустую библиотеку можно восстановить', () async {
    final keep = await history.create('Оставить');
    await history.add(foil, folder: keep);
    await model.save(opt);
    await model.save(opt, review: review);
    await model.deleteFolder(1);
    expect(model.state.folder, keep);
    expect(model.state.groups.single.count, 1);
    expect(model.state.recent.single.card.printingKey, foil.printingKey);
    expect(model.state.reviews, isEmpty);
    await model.deleteFolder(keep);
    expect(model.state.groups, isEmpty);
    expect(model.state.holdings, isEmpty);
    expect(model.state.additions, isEmpty);
    expect(model.libraryReady, isTrue);
    final empty = LibraryBackup.fromJson(
      jsonDecode(await history.backupJson()),
    );
    await model.create('Новая');
    await model.save(opt);
    await model.restoreBackup(empty);
    expect(model.state.groups, isEmpty);
    await model.create('С нуля');
    expect(model.state.title, 'С нуля');
    expect(model.state.recent, isEmpty);
  });

  test('Ошибка удаления откатывает и перенос, и удаление карт', () async {
    final target = await history.create('Обмен');
    await model.save(opt);
    await model.save(foil, review: review);
    final original = await history.backupJson();
    final db = await openDatabase(path);
    await db.execute("""
      CREATE TRIGGER stop_delete BEFORE DELETE ON folders
      BEGIN SELECT RAISE(ABORT, 'test'); END
    """);
    for (final moveTo in [target, null]) {
      await expectLater(
        model.deleteFolder(1, moveTo: moveTo),
        throwsA(isA<DatabaseException>()),
      );
      expect(await history.backupJson(), original);
      expect(model.state.folder, 1);
    }
  });

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> tapAndWait(
    WidgetTester tester,
    Finder finder,
    bool Function() done,
  ) async {
    await tap(tester, finder);
    for (int i = 0; !done() && i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(done(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> openLibrary(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 900);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      BlocProvider.value(
        value: model,
        child: const MaterialApp(home: CollectionsPage()),
      ),
    );
    final album = find.byKey(const ValueKey(1));
    await tester.ensureVisible(album);
    await tapAndWait(
      tester,
      album,
      () => find.byTooltip('Действия с коллекцией').evaluate().isNotEmpty,
    );
  }

  testWidgets(
    'Из меню можно переименовать коллекцию и выбрать получателя для переноса',
    (tester) async {
      await tester.runAsync(() async {
        await history.create('Архив');
        await history.create('Обмен');
        await model.select(1);
        await model.save(opt, review: review);
      });
      await openLibrary(tester);
      final menu = find.byTooltip('Действия с коллекцией');
      await tap(tester, menu);
      await tap(tester, find.text('Переименовать'));
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, 'Моя коллекция');
      await tester.enterText(field, '   ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(field, 'Личная');
      await tester.pump();
      await tapAndWait(
        tester,
        find.text('Сохранить'),
        () => model.state.title == 'Личная',
      );
      expect(find.text('Личная'), findsOneWidget);
      await tap(tester, menu);
      await tap(tester, find.text('Перенести карты и удалить'));
      expect(find.text('Экземпляров: 0 · На проверке: 1'), findsOneWidget);
      await tap(tester, find.text('Обмен'));
      await tap(tester, find.text('Архив').last);
      await tapAndWait(
        tester,
        find.text('Перенести и удалить'),
        () => model.state.title == 'Архив',
      );
      expect(find.byType(CollectionsPage), findsOneWidget);
      expect(find.text('Личная'), findsNothing);
      expect(model.state.reviews.length, 1);
    },
  );

  testWidgets(
    'Удаление последней коллекции требует подтверждения и оставляет доступным создание',
    (tester) async {
      await tester.runAsync(() => model.save(opt));
      await openLibrary(tester);
      Future<void> ask() async {
        await tap(tester, find.byTooltip('Действия с коллекцией'));
        expect(find.text('Перенести карты и удалить'), findsNothing);
        await tap(tester, find.text('Удалить вместе с картами'));
      }

      await ask();
      await tap(tester, find.text('Отмена'));
      expect(model.state.owned('Opt'), 1);
      await ask();
      await tapAndWait(
        tester,
        find.text('Удалить'),
        () => model.state.groups.isEmpty,
      );
      expect(find.byType(CollectionsPage), findsOneWidget);
      await tap(tester, find.byTooltip('Создать коллекцию'));
      await tester.enterText(find.byType(TextField), 'Новая');
      await tester.pump();
      await tapAndWait(
        tester,
        find.text('Создать'),
        () => model.state.title == 'Новая',
      );
      expect(model.state.recent, isEmpty);
    },
  );
}
