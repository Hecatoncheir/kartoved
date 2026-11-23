import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:kartoved/ui/picture.dart';
import 'package:kartoved/ui/scan_frame.dart';
import 'package:kartoved/ui/style.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const en = Edition(
  'c3669391-8f64-4904-b432-0f0582f30449',
  'Opt',
  'eld',
  '59',
  'en',
);
const ru = Edition(
  '5c71b782-30f9-4d91-a6d3-6325fdac4ba3',
  'Opt',
  'eld',
  '59',
  'ru',
);

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
    'Скан сохраняется сразу со звуком и фото даже при скрытой рамке',
    (tester) async {
      tester.view.physicalSize = const Size(390, 620);
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
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final photo = File('test/fixtures/bouncers-beatdown.jpg')
          .readAsBytesSync();
      File scanPhoto(Edition card) =>
          File(p.join(directory.path, 'pictures', '${card.id}.scan.jpg'));
      final image = (await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(photo);
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }))!;
      // Flutter Tester в Windows удерживает JPEG, декодированный из файла.
      for (final card in [en, ru]) {
        PaintingBinding.instance.imageCache.putIfAbsent(
          FileImage(scanPhoto(card)),
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image.clone())),
          ),
        );
      }
      addTearDown(image.dispose);
      var sounds = 0;
      var guide = true;
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      messenger.setMockMethodCallHandler(picker, (_) async => 'opt.jpg');
      messenger.setMockMethodCallHandler(android, (c) async {
        switch (c.method) {
          case 'readText':
            return <String, String>{};
          case 'scanPhoto':
            return photo;
          case 'scannerGuide':
            guide = (c.arguments as bool?) ?? guide;
            return guide;
          case 'chime':
            sounds++;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(picker, null);
        messenger.setMockMethodCallHandler(android, null);
        messenger.setMockMethodCallHandler(paths, null);
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
      final frame = find.byType(ScanFrame);
      final initialWindow = tester.widget<ScanFrame>(frame).window;
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Скрыть рамку и стекло'));
      expect(find.byType(ScanFrame), findsNothing);
      await tap(find.text('Из фото'));
      await waitFor(
        () =>
            find.text('В коллекциях: 4 · Opt').evaluate().isNotEmpty &&
            sounds == 1,
      );
      expect(model.state.recent.first.card.language, 'und');
      expect(model.state.reviews, isEmpty);
      expect(find.text('В коллекцию'), findsNothing);
      final thumbnail = find.descendant(
        of: find.byType(CardPicture),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is FileImage &&
              (widget.image as FileImage).file.path.endsWith('.scan.jpg'),
        ),
      );
      await waitFor(() => thumbnail.evaluate().isNotEmpty);
      expect(scanPhoto(en).readAsBytesSync(), photo);
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Показать рамку и стекло'));
      expect(tester.widget<ScanFrame>(frame).window, initialWindow);
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Скрыть рамку и стекло'));
      await tap(find.byTooltip('К коллекции'));
      await tap(find.text('Сканировать карту'));
      expect(find.byType(ScanFrame), findsNothing);
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Показать рамку и стекло'));
      expect(tester.widget<ScanFrame>(frame).window, initialWindow);
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
      await waitFor(
        () => model.state.recent.first.card.language == 'ru' && sounds == 2,
      );
      await tap(find.byTooltip('Отменить последнее добавление'));
      await waitFor(() => model.state.recent.length == 2);
      await waitFor(() => model.state.owned('Opt') == 4);
      expect(model.state.reviews, isEmpty);
      model.matches = const [
        Match([en]),
      ];
      await tap(find.text('Из фото'));
      await waitFor(() => model.state.owned('Opt') == 5 && sounds == 3);
      expect(model.state.reviews, isEmpty);
      expect(model.state.recent.first.card.language, 'en');
      await tap(find.byTooltip('К коллекции'));
      await tap(find.text('Сканировать карту'));
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Настройки стопки'));
      expect(find.text('Авто'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await tester.pump();
    },
  );
}
