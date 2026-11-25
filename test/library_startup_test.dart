import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _History extends History {
  _History(this.file);
  final String file;
  @override
  Future<void> open({String? path}) => super.open(path: file);
}

class _CatalogStore extends CatalogStore {
  final started = Completer<void>();
  var result = Completer<Catalog>();
  @override
  Future<Catalog> initialize() {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

void main() {
  late AppModel model;
  late Directory directory;
  late _CatalogStore store;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('kartoved-library-');
    final history = _History(p.join(directory.path, 'library.db'));
    store = _CatalogStore();
    model = AppModel(store, history);
    await history.open();
    final db = await openDatabase(history.file);
    addTearDown(() async {
      await model.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    await history.add(const Edition('opt', 'Opt', 'eld', '59', 'ru'));
    final initialized = model.initialize();
    await store.started.future;
    expect(model.state.owned('Opt'), 1);
    expect(model.catalog, isNull);
    store.result.completeError(StateError('Каталог недоступен'));
    await initialized;
  });

  testWidgets(
    'После ошибки каталога доступна копия, повторная загрузка сохраняет библиотеку',
    (tester) async {
      expect(model.state.error, isNotNull);
      expect(model.state.owned('Opt'), 1);
      await tester.pumpWidget(
        BlocProvider.value(
          value: model,
          child: const MaterialApp(home: CollectionsPage()),
        ),
      );
      await tester.tap(find.byTooltip('Резервная копия'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Сохранить в файл'), findsOneWidget);
      expect(find.text('Восстановить из файла'), findsOneWidget);
      const android = MethodChannel('kartoved/android');
      final messenger = tester.binding.defaultBinaryMessenger;
      Map<String, dynamic>? saved;
      messenger.setMockMethodCallHandler(android, (call) async {
        final file = File(call.arguments['path'] as String);
        saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(android, null));
      await tester.tap(find.text('Сохранить в файл'));
      for (var i = 0; saved == null && i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(saved?['scans'], contains(containsPair('name', 'Opt')));
      Navigator.of(tester.element(find.text('Сохранить в файл'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      store.result = Completer<Catalog>();
      await tester.tap(find.textContaining('Повторить'));
      await tester.pump();
      expect(model.state.error, isNull);
      store.result.complete(
        Catalog(
          directory,
          CatalogSpec.parse(
            File('assets/oracle/catalog.json').readAsStringSync(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(model.catalog, isNotNull);
      expect(model.state.owned('Opt'), 1);
    },
  );
}
