import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/collection_rows.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/collection_card.dart';
import 'package:kartoved/ui/collection_stack.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const opt = Edition('opt', 'Opt', 'eld', '59', 'en');
const sol = Edition('sol', 'Sol Ring', 'c14', '270', 'en');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
    'Флажки, удаление и отмена учитывают коллекцию, язык и покрытие',
    () async {
      final dir = await Directory.systemTemp.createTemp('kartoved-flags-');
      final path = '${dir.path}/collection.sqlite';
      final old = await openDatabase(
        path,
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE folders(folder INTEGER PRIMARY KEY,title TEXT)',
          );
          await db.execute("INSERT INTO folders VALUES (1,'Альбом')");
          await db.execute(
            'CREATE TABLE scans(seq INTEGER PRIMARY KEY,folder INTEGER,id TEXT,name TEXT,set_code TEXT,number TEXT,lang TEXT,foil INTEGER DEFAULT 0,qty INTEGER)',
          );
          await db.execute(
            "INSERT INTO scans VALUES (1,1,'opt','Opt','eld','59','en',0,3)",
          );
        },
      );
      await old.close();
      final history = History();
      await history.open(path: path);
      addTearDown(() async {
        await (await openDatabase(path)).close();
        await dir.delete(recursive: true);
      });
      final model = AppModel(CatalogStore(), history);
      addTearDown(model.close);
      await model.select(1);
      final other = await history.create('Обмен');
      await history.add(opt, folder: other);
      await model.save(opt.withLanguage('ru'));
      await model.save(opt.withFoil(true));
      await model.setFlag(opt, true);
      await model.save(opt);
      expect(model.state.flags, {opt.printingKey});
      await (await openDatabase(path)).close();
      await history.open(path: path);
      expect(await history.flags(1), {opt.printingKey});
      final removed = await model.remove(opt);
      expect(model.state.recent.length, 2);
      expect(model.state.groups.last.count, 2);
      expect(await history.flags(other), isEmpty);
      expect((await history.list(folder: other)).single.quantity, 1);
      await model.save(sol); // Новый скан может получить освобождённый номер.
      await model.select(other);
      await model.restore(removed);
      expect(model.state.folder, other);
      await model.select(1);
      expect(model.state.flags, {opt.printingKey});
      expect(model.state.groups.last.count, 7);
      final rows = await history.list();
      expect(
        rows.singleWhere((r) => r.card.printingKey == opt.printingKey).quantity,
        4,
      );
      expect(rows.singleWhere((r) => r.card.id == sol.id).quantity, 1);
      await model.setFlag(opt, false);
      expect(await history.flags(1), isEmpty);
    },
  );

  testWidgets(
    'Стопка оставляет две кромки, свайп открывает действия одной карты',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final cards = [
        for (int i = 0; i < 80; i++)
          Edition('id$i', 'Карта $i', 'eld', '$i', 'en'),
      ];
      final model = AppModel(
        CatalogStore(),
        History(),
        initial: LibraryState(
          recent: [
            for (final (i, c) in cards.indexed)
              (sequence: 80 - i, card: c, quantity: 1),
          ],
        ),
      );
      addTearDown(model.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(value: model, child: const CollectionPage()),
        ),
      );
      await tester.pump();
      Finder tile(int i) => find.byKey(ValueKey(cards[i].printingKey));
      final step =
          tester.getTopLeft(tile(1)).dy - tester.getTopLeft(tile(0)).dy;
      final top = tester.getTopLeft(tile(0)).dy;
      final button = tester.getRect(find.byType(FilledButton));
      expect(
        tester.getBottomLeft(find.byType(Scrollable)).dy,
        greaterThan(button.bottom),
      );
      expect(button.bottom, lessThanOrEqualTo(700 - 24));
      expect(
        find
            .byType(CollectionCard)
            .evaluate()
            .any(
              (e) => tester.getRect(find.byWidget(e.widget)).overlaps(button),
            ),
        isTrue,
      );
      expect(
        tester.getBottomLeft(tile(0)).dy,
        lessThan(tester.getTopLeft(tile(1)).dy),
      );
      expect(find.byType(CollectionCard).evaluate().length, lessThan(12));
      final blurs = find.descendant(
        of: find.byType(CollectionStack),
        matching: find.byType(BackdropFilter),
      );
      expect(blurs, findsNothing);
      expect(
        find.descendant(
          of: tile(0),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color?.a == 1,
          ),
        ),
        findsWidgets,
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(step * 2);
      await tester.pump();
      expect(tester.getTopLeft(tile(0)).dy, closeTo(top, 1));
      expect(tester.getTopLeft(tile(1)).dy, closeTo(top + 10, 1));
      expect(tester.getTopLeft(tile(2)).dy, closeTo(top + 20, 1));
      expect(
        tester.getSize(tile(0)).width,
        lessThan(tester.getSize(tile(1)).width),
      );
      final swipe = await tester.startGesture(tester.getCenter(tile(3)));
      await swipe.moveBy(const Offset(-30, 0));
      await swipe.moveBy(const Offset(-45, 0));
      await tester.pump();
      final flag = find.text('Флажок');
      final remove = find.text('Убрать');
      final flagCenter = tester.getCenter(flag);
      final removeCenter = tester.getCenter(remove);
      expect(flag.hitTestable(), findsNothing);
      expect(remove.hitTestable(), findsOneWidget);

      await swipe.moveBy(const Offset(-100, 0));
      await swipe.up();
      await tester.pumpAndSettle();
      expect(tester.getCenter(flag), flagCenter);
      expect(tester.getCenter(remove), removeCenter);
      expect(flag.hitTestable(), findsOneWidget);
      expect(find.byTooltip('Поставить флажок'), findsOneWidget);
      expect(find.byTooltip('Убрать из коллекции'), findsOneWidget);
      expect(position.pixels, closeTo(step * 2, 1));
      await tester.drag(tile(4), const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Убрать из коллекции'), findsOneWidget);
      await tester.drag(tile(4), const Offset(170, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Убрать из коллекции'), findsNothing);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(blurs, findsNothing);
      expect(tester.getTopLeft(tile(79)).dy, greaterThanOrEqualTo(top));
      expect(
        tester.getBottomLeft(tile(79)).dy,
        lessThanOrEqualTo(button.top - 12 + .01),
      );
      position.jumpTo(0);
      await tester.pump();
      expect(tester.getTopLeft(tile(0)).dy, top);
    },
  );

  testWidgets(
    'Значки растут по мере открытия каждой кнопки, область нажатия постоянна',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              height: 106,
              child: CollectionCard(
                item: CollectionRow([(card: opt, quantity: 1)]),
                flagged: false,
                selected: false,
                select: (_) {},
                flag: () {},
                remove: () {},
                open: () {},
              ),
            ),
          ),
        ),
      );
      final card = find.byType(CollectionCard);
      final flag = find.byIcon(Icons.flag_rounded);
      final remove = find.byIcon(Icons.delete_outline_rounded);
      final removeTarget = find.ancestor(
        of: remove,
        matching: find.byType(InkWell),
      );
      double width(Finder finder) => tester.getRect(finder).width;

      final swipe = await tester.startGesture(tester.getCenter(card));
      await swipe.moveBy(const Offset(-30, 0));
      await swipe.moveBy(const Offset(-45, 0));
      await tester.pump();
      final smallRemove = width(remove);
      final smallFlag = width(flag);
      final target = tester.getRect(removeTarget);

      await swipe.moveBy(const Offset(-80, 0));
      await tester.pump();
      final shownRemove = width(remove);
      final shownFlag = width(flag);
      expect(shownRemove, greaterThan(smallRemove));
      expect(shownFlag, greaterThan(smallFlag));

      await swipe.up();
      await tester.pumpAndSettle();
      expect(width(remove), closeTo(shownRemove, .01));
      expect(width(flag), greaterThan(shownFlag));
      expect(width(flag), closeTo(width(remove), .01));
      expect(tester.getRect(removeTarget), target);
    },
  );

  testWidgets(
    'Длинное название целиком помещается в строку альбома при крупном шрифте',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const long = Edition(
        'long',
        'The Book of Exalted Deeds',
        'afr',
        '4',
        'en',
      );
      final model = AppModel(
        CatalogStore(),
        History(),
        initial: const LibraryState(
          recent: [
            (sequence: 2, card: long, quantity: 3),
            (sequence: 1, card: opt, quantity: 1),
          ],
        ),
      );
      addTearDown(model.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(value: model, child: const CollectionPage()),
        ),
      );
      final row = find.byKey(ValueKey(long.printingKey));
      final title = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data == long.name &&
              widget.style?.fontSize == 18,
        ),
      );
      expect(tester.widget<Text>(title).maxLines, isNull);
      expect(tester.getSize(title).height, greaterThan(2 * 18 * 1.6));
      expect(
        tester.getRect(row).contains(tester.getBottomRight(title)),
        isTrue,
      );
      expect(find.text('4 карты'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Флажок, удаление последней позиции и отмена через меню', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final history = History();
    final model = AppModel(CatalogStore(), history);
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('kartoved-menu-'),
    );
    final path = '${dir!.path}/history.sqlite';
    addTearDown(() async {
      await model.close();
      await (await openDatabase(path)).close();
      await dir.delete(recursive: true);
    });
    await tester.runAsync(() async {
      await history.open(path: path);
      await model.save(opt);
      await model.save(opt);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: model, child: const CollectionPage()),
      ),
    );
    final tile = find.byKey(ValueKey(opt.printingKey));
    Future<void> open() async {
      await tester.drag(tile, const Offset(-180, 0));
      await tester.pumpAndSettle();
    }

    Future<void> choose(Finder button) async {
      final previous = model.state;
      await tester.tap(button);
      for (int i = 0; identical(previous, model.state) && i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(model.state, isNot(same(previous)));
      await tester.pumpAndSettle();
    }

    await open();
    await choose(find.byTooltip('Поставить флажок'));
    expect(model.state.flags, {opt.printingKey});
    await open();
    expect(find.byTooltip('Снять флажок'), findsOneWidget);
    await choose(find.byTooltip('Убрать из коллекции'));
    expect(find.text('Пока нет карт'), findsOneWidget);
    expect(find.text('Убрано: Opt ×2'), findsOneWidget);
    await choose(find.text('Отменить'));
    expect(model.state.flags, {opt.printingKey});
    expect(find.text('×2'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CollectionStack),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });
}
