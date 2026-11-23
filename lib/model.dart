import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/catalog.dart';
import 'data/oracle.dart';
import 'data/frame.dart';
import 'data/moxfield.dart';
import 'data/review.dart';

Recognition _photo(({String directory, String file}) input) =>
    identifyPhoto(input.directory, input.file);
Recognition _preview(({String directory, PreviewFrame frame}) input) =>
    identifyImage(input.directory, frameImage(input.frame));

class Match {
  const Match(this.editions, {this.score = 1, this.corners = const []});
  final List<double> corners;
  final List<Edition> editions;
  final double score;
}

class LibraryState {
  const LibraryState({
    this.catalog,
    this.groups = const [],
    this.folder = 1,
    this.recent = const [],
    this.flags = const {},
    this.reviews = const {},
    this.error,
  });
  final Catalog? catalog;
  final List<CardGroup> groups;
  final int folder;
  final List<ScanEntry> recent;
  final Set<String> flags;
  final Map<int, ScanReview> reviews;
  final String? error;
  List<CardCount> get printings {
    final rows = <String, CardCount>{};
    for (final entry in recent) {
      if (reviews.containsKey(entry.sequence)) continue;
      final key = entry.card.printingKey;
      rows[key] = (
        card: entry.card,
        quantity: (rows[key]?.quantity ?? 0) + entry.quantity,
      );
    }
    return rows.values.toList();
  }

  String get title =>
      groups.where((g) => g.id == folder).firstOrNull?.name ?? 'Моя коллекция';
}

class AppModel extends Cubit<LibraryState> {
  AppModel(
    this.store,
    this.history, {
    LibraryState initial = const LibraryState(),
  }) : _folder = initial.folder,
       _base = initial.catalog,
       super(initial);
  final CatalogStore store;
  final History history;
  int _folder;
  int _revision = 0;
  int _loadedRevision = 0;
  Catalog? _base;
  Catalog? get catalog => state.catalog;
  String? get initialError => state.error;

  Future<void> initialize() async {
    try {
      await history.open();
      _base = await store.initialize();
      await _refresh();
    } catch (e, stack) {
      debugPrint('Подготовка каталога: $e\n$stack');
      emit(const LibraryState(error: 'Не удалось подготовить базу карт'));
    }
  }

  Future<void> _refresh() async {
    final folder = _folder;
    final revision = ++_revision;
    final groups = await history.folders();
    final timeline = await history.timeline(folder);
    final flags = await history.flags(folder);
    if (revision != _revision || isClosed) return;
    _loadedRevision = revision;
    emit(
      LibraryState(
        catalog: _base,
        groups: groups,
        folder: folder,
        recent: timeline.recent,
        reviews: timeline.reviews,
        flags: flags,
      ),
    );
  }

  Future<bool>? _updating;
  Future<void> select(int folder) async {
    // Дождаться смены каталога раньше, чем камера начнёт читать модели.
    await _updating?.catchError((Object _) => false);
    _folder = folder;
    await _refresh();
  }

  Future<void> create(String title) async =>
      select(await history.create(title));

  Future<List<Match>> _matches(Recognition result) async {
    final matches = <Match>[];
    for (final hit in result.hits) {
      final editions = await catalog!.editions(hit.index);
      if (editions.isNotEmpty) {
        matches.add(Match(editions, score: hit.score, corners: result.corners));
      }
    }
    return matches;
  }

  Future<List<Match>> recognize(String file) async => _matches(
    await compute(_photo, (directory: catalog!.directory.path, file: file)),
  );

  Future<List<Match>> recognizeFrame(PreviewFrame frame) async => _matches(
    await compute(_preview, (directory: catalog!.directory.path, frame: frame)),
  );

  Future<int> save(Edition card, {ScanReview? review}) async {
    final folder = state.folder;
    final revision = _loadedRevision;
    final seq = await history.add(card, folder: folder, review: review);
    if (isClosed) return seq;
    if (folder != _folder || revision != _revision || state.groups.isEmpty) {
      await _refresh();
      return seq;
    }
    emit(
      LibraryState(
        catalog: catalog,
        folder: folder,
        flags: state.flags,
        reviews: review == null
            ? state.reviews
            : {...state.reviews, seq: review},
        groups: [
          for (final g in state.groups)
            g.id == folder && review == null
                ? (id: g.id, name: g.name, count: g.count + 1)
                : g,
        ],
        recent: [(sequence: seq, card: card, quantity: 1), ...state.recent],
      ),
    );
    return seq;
  }

  Future<void> confirmReview(int seq, Edition card) async {
    await history.confirm(state.folder, seq, card);
    await _refresh();
  }

  Future<void> discardScan(int seq, {bool pendingOnly = false}) async {
    await history.discard(state.folder, seq, pendingOnly: pendingOnly);
    await _refresh();
  }

  Future<void> replace(ScanEntry entry, Edition card) async {
    final folder = state.folder;
    await history.replace(folder, entry.sequence, card);
    await _refresh();
  }

  Future<void> setFlag(Edition card, bool value) async {
    await history.setFlag(state.folder, card, value);
    await _refresh();
  }

  Future<RemovedPrinting> remove(Edition card) async {
    final removed = await history.remove(state.folder, card);
    await _refresh();
    return removed;
  }

  Future<void> restore(RemovedPrinting removed) async {
    await history.restore(removed);
    await _refresh();
  }

  Future<void> takeOne(Edition card) async {
    await history.takeOne(state.folder, card);
    await _refresh();
  }

  Future<String> export({bool flaggedOnly = false}) async {
    final base = catalog;
    final rows = await history.list(
      folder: state.folder,
      flaggedOnly: flaggedOnly,
    );
    final byPrinting = <String, CardCount>{};
    for (final row in rows) {
      final card = (await base!.front(row.card))
          .withLanguage(row.card.language)
          .withFoil(row.card.foil);
      final key = card.printingKey;
      final total = (byPrinting[key]?.quantity ?? 0) + row.quantity;
      byPrinting[key] = (card: card, quantity: total);
    }
    return moxfieldCsv(byPrinting.values.toList());
  }

  Future<bool> update() => _updating ??= _update().whenComplete(() {
    _updating = null;
  });
  Future<bool> _update() async {
    final old = catalog!;
    final next = await store.update(old);
    if (old.spec.version == next.spec.version) return false;
    _base = next;
    await _refresh();
    return true;
  }
}
