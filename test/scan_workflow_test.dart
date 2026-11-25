import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/card_reference.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/recognition_result.dart';
import 'package:kartoved/data/scan_progress.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/ui/auto_scan_controls.dart';
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
const bolt = Edition(
  '0a6d4380-0000-4000-8000-000000000001',
  'Lightning Bolt',
  'm11',
  '149',
  'en',
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
  @override
  Future<List<String>> searchNames(String input, {int limit = 61}) async => [];
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
  RecognitionModel? lastEngine;

  @override
  Future<List<Match>> recognize(
    String file, {
    RecognitionModel engine = RecognitionModel.oracle,
    ScanProgress? onProgress,
  }) async {
    lastEngine = engine;
    return matches;
  }
}

void main() {
  testWidgets(
    'Скан сохраняется сразу, а сигнал ждёт изображение и текст Scryfall',
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
      File officialPhoto(Edition card) =>
          File(p.join(directory.path, 'pictures', '${card.id}.jpg'));
      void cacheReference(Edition card) {
        final file = File(
          p.join(directory.path, 'card-reference', '${card.id}.json'),
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          jsonEncode({
            'card': {'name': card.name, 'oracle_text': 'Draw a card.'},
            'rulings': [],
          }),
        );
      }

      cacheReference(en);
      cacheReference(ru);
      officialPhoto(ru).parent.createSync(recursive: true);
      officialPhoto(ru).writeAsBytesSync(photo);
      officialPhoto(bolt).writeAsBytesSync(photo);
      final image = (await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(photo);
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }))!;
      // Flutter Tester в Windows удерживает JPEG, декодированный из файла.
      for (final file in [
        for (final card in [en, ru, bolt]) ...[
          scanPhoto(card),
          officialPhoto(card),
        ],
      ]) {
        PaintingBinding.instance.imageCache.putIfAbsent(
          FileImage(file),
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image.clone())),
          ),
        );
      }
      addTearDown(image.dispose);
      var sounds = 0;
      final targetSounds = <bool>[];
      var guide = true;
      var savedEngine = RecognitionModel.oracle.name;
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
          case 'scannerModel':
            savedEngine = (c.arguments as String?) ?? savedEngine;
            return savedEngine;
          case 'chime':
            sounds++;
            targetSounds.add(c.arguments == true);
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

      Future<void> openTargets() async {
        await tap(find.byTooltip('Меню сканера'));
        await tap(find.text('Искомые карты'));
      }

      Future<void> addTarget(String translation, String name) async {
        await tester.enterText(find.byType(TextField), translation);
        await tap(find.widgetWithText(ListTile, name));
        expect(find.byTooltip('Убрать из поиска: $name'), findsOneWidget);
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
        () => find.text('В коллекциях: 4 · Opt').evaluate().isNotEmpty,
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
      expect(sounds, 0);
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
      await openTargets();
      await addTarget('選択', 'Opt');
      await addTarget('foudre', 'Lightning Bolt');
      await tap(find.text('Готово'));
      expect(find.textContaining('Ищу · карт: 2'), findsOneWidget);
      final auto = tester.widget<AutoScanButton>(find.byType(AutoScanButton));
      expect(auto.running, isTrue);
      expect(auto.profile, ScanMode.tray);
      await tap(find.text('Из фото'));
      await waitFor(
        () => model.state.recent.first.card.language == 'ru' && sounds == 1,
      );
      final official = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is FileImage &&
            (widget.image as FileImage).file.path == officialPhoto(ru).path,
      );
      await waitFor(() => official.evaluate().isNotEmpty);
      await tap(find.byTooltip('Отменить последнее добавление'));
      await waitFor(() => model.state.recent.length == 2);
      await waitFor(() => model.state.owned('Opt') == 4);
      expect(model.state.reviews, isEmpty);
      model.matches = const [
        Match([bolt]),
      ];
      await tap(find.text('Из фото'));
      await waitFor(() => model.state.owned('Lightning Bolt') == 1);
      var noDescription = false;
      unawaited(
        CardReferences.shared
            .get(bolt.id)
            .then<void>(
              (_) => fail('Текст карты отсутствует в тестовом кэше'),
              onError: (Object _) {
                noDescription = true;
              },
            ),
      );
      await waitFor(() => noDescription);
      expect(sounds, 1);
      cacheReference(bolt);
      await tap(find.text('Из фото'));
      await waitFor(
        () => model.state.owned('Lightning Bolt') == 2 && sounds == 2,
      );

      await openTargets();
      await tester.enterText(find.byType(TextField), 'выбор');
      await waitFor(() => find.byTooltip('Уже в списке').evaluate().isNotEmpty);
      await tap(find.byTooltip('Очистить поиск'));
      await tap(find.byTooltip('Убрать из поиска: Opt'));
      expect(find.text('Opt'), findsNothing);
      expect(
        find.byTooltip('Убрать из поиска: Lightning Bolt'),
        findsOneWidget,
      );
      await tap(find.text('Готово'));
      expect(find.textContaining('Ищу · Lightning Bolt'), findsOneWidget);
      model.matches = const [
        Match([en]),
      ];
      officialPhoto(en).writeAsBytesSync(photo);
      await tap(find.text('Из фото'));
      await waitFor(() => model.state.owned('Opt') == 5 && sounds == 3);
      expect(model.state.reviews, isEmpty);
      expect(model.state.recent.first.card.language, 'en');
      expect(targetSounds, [true, true, false]);
      await openTargets();
      await tap(find.byTooltip('Убрать из поиска: Lightning Bolt'));
      await tap(find.byTooltip('Back'));
      expect(find.textContaining('Ищу ·'), findsNothing);
      expect(
        tester.widget<AutoScanButton>(find.byType(AutoScanButton)).running,
        isTrue,
      );
      await tap(find.byTooltip('К коллекции'));
      await tap(find.text('Сканировать карту'));
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Настройки стопки'));
      expect(find.text('Авто'), findsNWidgets(2));
      expect(model.lastEngine, RecognitionModel.oracle);
      await tap(find.text('Применить'));
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Модель распознавания'));
      await tap(find.text(RecognitionModel.mtgIdentification.label));
      expect(savedEngine, RecognitionModel.mtgIdentification.name);
      await tap(find.byTooltip('К коллекции'));
      await tap(find.text('Сканировать карту'));
      await waitFor(() => find.text('MTG + Oracle').evaluate().isNotEmpty);
      await tap(find.text('Из фото'));
      await waitFor(() => model.state.owned('Opt') == 6 && sounds == 4);
      expect(model.lastEngine, RecognitionModel.mtgIdentification);
      await tap(find.byTooltip('Меню сканера'));
      await tap(find.text('Модель распознавания'));
      await tap(find.text(RecognitionModel.keypoints.label));
      expect(savedEngine, RecognitionModel.keypoints.name);
      await tap(find.byTooltip('К коллекции'));
      await tap(find.text('Сканировать карту'));
      await waitFor(() => find.text('Ключевые точки').evaluate().isNotEmpty);
      await tap(find.text('Из фото'));
      await waitFor(() => model.state.owned('Opt') == 7 && sounds == 5);
      expect(model.lastEngine, RecognitionModel.keypoints);
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await tester.pump();
    },
  );
}
