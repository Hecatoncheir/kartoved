import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/card_reference.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/pictures.dart';
import 'package:kartoved/data/recognition_result.dart';
import 'package:kartoved/data/review.dart';
import 'package:kartoved/data/scan_progress.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/ui/auto_scan_controls.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:kartoved/ui/picture.dart';
import 'package:kartoved/ui/scan_frame.dart';
import 'package:kartoved/ui/scanner.dart';
import 'package:kartoved/ui/scanner_menu.dart';
import 'package:kartoved/ui/library_style.dart';
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
const domOpt = Edition(
  '00000000-0000-4000-8000-000000000123',
  'Opt',
  'dom',
  '60',
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
  Future<List<Edition>> byName(String name) async =>
      name == en.name ? [en, ru, domOpt] : [];
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
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('kartoved-scan-');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    await Pictures.shared.scanThumbnail(en.id);
    addTearDown(() {
      messenger.setMockMethodCallHandler(paths, null);
      return directory.delete(recursive: true);
    });
  });
  void scannerTest(
    String name,
    Future<void> Function(_ScannerFixture app) run,
  ) {
    testWidgets(name, (tester) async {
      final app = _ScannerFixture(tester, directory);
      await app.start();
      try {
        await run(app);
      } finally {
        await app.stop();
      }
    });
  }

  scannerTest('Выбор коллекции и сохранение рамки при повторном открытии', (
    app,
  ) async {
    await app.tap(find.text('Сканер'));
    await app.tap(find.widgetWithText(ListTile, 'На обмен'));
    await app.waitFor(
      () => find.byTooltip('Меню сканера').evaluate().isNotEmpty,
    );
    expect(app.model.state.title, 'На обмен');
    await app.tap(find.byTooltip('К коллекции'));
    await app.tap(find.text('Моя коллекция'));
    await app.waitFor(() => find.byType(CollectionPage).evaluate().isNotEmpty);
    await app.tap(find.text('Сканировать карту'));
    final frame = find.byType(ScanFrame);
    final initialWindow = app.tester.widget<ScanFrame>(frame).window;
    await app.tap(find.byTooltip('Меню сканера'));
    final guide = find.widgetWithText(FilterChip, 'Рамка и стекло');
    expect(app.tester.widget<FilterChip>(guide).selected, isTrue);
    await app.tap(guide);
    expect(app.tester.widget<FilterChip>(guide).selected, isFalse);
    await app.closeMenu();
    expect(frame, findsNothing);
    await app.reopenScanner();
    expect(frame, findsNothing);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(guide);
    await app.closeMenu();
    expect(app.tester.widget<ScanFrame>(frame).window, initialWindow);
  });

  scannerTest('Поиск издания, возврат и сброс только одного фильтра стопки', (
    app,
  ) async {
    await app.openScanner();
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Стопка и распознавание'));
    await app.tap(find.text('Язык стопки'));
    await app.tester.enterText(find.byType(TextField), 'рус');
    await app.tap(find.text('Русский'));
    await app.tap(find.text('Издание стопки'));
    await app.tester.enterText(find.byType(TextField), 'несуществующий');
    await app.waitFor(() => find.text('Нет совпадений').evaluate().isNotEmpty);
    await app.tap(find.byTooltip('Очистить поиск'));
    await app.tap(find.text('ELD'));
    await app.tap(find.text('Язык стопки'));
    await app.tap(find.text('Авто'));
    expect(
      find.descendant(of: find.byType(ScannerMenu), matching: find.text('ELD')),
      findsOneWidget,
    );
    await app.tap(find.text('Издание стопки'));
    await app.tester.binding.handlePopRoute();
    await app.tester.pumpAndSettle();
    expect(find.text('Стопка и распознавание'), findsOneWidget);
    await app.tap(find.byTooltip('Назад'));
    await app.closeMenu();
    expect(find.text('ELD'), findsOneWidget);
  });

  scannerTest('Меню на узком экране с крупным шрифтом и открытой клавиатурой', (
    app,
  ) async {
    final tester = app.tester;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 680);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await app.openScanner();
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Стопка и распознавание'));
    await app.tap(find.text('Издание стопки'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'eld');
    await app.tap(find.text('ELD'));
    tester.view.resetViewInsets();
    await app.closeMenu();
    expect(tester.takeException(), isNull);
  });

  scannerTest(
    'Смена альбома в сканере направляет следующий снимок в выбранный альбом',
    (app) async {
      await app.openScanner();
      await app.tap(find.widgetWithText(TextButton, 'Моя коллекция'));
      await app.tap(find.widgetWithText(ListTile, 'На обмен'));
      await app.waitFor(() => app.model.state.title == 'На обмен');
      await app.tap(find.text('Из фото'));
      await app.waitFor(
        () => find.text('Учтено в «На обмен»').evaluate().isNotEmpty,
      );
    },
  );

  scannerTest('Скан из фото сохраняет карту и миниатюру', (app) async {
    await app.openScanner();
    await app.tap(find.text('Из фото'));
    await app.waitFor(
      () => find.text('Учтено в «Моя коллекция»').evaluate().isNotEmpty,
    );
    final feedback = find
        .ancestor(
          of: find.text('Учтено в «Моя коллекция»'),
          matching: find.byType(Column),
        )
        .first;
    expect(
      find.descendant(of: feedback, matching: find.text(en.name)),
      findsOneWidget,
    );
    expect(app.model.state.recent.first.card.language, 'und');
    expect(app.model.state.reviews, isEmpty);
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
    await app.waitFor(() => thumbnail.evaluate().isNotEmpty);
    expect(app.scanPhoto(en).readAsBytesSync(), app.photo);
    expect(app.targetSounds, ['added']);
  });

  scannerTest('Из библиотеки можно выбрать очередь конкретного альбома', (
    app,
  ) async {
    await app.tester.runAsync(() async {
      await app.model.save(
        en,
        review: ScanReview(ReviewReason.language, [en, ru]),
      );
      final other = app.model.state.groups.firstWhere(
        (g) => g.name == 'На обмен',
      );
      await app.model.select(other.id);
      await app.model.save(
        bolt,
        review: ScanReview(ReviewReason.artwork, [bolt]),
      );
      await app.model.select(1);
    });
    await app.openLibraryReviews(2);
    await app.tap(find.widgetWithText(ListTile, 'На обмен'));
    await app.waitFor(() => find.byType(CollectionPage).evaluate().isNotEmpty);
    expect(find.text('Переснять'), findsOneWidget);
    expect(find.text(bolt.name), findsWidgets);
    expect(app.model.state.title, 'На обмен');
  });

  scannerTest(
    'Пересъёмка из фильтра заменяет выбранную запись и сохраняет соседнюю',
    (app) async {
      final ids = (await app.tester.runAsync(() async {
        final first = await app.model.save(
          en,
          review: ScanReview(ReviewReason.language, [en, ru]),
        );
        final second = await app.model.save(
          bolt,
          review: ScanReview(ReviewReason.artwork, [bolt]),
        );
        return (first, second);
      }))!;
      app.model.matches = const [
        Match([en]),
      ];
      await app.openLibraryReviews(2);
      await app.waitFor(
        () => find.byType(CollectionPage).evaluate().isNotEmpty,
      );
      final firstRow = find.byKey(ValueKey(ids.$1));
      final rescan = find.descendant(
        of: firstRow,
        matching: find.text('Переснять'),
      );
      await app.tap(rescan);
      await app.tap(find.byTooltip('К коллекции'));
      expect(app.model.state.reviews.keys, containsAll([ids.$1, ids.$2]));
      await app.tap(rescan);
      await app.tap(find.text('Из фото'));
      await app.waitFor(
        () =>
            find.byType(Scanner).evaluate().isEmpty &&
            find.text('На проверке · 1').evaluate().isNotEmpty,
      );
      expect(app.model.state.reviews.keys, [ids.$2]);
      expect(
        app.model.state.recent
            .singleWhere((e) => e.sequence == ids.$1)
            .quantity,
        1,
      );
      expect(find.byKey(ValueKey(ids.$2)), findsOneWidget);
      expect(firstRow, findsNothing);
      await app.tap(find.text('Переснять'));
      await app.tap(find.text('Из фото'));
      await app.waitFor(
        () => find.text('Все карты проверены').evaluate().isNotEmpty,
      );
      await app.tap(find.text('К альбому'));
      expect(find.byType(CollectionPage), findsOneWidget);
      expect(find.text('Найти карту'), findsOneWidget);
      expect(app.model.state.reviews, isEmpty);
    },
  );

  scannerTest(
    'После пересъёмки в середине длинной очереди соседняя карта остаётся на месте',
    (app) async {
      final ids = (await app.tester.runAsync(() async {
        final pending = ScanReview(ReviewReason.language, [en, ru]);
        final ids = <int>[];
        for (var index = 0; index < 18; index++) {
          ids.add(await app.model.save(en, review: pending));
        }
        return ids.reversed.toList();
      }))!;
      app.model.matches = const [
        Match([en]),
      ];
      await app.openLibraryReviews(ids.length);
      final list = find.byType(ListView);
      await app.waitFor(() => list.evaluate().isNotEmpty);
      final target = find.byKey(ValueKey(ids[9]));
      final viewport = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      await app.tester.scrollUntilVisible(target, 240, scrollable: viewport);
      await app.tester.ensureVisible(target);
      await app.tester.pumpAndSettle();
      final y = app.tester.getTopLeft(target).dy;
      await app.tap(
        find.descendant(of: target, matching: find.text('Переснять')),
      );
      await app.tap(find.text('Из фото'));
      await app.waitFor(
        () =>
            find.text('На проверке · 17').evaluate().isNotEmpty &&
            find.byType(Scanner).evaluate().isEmpty,
      );
      expect(app.model.state.reviews.containsKey(ids[9]), isFalse);
      final next = find.byKey(ValueKey(ids[10]));
      expect(app.tester.getTopLeft(next).dy, closeTo(y, 1));
    },
  );

  scannerTest('Отмена убирает последнее добавление выбранного издания', (
    app,
  ) async {
    await app.openScanner();
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Стопка и распознавание'));
    await app.tap(find.text('Язык стопки'));
    await app.tap(find.text('Русский'));
    await app.tap(find.text('Издание стопки'));
    await app.tester.enterText(find.byType(TextField), 'eld');
    await app.tap(find.text('ELD'));
    await app.closeMenu();
    expect(find.text('ELD · RU'), findsOneWidget);
    await app.tap(find.text('Из фото'));
    await app.waitFor(
      () =>
          app.model.state.recent.first.card.language == 'ru' && app.sounds == 1,
    );
    final official = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is FileImage &&
          (widget.image as FileImage).file.path == app.officialPhoto(ru).path,
    );
    await app.waitFor(() => official.evaluate().isNotEmpty);
    await app.tap(find.byTooltip('Отменить последнее добавление'));
    await app.waitFor(() => app.model.state.recent.length == 1);
    await app.waitFor(() => app.model.state.owned('Opt') == 3);
    expect(app.model.state.reviews, isEmpty);
    await app.reopenScanner();
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Стопка и распознавание'));
    expect(find.text('Авто'), findsNWidgets(2));
  });

  scannerTest(
    'Отмена остаётся после удаления результата и учитывает быстрые нажатия',
    (app) async {
      await app.openScanner();
      final before = app.model.state.recent.single;
      final undo = find.byTooltip('Отменить последнее добавление');
      expect(undo, findsNothing);

      app.cacheReference(bolt);
      final matches = [
        const Match([en]),
        const Match([bolt]),
        const Match([bolt], titleOnly: true, score: .70),
      ];
      for (final (index, match) in matches.indexed) {
        app.model.matches = [match];
        await app.tap(find.text('Из фото'));
        await app.waitFor(() => app.sounds == index + 1);
      }

      final saved = app.model.state.recent
          .map((entry) => entry.sequence)
          .toList();
      expect(saved.length, 4);
      expect(app.model.state.reviews.keys, [saved.first]);
      await app.tap(undo);
      await app.waitFor(() => app.model.state.recent.length == 3);
      expect(app.model.state.reviews, isEmpty);
      expect(
        app.model.state.recent.map((entry) => entry.sequence),
        saved.skip(1),
      );
      expect(app.model.state.owned(bolt.name), 1);
      expect(undo, findsOneWidget);

      await app.tester.tap(undo);
      await app.tester.tap(undo);
      await app.waitFor(() => undo.evaluate().isEmpty);
      final remaining = app.model.state.recent.single;
      expect(remaining.sequence, before.sequence);
      expect(remaining.card.printingKey, before.card.printingKey);
      expect(remaining.quantity, before.quantity);
      expect(app.model.state.owned(bolt.name), 0);
      expect(app.model.state.owned(en.name), 3);
    },
  );

  scannerTest(
    'Снятие результата с проверки не занимает шаг отмены после нового скана',
    (app) async {
      await app.openScanner();
      app.model.matches = const [
        Match([en]),
      ];
      await app.tap(find.text('Из фото'));
      await app.waitFor(() => app.sounds == 1);
      final kept = app.model.state.recent.first.sequence;

      app.model.matches = const [
        Match([bolt], titleOnly: true, score: .70),
      ];
      await app.tap(find.text('Из фото'));
      await app.waitFor(() => app.sounds == 2);
      final pending = app.model.state.reviews.keys.single;
      await app.tap(
        find.descendant(
          of: find.byKey(ValueKey(pending)),
          matching: find.byType(InkWell),
        ),
      );
      await app.tap(find.text('Убрать из очереди'));
      await app.waitFor(() => app.model.state.reviews.isEmpty);

      app.model.matches = const [
        Match([en]),
      ];
      await app.tap(find.text('Из фото'));
      await app.waitFor(() => app.sounds == 3);
      expect(app.model.state.recent.first.sequence, pending);

      final undo = find.byTooltip('Отменить последнее добавление');
      await app.tap(undo);
      await app.waitFor(() => app.model.state.recent.first.sequence == kept);
      await app.tap(undo);
      await app.waitFor(() => undo.evaluate().isEmpty);
      expect(app.model.state.recent.length, 1);
    },
  );

  scannerTest(
    'Сигнал сохранения работает без описания, спорный снимок звучит иначе',
    (app) async {
      await app.openScanner();
      app.model.matches = const [
        Match([bolt]),
      ];
      await app.tap(find.text('Из фото'));
      await app.waitFor(() => app.model.state.owned('Lightning Bolt') == 1);
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
      await app.waitFor(() => noDescription);
      expect(app.targetSounds, ['added']);
      app.model.matches = const [
        Match([bolt], titleOnly: true, score: .70),
      ];
      await app.tap(find.text('Из фото'));
      await app.waitFor(
        () => app.model.state.reviews.length == 1 && app.sounds == 2,
      );
      expect(app.targetSounds, ['added', 'review']);
      expect(app.model.state.owned('Lightning Bolt'), 1);
      expect(app.model.state.recent.first.card.language, 'en');
    },
  );

  scannerTest(
    'Только необходимое пропускает языковой OCR при английском названии и возвращается к нему для русского',
    (app) async {
      await app.openScanner();
      await app.tap(find.byTooltip('Меню сканера'));
      final quick = find.widgetWithText(SwitchListTile, 'Только необходимое');
      await app.tester.ensureVisible(quick);
      await app.tap(quick);
      await app.closeMenu();
      app.model.matches = const [
        Match([ru, en], englishTitle: true),
      ];
      await app.tap(find.text('Из фото'));
      await app.waitFor(
        () => app.model.state.owned('Opt') == 4 && app.sounds == 1,
      );
      expect(app.model.state.recent.first.card.language, 'en');
      expect(app.textReads, 0);
      await app.reopenScanner();
      app.model.matches = const [
        Match([en]),
      ];
      app.cardText = 'Целевое существо получает усиление до конца хода';
      await app.tap(find.text('Из фото'));
      await app.waitFor(
        () => app.model.state.owned('Opt') == 5 && app.sounds == 2,
      );
      expect(app.model.state.recent.first.card.language, 'ru');
      expect(app.textReads, 1);
    },
  );

  scannerTest('Искомые карты включают автоскан и получают отдельный сигнал', (
    app,
  ) async {
    await app.openScanner();
    await app.openTargets();
    await app.addTarget('選択', 'Opt');
    await app.addTarget('foudre', 'Lightning Bolt');
    await app.tap(find.text('Готово'));
    expect(find.textContaining('Ищу · карт: 2'), findsOneWidget);
    final auto = app.tester.widget<AutoScanButton>(find.byType(AutoScanButton));
    expect(auto.running, isTrue);
    expect(auto.profile, ScanMode.tray);
    app.model.matches = const [
      Match([ru]),
    ];
    await app.tap(find.text('Из фото'));
    await app.waitFor(() => app.sounds == 1);
    await app.openTargets();
    await app.tester.enterText(find.byType(TextField), 'выбор');
    await app.waitFor(
      () => find.byTooltip('Уже в списке').evaluate().isNotEmpty,
    );
    await app.tap(find.byTooltip('Очистить поиск'));
    await app.tap(find.byTooltip('Убрать из поиска: Opt'));
    expect(find.text('Opt'), findsNothing);
    expect(find.byTooltip('Убрать из поиска: Lightning Bolt'), findsOneWidget);
    await app.tap(find.text('Готово'));
    expect(find.textContaining('Ищу · Lightning Bolt'), findsOneWidget);
    await app.tap(find.text('Из фото'));
    await app.waitFor(
      () => app.model.state.owned('Opt') == 5 && app.sounds == 2,
    );
    expect(app.model.state.reviews, isEmpty);
    expect(app.model.state.recent.first.card.language, 'ru');
    expect(app.targetSounds, ['found', 'added']);
    await app.openTargets();
    await app.tap(find.byTooltip('Убрать из поиска: Lightning Bolt'));
    await app.tap(find.byTooltip('Back'));
    expect(find.textContaining('Ищу ·'), findsNothing);
    expect(
      app.tester.widget<AutoScanButton>(find.byType(AutoScanButton)).running,
      isTrue,
    );
  });

  scannerTest(
    'Быстрый скан учитывает карту до уточнения издания и не дублирует её после выбора',
    (app) async {
      await app.openScanner();
      await app.tap(find.byTooltip('Меню сканера'));
      final quick = find.widgetWithText(SwitchListTile, 'Только необходимое');
      await app.tester.ensureVisible(quick);
      await app.tap(quick);
      await app.closeMenu();
      app.model.matches = const [
        Match([en, domOpt], englishTitle: true),
      ];
      await app.tap(find.text('Из фото'));
      await app.waitFor(() => app.model.state.recent.first.card.needsPrinting);
      expect(app.model.state.owned('Opt'), 4);
      expect(app.model.state.reviews, isEmpty);
      final entry = app.model.state.recent.first;
      await app.tap(
        find.descendant(
          of: find.byKey(ValueKey(entry.sequence)),
          matching: find.byType(CardPicture),
        ),
      );
      await app.tap(find.text(domOpt.detail));
      await app.waitFor(
        () => app.model.state.recent.first.card.id == domOpt.id,
      );
      expect(app.model.state.recent.first.sequence, entry.sequence);
      expect(app.model.state.owned('Opt'), 4);
    },
  );

  scannerTest('Выбранная модель сохраняется между сеансами', (app) async {
    await app.openScanner();
    expect(app.savedEngine, RecognitionModel.oracle.name);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Стопка и распознавание'));
    await app.tap(find.text('Модель распознавания'));
    await app.tap(find.text(RecognitionModel.mtgIdentification.label));
    await app.closeMenu();
    expect(app.savedEngine, RecognitionModel.mtgIdentification.name);
    await app.reopenScanner();
    await app.waitFor(() => find.text('MTG + Oracle').evaluate().isNotEmpty);
    await app.tap(find.text('Из фото'));
    await app.waitFor(() => app.model.state.owned('Opt') == 4);
    expect(app.model.lastEngine, RecognitionModel.mtgIdentification);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Стопка и распознавание'));
    await app.tap(find.text('Модель распознавания'));
    await app.tap(find.text(RecognitionModel.keypoints.label));
    await app.closeMenu();
    expect(app.savedEngine, RecognitionModel.keypoints.name);
    await app.reopenScanner();
    await app.waitFor(() => find.text('Ключевые точки').evaluate().isNotEmpty);
    await app.tap(find.text('Из фото'));
    await app.waitFor(() => app.model.state.owned('Opt') == 5);
    expect(app.model.lastEngine, RecognitionModel.keypoints);
  });
}

