import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:kartoved/ui/style.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const en = Edition('opt-en', 'Opt', 'eld', '59', 'en');
const ru = Edition('opt-ru', 'Opt', 'eld', '59', 'ru');

class _Catalog extends Catalog {
  _Catalog()
    : super(
        Directory('.'),
        CatalogSpec.parse(
          File('assets/oracle/catalog.json').readAsStringSync(),
        ),
      );
  @override
  Future<List<String>> languages() async => ['en', 'ru'];
  @override
  Future<List<String>> setCodes() async => ['eld', 'dom'];
}

class _ScannerModel extends AppModel {
  _ScannerModel(History history)
    : super(
        CatalogStore(),
        history,
        initial: LibraryState(catalog: _Catalog()),
      );
  List<Match> matches = const [
    Match([en, ru]),
  ];
  @override
  Future<List<Match>> recognize(String file) async => matches;
}

void main() {
  testWidgets(
    'Спорный снимок, выбор издания, отмена и настройки стопки через камеру',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final history = History();
      final model = _ScannerModel(history);
      final directory = Directory.systemTemp.createTempSync('kartoved-scan-');
      addTearDown(() => directory.delete(recursive: true));
      final db = (await tester.runAsync(() async {
        final path = p.join(directory.path, 'test.sqlite');
        await history.open(path: path);
        await history.add(
          en,
          folder: await history.create('На обмен'),
          quantity: 2,
        );
        await model.save(ru);
        return openDatabase(path);
      }))!;
      addTearDown(model.close);
      addTearDown(db.close);
      final messenger = tester.binding.defaultBinaryMessenger;
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      const android = MethodChannel('kartoved/android');
      messenger.setMockMethodCallHandler(picker, (_) async => 'opt.jpg');
      messenger.setMockMethodCallHandler(
        android,
        (c) async => c.method == 'readText' ? <String, String>{} : null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(picker, null);
        messenger.setMockMethodCallHandler(android, null);
      });
      await tester.pumpWidget(
        BlocProvider<AppModel>.value(
          value: model,
          child: MaterialApp(
            theme: kartovedTheme(),
            home: const CollectionsPage(),
          ),
        ),
      );
      Future<void> waitFor(bool Function() ready, [String? reason]) async {
        for (int i = 0; !ready() && i < 350; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 12)),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(ready(), isTrue, reason: reason);
      }

      Future<void> tap(Finder finder) async {
        await waitFor(
          () => finder.hitTestable().evaluate().isNotEmpty,
          finder.toString(),
        );
        await tester.tap(finder.hitTestable().first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      await tap(find.text('Сканировать карту'));
      await tap(find.widgetWithText(ListTile, 'На обмен'));
      await waitFor(() => find.byTooltip('Меню сканера').evaluate().isNotEmpty);
      expect(model.state.title, 'На обмен');
      await tap(find.byTooltip('К коллекции'));
      await tap(find.text('Моя коллекция'));
      await waitFor(() => find.byType(CollectionPage).evaluate().isNotEmpty);
      await tap(find.text('Сканировать карту'));
      await tap(find.text('Из фото'));
      await waitFor(
        () => find.text('В коллекциях: 3 · Opt').evaluate().isNotEmpty,
      );
      expect(model.state.additions.length, 2);
      await tap(find.text('Проверить · 1'));
      await tap(find.widgetWithText(ListTile, 'Opt'));
      await tap(find.text(ru.detail));
      await tap(find.text('Подтвердить'));
      await waitFor(() => model.state.printings.single.quantity == 2);
      await tap(find.byType(BackButton));
      await tap(find.byTooltip('Отменить последнее добавление'));
      await waitFor(() => model.state.recent.length == 1);
      expect(model.state.printings.single.quantity, 1);
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Настройки стопки'));
      await tap(find.text('Язык'));
      await tap(find.text('Русский'));
      await tap(find.text('Издание'));
      await tester.enterText(find.byType(TextField), 'eld');
      await tap(find.text('ELD'));
      await tap(find.text('Применить'));
      expect(find.text('ELD · RU'), findsOneWidget);
      await tap(find.text('Из фото'));
      await waitFor(() => find.text('В коллекциях · 3').evaluate().isNotEmpty);
      await tap(find.text('В коллекцию'));
      await waitFor(() => model.state.printings.single.quantity == 2);
      await waitFor(
        () => find.text('В коллекциях: 4 · Opt').evaluate().isNotEmpty,
      );
      expect(model.state.reviews, isEmpty);
      model.matches = const [
        Match([en]),
      ];
      await tap(find.text('Из фото'));
      await waitFor(() => model.state.reviews.isNotEmpty);
      await tap(find.byTooltip('К коллекции'));
      await tap(find.byTooltip('Экспорт для Moxfield'));
      await tap(find.text('Проверить карты'));
      await tap(
        find.widgetWithText(ListTile, 'Расхождение с настройками стопки'),
      );
      await tap(find.text('Убрать из очереди'));
      await waitFor(() => model.state.reviews.isEmpty);
      expect(model.state.printings.single.quantity, 2);
      await tap(find.byType(BackButton));
      await tap(find.text('Сканировать карту'));
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Настройки стопки'));
      expect(find.text('Авто'), findsNWidgets(2));
    },
  );
}
