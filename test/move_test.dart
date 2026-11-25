import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/data/review.dart';
import 'package:kartoved/model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const en = Edition('opt-en', 'Opt', 'eld', '59', 'en');
  const ru = Edition('opt-ru', 'Opt', 'dom', '60', 'ru', foil: true);
  test('Новая коллекция создаётся вместе с перемещением, ошибка откатывает обе операции', () async {
    final history = History();
    await history.open(path: inMemoryDatabasePath);
    addTearDown((await openDatabase(inMemoryDatabasePath)).close);
    final model = AppModel(CatalogStore(), history);
    addTearDown(model.close);
    await model.save(ru);
    await expectLater(
      model.moveToNewCollection('Лишняя', ru, 2),
      throwsStateError,
    );
    expect((await history.folders()).length, 1);
    final move = await model.moveToNewCollection('  На обмен  ', ru, 1);
    expect(model.state.groups.first.name, 'На обмен');
    expect(model.state.folder, 1);
    expect(model.state.holdings[ru.name], {move.to: 1});
    await model.undoMove(move);
    expect(model.state.holdings[ru.name], {1: 1});
  });
  test(
    'Перемещение части стопки и отдельных сканов обратимо и атомарно',
    () async {
      final history = History();
      await history.open(path: inMemoryDatabasePath);
      final model = AppModel(CatalogStore(), history);
      addTearDown(model.close);
      final dest = await history.create('Обмен');
      await model.select(1);
      await model.addFromCatalog(1, ru, 4);
      await model.save(ru);
      await model.setFlag(ru, true);
      await model.save(en);
      await model.save(
        ru,
        review: const ScanReview(ReviewReason.printing, [ru, en]),
      );
      await model.addFromCatalog(dest, ru, 2);
      final original = model.state.recent
          .map((e) => (e.sequence, e.card.printingKey, e.quantity))
          .toList();
      expect(model.state.holdings['Opt'], {1: 6, dest: 2});
      await expectLater(
        model.addFromCatalog(dest, en, 0x7fffffffffffffff),
        throwsRangeError,
      );
      final receipt = await model.moveCards(dest, ru, 3);
      expect(model.state.holdings['Opt'], {1: 3, dest: 5});
      expect(model.state.owned('Opt'), 8);
      expect(model.state.reviews.length, 1);
      expect(await history.flags(dest), isEmpty);
      expect(await history.flags(1), {ru.printingKey});
      await expectLater(model.moveCards(dest, ru, 3), throwsStateError);
      await expectLater(model.moveCards(1, ru, 1), throwsArgumentError);
      await expectLater(
        model.moveCards(999, ru, 1),
        throwsA(isA<DatabaseException>()),
      );
      await model.select(dest);
      await model.undoMove(receipt);
      await expectLater(model.undoMove(receipt), throwsStateError);
      await model.select(1);
      expect(model.state.holdings['Opt'], {1: 6, dest: 2});
      expect(
        model.state.recent.map(
          (e) => (e.sequence, e.card.printingKey, e.quantity),
        ),
        original,
      );
      expect(model.state.flags, {ru.printingKey});
      final other = await history.create('Пустая');
      await model.moveCards(other, ru, 5);
      expect(await history.flags(other), {ru.printingKey});
      expect(model.state.holdings['Opt'], {1: 1, dest: 2, other: 5});
    },
  );
}
