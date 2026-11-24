import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/keypoints.dart';
import 'package:kartoved/data/language.dart';
import 'package:kartoved/data/moxfield.dart';
import 'package:kartoved/data/pictures.dart';
import 'package:kartoved/data/recognition_result.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/scan_decision.dart';
import 'package:kartoved/data/review.dart';

void main() {
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

  test('MTG без Oracle принимает уверенное совпадение на двух кадрах', () {
    const best = (index: 1, score: .43);
    expect(standaloneMtgHit([best, (index: 2, score: .38)]), isNull);
    expect(standaloneMtgHit([(index: 1, score: .33)]), isNull);
    expect(standaloneMtgHit([best, (index: 2, score: .34)]), best);

    final scan = ScanCubit()..toggle();
    addTearDown(scan.close);
    const match = [
      Match([en], score: .43),
    ];
    expect(scan.evaluate(match), isNull);
    expect(scan.evaluate(match), isNull);
    scan.setModel(RecognitionModel.mtgStandalone);
    expect(scan.evaluate(match), isNull);
    expect(scan.evaluate(match), en);
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
