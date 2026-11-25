import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/scan_decision.dart';
import 'package:kartoved/scan_processing.dart';
import 'package:kartoved/model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Пересъёмка заменяет варианты проверки, уверенный результат засчитывается один раз', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final history = History();
    await history.open(path: inMemoryDatabasePath);
    final model = AppModel(CatalogStore(), history);
    addTearDown(model.close);
    const opt = Edition('a', 'Opt', 'eld', '59', 'en');
    const bolt = Edition('b', 'Lightning Bolt', 'm11', '149', 'en');
    const other = Edition('c', 'Lightning Bolt', 'dom', '12', 'ru');
    final scan = ScanCubit();
    addTearDown(scan.close);
    final directory = await Directory.systemTemp.createTemp('kartoved-rescan-');
    addTearDown(() => directory.delete(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const android = MethodChannel('kartoved/android');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(
      android,
      (call) async => call.method == 'readText' ? <String, String>{} : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(android, null);
    });
    Future<int> capture(
      List<Match> matches,
      String image, {
      ScanEntry? previous,
    }) async {
      final result = await prepareScan(
        matches,
        file: 'test/fixtures/$image.jpg',
        library: model,
        batch: const BatchSettings(),
        isCurrent: () => true,
        rescan: previous != null,
      );
      return scan.save(model, result!, previous: previous);
    }

    final seq = await capture(const [
      Match([opt, bolt], titleOnly: true),
    ], 'bouncers-beatdown');
    expect(model.state.reviews[seq]?.choices.first.id, opt.id);
    await capture(
      const [
        Match([bolt, other]),
      ],
      'bouncers-beatdown-ru',
      previous: model.state.recent.single,
    );
    expect(model.state.reviews[seq]?.choices.map((c) => c.id), [
      bolt.id,
      other.id,
    ]);
    expect(await history.list(), isEmpty);
    await capture(
      const [
        Match([bolt]),
      ],
      'bouncers-beatdown',
      previous: model.state.recent.single,
    );
    expect(model.state.reviews, isEmpty);
    expect(scan.state.lastScan, seq);
    expect(model.state.recent.single.sequence, seq);
    expect(model.state.owned(bolt.name), 1);
    expect((await history.list()).single.card.id, bolt.id);
    await capture(
      const [
        Match([opt, bolt], titleOnly: true),
      ],
      'bouncers-beatdown-ru',
      previous: model.state.recent.single,
    );
    expect(model.state.owned(bolt.name), 0);
    expect(model.state.reviews.keys, [seq]);
    expect(await history.list(), isEmpty);
  });
}
