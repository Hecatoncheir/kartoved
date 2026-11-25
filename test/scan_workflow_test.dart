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
    await app.tap(find.text('Сканировать карту'));
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
    await app.tap(find.text('Скрыть рамку и стекло'));
    expect(find.byType(ScanFrame), findsNothing);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Показать рамку и стекло'));
    expect(app.tester.widget<ScanFrame>(frame).window, initialWindow);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Скрыть рамку и стекло'));
    await app.reopenScanner();
    expect(find.byType(ScanFrame), findsNothing);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Показать рамку и стекло'));
    expect(app.tester.widget<ScanFrame>(frame).window, initialWindow);
  });

  scannerTest('Скан из фото сохраняет карту и миниатюру', (app) async {
    await app.openScanner();
    await app.tap(find.text('Из фото'));
    await app.waitFor(
      () => find.text('В коллекциях: 4 · Opt').evaluate().isNotEmpty,
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
    expect(app.sounds, 0);
  });

  scannerTest('Отмена убирает последнее добавление выбранного издания', (
    app,
  ) async {
    await app.openScanner();
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Настройки стопки'));
    await app.tap(find.text('Язык'));
    await app.tap(find.text('Русский'));
    await app.tap(find.text('Издание'));
    await app.tester.enterText(find.byType(TextField), 'eld');
    await app.tap(find.text('ELD'));
    await app.tap(find.text('Применить'));
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
    await app.tap(find.text('Настройки стопки'));
    expect(find.text('Авто'), findsNWidgets(2));
  });

  scannerTest('Сигнал ждёт изображение и текст карты', (app) async {
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
    expect(app.sounds, 0);
    app.cacheReference(bolt);
    await app.tap(find.text('Из фото'));
    await app.waitFor(
      () => app.model.state.owned('Lightning Bolt') == 2 && app.sounds == 1,
    );
    expect(app.model.state.recent.first.card.language, 'en');
  });

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
    expect(app.targetSounds, [true, false]);
    await app.openTargets();
    await app.tap(find.byTooltip('Убрать из поиска: Lightning Bolt'));
    await app.tap(find.byTooltip('Back'));
    expect(find.textContaining('Ищу ·'), findsNothing);
    expect(
      app.tester.widget<AutoScanButton>(find.byType(AutoScanButton)).running,
      isTrue,
    );
  });

  scannerTest('Выбранная модель сохраняется между сеансами', (app) async {
    await app.openScanner();
    expect(app.savedEngine, RecognitionModel.oracle.name);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Модель распознавания'));
    await app.tap(find.text(RecognitionModel.mtgIdentification.label));
    expect(app.savedEngine, RecognitionModel.mtgIdentification.name);
    await app.reopenScanner();
    await app.waitFor(() => find.text('MTG + Oracle').evaluate().isNotEmpty);
    await app.tap(find.text('Из фото'));
    await app.waitFor(() => app.model.state.owned('Opt') == 4);
    expect(app.model.lastEngine, RecognitionModel.mtgIdentification);
    await app.tap(find.byTooltip('Меню сканера'));
    await app.tap(find.text('Модель распознавания'));
    await app.tap(find.text(RecognitionModel.keypoints.label));
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
  final targetSounds = <bool>[];
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
    const paths = MethodChannel('plugins.flutter.io/path_provider');
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
