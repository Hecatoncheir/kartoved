import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/catalog.dart';
import 'data/oracle.dart';
import 'data/frame.dart';
import 'data/moxfield.dart';

List<Hit> _photo(({String directory, String file}) input) =>
    identify(input.directory, input.file);
List<Hit> _preview(({String directory, PreviewFrame frame}) input) =>
    identifyImage(input.directory, frameImage(input.frame));

class Match {
  const Match(this.editions, {this.score = 1});
  final List<Edition> editions;
  final double score;
}

class LibraryState {
  const LibraryState({
    this.catalog,
    this.groups = const [],
    this.folder = 1,
    this.recent = const [],
    this.error,
  });
  final Catalog? catalog;
  final List<CardGroup> groups;
  final int folder;
  final List<ScanEntry> recent;
  final String? error;
  String get title =>
      groups.where((g) => g.id == folder).firstOrNull?.name ?? 'Моя коллекция';
}

class AppModel extends Cubit<LibraryState> {
  AppModel(
    this.store,
    this.history, {
    LibraryState initial = const LibraryState(),
  }) : super(initial);
  final CatalogStore store;
  final History history;
  Catalog? get catalog => state.catalog;
  String? get initialError => state.error;

  Future<void> initialize() async {
    try {
      await history.open();
      await _refresh(1, await store.initialize());
    } catch (e, stack) {
      debugPrint('Подготовка каталога: $e\n$stack');
      emit(const LibraryState(error: 'Не удалось подготовить базу карт'));
    }
  }

  Future<void> _refresh(int folder, Catalog? base) async {
    final groups = await history.folders();
    final recent = await history.recent(folder);
    emit(
      LibraryState(
        catalog: base,
        groups: groups,
        folder: folder,
        recent: recent,
      ),
    );
  }

  Future<void> select(int folder) => _refresh(folder, catalog);
  Future<void> create(String title) async =>
      select(await history.create(title));

  Future<List<Match>> _matches(List<Hit> hits) async {
    final matches = <Match>[];
    for (final hit in hits) {
      final editions = await catalog!.editions(hit.index);
      if (editions.isNotEmpty) matches.add(Match(editions, score: hit.score));
    }
    return matches;
  }

  Future<List<Match>> recognize(String file) async => _matches(
    await compute(_photo, (directory: catalog!.directory.path, file: file)),
  );

  Future<List<Match>> recognizeFrame(PreviewFrame frame) async => _matches(
    await compute(_preview, (directory: catalog!.directory.path, frame: frame)),
  );

  Future<void> save(Edition card) async {
    final folder = state.folder;
    final seq = await history.add(card, folder: folder);
    if (state.folder != folder) return;
    final groups = [
      for (final g in state.groups)
        g.id == folder ? (id: g.id, name: g.name, count: g.count + 1) : g,
    ];
    emit(
      LibraryState(
        catalog: catalog,
        folder: folder,
        groups: groups,
        recent: [(sequence: seq, card: card, quantity: 1), ...state.recent],
      ),
    );
  }

  Future<void> replace(ScanEntry entry, Edition card) async {
    final folder = state.folder;
    await history.replace(folder, entry.sequence, card);
    await select(folder);
  }

  Future<String> export() async {
    final rows = await history.list(folder: state.folder);
    final byPrinting = <String, CardCount>{};
    for (final row in rows) {
      final card = (await catalog!.front(row.card))
          .withLanguage(row.card.language);
      final key = "${card.id}/${card.language}";
      final total = (byPrinting[key]?.quantity ?? 0) + row.quantity;
      byPrinting[key] = (card: card, quantity: total);
    }
    return moxfieldCsv(byPrinting.values.toList());
  }

  Future<bool> update() async {
    final old = catalog!;
    final next = await store.update(old);
    if (old.spec.version == next.spec.version) return false;
    await _refresh(state.folder, next);
    return true;
  }
}