class _ScannerFixture {
  _ScannerFixture(this.tester, this.directory);
  final WidgetTester tester;
  final Directory directory;
  final history = History();
  late final model = _ScannerModel(history);
  late final photo = File('test/fixtures/bouncers-beatdown.jpg')
      .readAsBytesSync();
  final targetSounds = <String>[];
  final options = <String, bool>{};
  String cardText = '';
  int textReads = 0;
  int get sounds => targetSounds.length;
  var guide = true;
  var savedEngine = RecognitionModel.oracle.name;

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

  Future<void> start() async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(() async {
      final path = p.join(
        (await directory.createTemp('library-')).path,
        'test.sqlite',
      );
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
    for (final file in [
      officialPhoto(en),
      File(p.join(directory.path, 'card-reference', '${bolt.id}.json')),
    ]) {
      if (file.existsSync()) file.deleteSync();
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
      for (final card in [en, ru, bolt, domOpt]) ...[
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
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(picker, (_) async => 'opt.jpg');
    messenger.setMockMethodCallHandler(android, (c) async {
      switch (c.method) {
        case 'readText':
          textReads++;
          return <String, String>{'text': cardText};
        case 'scannerOption':
          final key = c.arguments['name'] as String;
          return options[key] =
              c.arguments['value'] as bool? ?? options[key] ?? false;
        case 'scanPhoto':
          return photo;
        case 'scannerGuide':
          guide = (c.arguments as bool?) ?? guide;
          return guide;
        case 'scannerModel':
          savedEngine = (c.arguments as String?) ?? savedEngine;
          return savedEngine;
        case 'chime':
          targetSounds.add(c.arguments as String);
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
        child: MaterialApp(theme: libraryTheme, home: const CollectionsPage()),
      ),
    );
  }

  Future<void> waitFor(bool Function() ready, [String? reason]) async {
    for (int i = 0; !ready() && i < 350; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 12)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(
      ready(),
      isTrue,
      reason:
          '${reason ?? "Ожидание сканера"}: '
          '${model.state.holdings}, сигналы $targetSounds, '
          'уведомления ${tester.widgetList<SnackBar>(find.byType(SnackBar)).map((bar) => bar.content)}',
    );
  }

  Future<void> tap(Finder finder) async {
    if (finder.evaluate().length == 1 &&
        finder.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump();
    }
    await waitFor(
      () => finder.hitTestable().evaluate().isNotEmpty,
      finder.toString(),
    );
    await tester.tap(finder.hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> closeMenu() => tap(find.byTooltip('Закрыть меню'));

  Future<void> openLibraryReviews(int count) async {
    await tester.pumpAndSettle();
    final row = find.text('На проверке · $count');
    await tester.scrollUntilVisible(row, 160);
    await tap(row);
  }

  Future<void> openTargets() async {
    await tap(find.byTooltip('Меню сканера'));
    await tap(find.text('Стопка и распознавание'));
    await tap(find.text('Искомые карты'));
  }

  Future<void> addTarget(String translation, String name) async {
    await tester.enterText(find.byType(TextField), translation);
    await tap(find.widgetWithText(ListTile, name));
    expect(find.byTooltip('Убрать из поиска: $name'), findsOneWidget);
  }

  Future<void> openScanner() async {
    await tap(find.text('Моя коллекция'));
    await waitFor(() => find.byType(CollectionPage).evaluate().isNotEmpty);
    await tap(find.text('Сканировать карту'));
  }

  Future<void> reopenScanner() async {
    await tap(find.byTooltip('К коллекции'));
    await tap(find.text('Сканировать карту'));
  }

  Future<void> stop() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // После сигнала чтение описания может ещё держать файл открытым.
    var descriptionsReady = false;
    Future.wait([
      for (final card in [en, ru]) CardReferences.shared.get(card.id),
    ]).then((_) => descriptionsReady = true);
    await waitFor(() => descriptionsReady);
    // Даём завершиться чтению миниатюр, начатому перед закрытием сканера.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await tester.pump();
  }
}
