import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/language.dart';
import 'package:kartoved/data/moxfield.dart';
import 'package:kartoved/data/pictures.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/scan_cubit.dart';

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
  test('Сходные рисунки не создают ложную запись', () {
    final gate = ScanGate();
    const uncertain = [
      Match([en], score: .86),
      Match([next], score: .84),
    ];
    expect(gate.accept(uncertain), isNull);
    expect(gate.accept(uncertain), isNull);
  });
  test('Печатный код языка, кириллица и неизвестный язык', () {
    expect(CardLanguage.resolve('SNC • RU', 'en', [ru, en]), 'ru');
    expect(
      CardLanguage.resolve('Целевое существо получает', null, [ru, en]),
      'ru',
    );
    expect(CardLanguage.resolve('123', 'en', [ru, en]), isNull);
    expect(CardLanguage.select([en, ru], null).language, 'und');
    expect(CardLanguage.select([en, ru], 'ru'), ru);
  });
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
  });
}
