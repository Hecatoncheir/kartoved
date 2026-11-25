import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/keypoints.dart';
import 'package:kartoved/data/language.dart';
import 'package:kartoved/data/moxfield.dart';
import 'package:kartoved/data/pictures.dart';
import 'package:kartoved/data/recognition_result.dart';
import 'package:kartoved/data/tray.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/scan_decision.dart';
import 'package:kartoved/data/review.dart';

void main() {
  test('Лоток пропускает шум, сразу проверяет смену карты, подтверждение и свежий повтор', () {
    final changes = TrayChangeDetector();
    final image = Uint8List.fromList(List.filled(256, 96));
    final noise = Uint8List.fromList(List.filled(256, 101));
    expect(changes.shouldInspect(image, 0, 1), isTrue);
    expect(changes.shouldInspect(noise, 80, 1), isFalse);
    final changed = Uint8List.fromList(image)..fillRange(48, 96, 60);
    expect(changes.shouldInspect(changed, 160, 1), isTrue);
    expect(changes.shouldInspect(changed, 240, 1, force: true), isTrue);
    expect(changes.shouldInspect(changed, 400, 1), isFalse);
    expect(changes.shouldInspect(changed, 2250, 1), isTrue);
    expect(changes.shouldInspect(changed, 2260, 2), isTrue);
  });
  const en = Edition('en', 'A, "B"', 'snc', '135', 'en');
  const ru = Edition('ru', 'A, "B"', 'snc', '135', 'ru');
  const next = Edition('different', 'Island', 'm21', '265', 'en');
  const a = [
        Match([en, ru]),
      ],
      b = [
        Match([next]),
      ];
  test('Повтор, пропавший кадр и ручной дубль', () {
    final mode = ScanCubit()..toggle();
    expect(mode.evaluate(a), isNull);
    expect(mode.evaluate(a), en);
    mode.gate.saved(ru);
    expect(mode.evaluate([]), isNull);
    expect(mode.evaluate(a), isNull);
    mode.shutter();
    expect(mode.evaluate(a), ru);
    expect(mode.evaluate(b), isNull);
    expect(mode.evaluate(b), next);
    mode.gate.saved(next);
    expect(mode.evaluate(a), isNull);
    expect(mode.evaluate(a), en);
  });

  test('Список поиска допускает независимое добавление и удаление карт', () {
    final scan = ScanCubit()..toggle();
    addTearDown(scan.close);

    scan.addTarget(en.name);
    final first = scan.state.targets;
    scan.addTarget(next.name);
    scan.addTarget(en.name);
    expect(scan.state.targets.toList(), [en.name, next.name]);
    expect(first, {en.name});

    scan.recorded(1, ru, a);
    scan.removeTarget(en.name);
    expect(scan.state.targets, {next.name});
    expect(scan.state.lastScan, 1);
    scan.removeTarget(next.name);
    expect(scan.state.targets, isEmpty);
    expect(scan.state.mode, ScanMode.automatic);
  });

  testWidgets(
    'Лоток повторяет подтверждённую карту только по свежему совпадению после отсчёта',
    (tester) async {
      final scan = ScanCubit()..setMode(ScanMode.tray);
      addTearDown(scan.close);
      scan.recorded(1, ru, a, repeatable: true);
      expect(scan.repeatFor(a), isNull);
      scan.setOption(ScanOption.consecutive, true);
      final image = Uint8List(4 * TrayArea.detailSide * TrayArea.detailSide)
        ..fillRange(0, 4096, 100);
      scan.observeTray(image);
      scan.recorded(2, ru, a, repeatable: true);
      expect(scan.state.repeatSeconds, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(scan.state.repeatSeconds, 1);
      expect(scan.repeatFor(a), isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(scan.state.lastScan, 2);
      expect(scan.repeatFor([]), isNull);
      expect(scan.repeatFor(b), isNull);
      expect(
        scan.repeatFor(const [
          Match([en], score: .65),
        ]),
        isNull,
      );
      expect(scan.repeatFor(a), (card: ru, reuse: true));
      expect(
        scan.repeatFor(const [
          Match([en]),
        ])?.reuse,
        isFalse,
      );
      final textChanged = Uint8List.fromList(image)..fillRange(3072, 3092, 55);
      scan.observeTray(textChanged);
      expect(scan.repeatFor(a)?.reuse, isFalse);
      scan.observeTray(image);
      expect(scan.repeatFor(a)?.reuse, isFalse);
      scan.recorded(3, ru, a, repeatable: true);
      expect(scan.repeatFor(a), isNull);
      scan.setMode(ScanMode.automatic);
      await tester.pump(const Duration(seconds: 3));
      expect(scan.repeatFor(a), isNull);
      scan.setMode(ScanMode.tray);
      scan.recorded(4, ru, a);
      expect(scan.repeatFor(a), isNull);
    },
  );

  test('Свежие выходные данные различают две Opt и сохраняют неясный выпуск без номера', () {
    const first = Edition('eld-en', 'Opt', 'eld', '59', 'en');
    const second = Edition('dom-ru', 'Opt', 'dom', '60', 'ru');
    const other = Edition('eld-ru', 'Opt', 'eld', '59', 'ru');
    const variants = [first, second, other];
    const matches = [
      Match([first]),
    ];
    ScanDecision read(String text) => decideTrayRepeat(
      matches,
      CardLanguage.candidates(text, null, variants),
      const BatchSettings(),
    );
    expect(read('060/269 C DOM • RU').card, second);
    final unknown = read('Целевое существо под вашим контролем');
    expect(unknown.review, isNull);
    expect(unknown.card.language, 'ru');
    expect(unknown.card.needsPrinting, isTrue);
    expect(read('').review?.reason, ReviewReason.language);
  });

  test('Быстрый режим сразу принимает уверенное совпадение и сохраняет защиту от дублей', () {
    final scan = ScanCubit()..setOption(ScanOption.essentials, true);
    addTearDown(scan.close);
    expect(scan.evaluate(a), en);
    scan.recorded(1, en, a);
    expect(scan.evaluate(a), isNull);
    const uncertain = [
      Match([next], score: .70),
    ];
    expect(scan.evaluate(uncertain), isNull);
    expect(scan.evaluate(uncertain), next);
  });

  test('MTG уточняет близкие совпадения и сохраняет границу Oracle', () {
    const third = Edition('other', 'Mountain', 'm21', '269', 'en');
    const oracle = [
      Match([en, ru], score: .90),
      Match([next], score: .87),
      Match([third], score: .76),
    ];
    expect(Match.preferMtg(oracle, [third.id]), same(oracle));
    final refined = Match.preferMtg(oracle, [third.id, next.id]);
    expect(refined.map((match) => match.editions.first), [next, en, third]);
    expect(refined.first.score, oracle.first.score);
  });

  test('Сохранённый самостоятельный режим MTG заменяется Oracle', () {
    expect(RecognitionModel.fromName('mtgStandalone'), RecognitionModel.oracle);
    expect(
      RecognitionModel.fromName('mtgIdentification'),
      RecognitionModel.mtgIdentification,
    );
  });

  test('Ключевые точки различают иллюстрации на контрольных изображениях', () {
    final references = [
      File('docs/ui-prototype/media/bouncer.webp').readAsBytesSync(),
      File('docs/ui-prototype/media/counter.webp').readAsBytesSync(),
    ];
    for (final suffix in ['', '-ru']) {
      final crop = File('test/fixtures/bouncers-beatdown$suffix.jpg')
          .readAsBytesSync();
      final [same, different] = compareKeypoints((
        crop: crop,
        references: references,
      ));
      expect(same.art, greaterThanOrEqualTo(12));
      expect(different.art, 0);
    }
  });

  test('Лоток запоминает ровную карту и отклоняет сильный наклон', () {
    final area = TrayArea.calibrate([.2, .15, .8, .17, .79, .85, .21, .84]);
    expect(area?.bounds, [.2, .15, .8, .85]);
    expect(TrayArea.calibrate([.2, .15, .8, .28, .63, .85, .26, .84]), isNull);
    expect(TrayArea.calibrate([]), isNull);
  });

  test('Лоток принимает нижнюю строку, совпавшую с каталогом', () {
    expect(CardLanguage.trayCandidates('135/281 U\nSNC + RU', [en, ru]), [ru]);
    expect(
      CardLanguage.trayCandidates('138/281 U\nSNC + RU', [en, ru]),
      isEmpty,
    );
    expect(CardLanguage.trayCandidates('SNC + RU', [en, ru]), isEmpty);
  });

  test('Лоток использует порог выбранной модели и ждёт второй кадр', () {
    final scanner = ScanCubit()
      ..setModel(RecognitionModel.mtgIdentification)
      ..setMode(ScanMode.tray);
    addTearDown(scanner.close);
    const uncertain = [
      Match([en], score: .43),
    ];
    expect(scanner.evaluate(uncertain), isNull);
    expect(scanner.state.model, RecognitionModel.mtgIdentification);
    expect(scanner.evaluate(uncertain), isNull);
    expect(scanner.evaluate(a), isNull);
    expect(scanner.evaluate(a), en);
  });

  test(
    'Сходные рисунки дают одну спорную карту, отмена сохраняет защиту от дубля',
    () {
      final scan = ScanCubit()..toggle();
      const uncertain = [
        Match([en], score: .86),
        Match([next], score: .84),
      ];
      expect(scan.evaluate(uncertain), isNull);
      expect(scan.evaluate(uncertain), en);
      final decision = decideScan(uncertain, [en], scan.state.batch);
      expect(decision.review!.reason, ReviewReason.artwork);
      expect(decision.review!.choices, [en, next]);
      scan.recorded(42, en, uncertain);
      expect(scan.state.lastScan, 42);
      scan.undone();
      expect(scan.state.lastScan, isNull);
      expect(scan.state.mode, ScanMode.automatic);
      expect(scan.evaluate([]), isNull);
      expect(
        scan.evaluate([
          const Match([next], score: .86),
          const Match([en], score: .84),
        ]),
        isNull,
      );
      expect(scan.evaluate(uncertain), isNull);
      scan.shutter();
      expect(scan.evaluate(uncertain), en);
      addTearDown(scan.close);
    },
  );

  test('Стопка сужает выбор, конфликт или неоднозначный выпуск отправляются на проверку', () {
    const other = Edition('other', 'A, "B"', 'dom', '77', 'ru');
    const hits = [
      Match([en, ru, other]),
    ];
    const auto = BatchSettings();
    const russian = BatchSettings(language: 'ru');
    const batch = BatchSettings(language: 'ru', setCode: 'snc');
    expect(
      decideScan(hits, hits.first.editions, auto).review!.reason,
      ReviewReason.language,
    );
    expect(
      decideScan(hits, hits.first.editions, russian).review!.reason,
      ReviewReason.printing,
    );
    expect(decideScan(hits, hits.first.editions, batch), (
      card: ru,
      review: null,
    ));
    expect(decideScan(hits, [en], batch).review!.reason, ReviewReason.batch);
    expect(decideScan(hits, [other], batch).review!.reason, ReviewReason.batch);
    expect(
      decideScan(hits, [en], const BatchSettings(setCode: 'snc')).card,
      en,
    );
    expect(
      decideScan(hits, [
        en,
      ], const BatchSettings(setCode: 'eld')).review!.reason,
      ReviewReason.batch,
    );
  });
  test('Печатный код языка, кириллица и неизвестный язык', () {
    expect(CardLanguage.resolve('SNC • RU', 'en', [ru, en]), 'ru');
    expect(
      CardLanguage.resolve('Целевое существо получает', null, [ru, en]),
      'ru',
    );
    expect(CardLanguage.resolve('123', 'en', [ru, en]), isNull);
    expect(
      CardLanguage.resolve(
        'АБВГДЕЖЗ Deals damage to target creature you control',
        'en',
        [ru, en],
      ),
      'en',
    );
    expect(CardLanguage.select([en, ru], null).language, 'und');
    expect(CardLanguage.select([en, ru], 'ru'), ru);
  });
  test(
    'Слова и числа в тексте правил не выбирают издание одноимённой карты',
    () {
      const one = Edition('one-id', 'Opt', 'one', '2', 'en');
      const eld = Edition('eld-id', 'Opt', 'eld', '59', 'en');
      const options = [one, eld];
      expect(
        CardLanguage.candidates(
          'Choose one of 2 target creatures',
          'en',
          options,
        ),
        options,
      );
      expect(
        CardLanguage.candidates(
          'Draw one card. 059/269 ELD • EN',
          'en',
          options,
        ),
        [eld],
      );
      expect(CardLanguage.candidates('C 0002', null, options), [one]);
    },
  );
  test('CSV сохраняет язык, количество и кавычки', () {
    final data = moxfieldCsv([(card: ru, quantity: 2)]);
    expect(
      data,
      'Count,Name,Edition,Condition,Language,Foil,Collector Number\r\n"2","A, ""B""","SNC","","Russian","","135"\r\n',
    );
  });
  test('У оборотной стороны отдельная миниатюра', () {
    const id = '63ba8eef-b834-4031-b0a1-0f8505d53813';
    expect(Pictures.address('$id-1').path, '/small/back/6/3/$id.jpg');
    expect(
      Pictures.address('$id-1', large: true).path,
      '/normal/back/6/3/$id.jpg',
    );
  });
  test(
    'Фольга определяется только при однозначном покрытии и попадает в CSV',
    () {
      final foil = en.withFoil(true);
      expect(CardLanguage.select([foil], 'en').foil, isTrue);
      expect(CardLanguage.select([foil, en], 'en').foil, isFalse);
      expect(foil.printingKey, isNot(en.printingKey));
      final csv = moxfieldCsv([
        (card: foil, quantity: 2),
        (card: en, quantity: 1),
      ]);
      expect(csv, contains('"English","foil","135"'));
      expect(csv, contains('"English","","135"'));
    },
  );
}
