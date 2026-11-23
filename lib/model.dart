import 'package:flutter/foundation.dart';

import 'data/catalog.dart';
import 'data/oracle.dart';

List<Hit> _identifyPhoto(({String directory, String file}) input) =>
    identify(input.directory, input.file);

class Match {
  const Match(this.editions);
  final List<Edition> editions;
}

class AppModel extends ChangeNotifier {
  AppModel(this.store, this.history);
  final CatalogStore store;
  final History history;
  Catalog? catalog;
  bool busy = false;
  String? initialError;
  List<({Edition card, int quantity})> cards = [];
  Future<void> initialize() async {
    initialError = null;
    await work(() async {
      try {
        await history.open();
        cards = await history.list();
        catalog = await store.initialize();
      } catch (e, stack) {
        debugPrint('Подготовка каталога: $e\n$stack');
        initialError = 'Не удалось подготовить базу карт';
      }
    });
  }

  Future<T> work<T>(Future<T> Function() action) async {
    if (busy) throw StateError('Дождитесь завершения операции');
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<Match>> recognize(String file) => work(() async {
    final current = catalog!;
    final directory = current.directory.path;
    final hits = await compute(_identifyPhoto, (
      directory: directory,
      file: file,
    ));
    final result = <Match>[];
    for (final hit in hits) {
      final editions = await current.editions(hit.index);
      if (editions.isNotEmpty) result.add(Match(editions));
    }
    return result;
  });
  Future<void> save(Edition card) => work(() async {
    await history.add(card);
    cards = await history.list();
  });
  Future<bool> update() => work(() async {
    final old = catalog!;
    catalog = await store.update(old);
    return catalog!.spec.version != old.spec.version;
  });
}
