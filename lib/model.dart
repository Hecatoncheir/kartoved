import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/catalog.dart';
import 'data/android.dart';
import 'data/backup.dart';
import 'data/browser.dart';
import 'data/recognition.dart';
import 'data/frame.dart';
import 'data/tray.dart';
import 'data/keypoint_scan.dart';
import 'data/moxfield.dart';
import 'data/review.dart';

class Match {
  const Match(this.editions, {this.score = 1, this.corners = const []});
  final List<double> corners;
  final List<Edition> editions;
  final double score;

  static List<Match> preferMtg(
    List<Match> matches,
    Iterable<String> printings,
  ) {
    if (matches.length < 2) return matches;
    final best = matches.first;
    final near = {
      for (final match in matches.takeWhile(
        (m) => best.score - m.score < nearMatchWindow,
      ))
        for (final edition in match.editions) edition.id: match,
    };
    final preferred = printings.map((id) => near[id]).nonNulls.firstOrNull;
    if (preferred == null || identical(preferred, best)) return matches;
    return [
      Match(preferred.editions, score: best.score, corners: preferred.corners),
      ...matches.where((match) => !identical(match, preferred)),
    ];
  }
}

class LibraryState {
  const LibraryState({
    this.catalog,
    this.groups = const [],
    this.holdings = const {},
    this.folder = 1,
    this.recent = const [],
    this.additions = const [],
    this.flags = const {},
    this.reviews = const {},
    this.error,
  });
  final Catalog? catalog;
  final List<CardGroup> groups;
  final Holdings holdings;
  int owned(String name) =>
      holdings[name]?.values.fold<int>(0, (n, qty) => n + qty) ?? 0;
  final int folder;
  final List<ScanEntry> recent;
  final List<LibraryAddition> additions;
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
    final additions = await history.latestAdditions();
    final flags = await history.flags(folder);
    final holdings = await history.holdings();
    if (revision != _revision || isClosed) return;
    _loadedRevision = revision;
    emit(
      LibraryState(
        catalog: _base,
        groups: groups,
        holdings: holdings,
        folder: folder,
        recent: timeline.recent,
        additions: additions,
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

  Future<bool> saveBackup() async {
    if (kIsWeb) {
      final date = DateTime.now().toIso8601String().split('T').first;
      final data = await history.backupJson();
      browserDownload(
        'kartoved-$date.json',
        'application/json',
        utf8.encode(data),
      );
      return true;
    }
    return AndroidActions.withBackupFile((path) async {
      await history.writeBackup(path);
      return AndroidActions.saveBackup(path);
    });
  }

  Future<LibraryBackup?> openBackup() async {
    if (kIsWeb) {
      final text = await browserPickBackup();
      return text == null ? null : LibraryBackup.fromJson(jsonDecode(text));
    }
    return AndroidActions.withBackupFile((path) async {
      if (!await AndroidActions.openBackup(path)) return null;
      return compute(LibraryBackup.read, path);
    });
  }

  Future<void> restoreBackup(LibraryBackup backup) async {
    _undoable = null;
    await history.restoreBackup(backup);
    await select(1);
  }

  static final _mtgPrintings = rootBundle
      .loadString('$mtgIdentificationAssets/printings.json')
      .then((json) => (jsonDecode(json) as List).cast<String>());

  Future<List<Match>> _standaloneMatches(Recognition result) async {
    final hit = standaloneMtgHit(result.mtgHits);
    if (hit == null) return [];
    final printings = await _mtgPrintings;
    final editions = await catalog!.editionsForPrinting(printings[hit.index]);
    return [
      if (editions.isNotEmpty)
        Match(editions, score: hit.score, corners: result.corners),
    ];
  }

  Future<List<Match>> _matches(
    Recognition result,
    RecognitionModel engine, {
    String? file,
    PreviewFrame? frame,
  }) async {
    if (engine == RecognitionModel.mtgStandalone) {
      return _standaloneMatches(result);
    }
    if (result.hits.isEmpty) return [];
    final catalog = this.catalog!;
    final matches = <Match>[];
    for (final hit in result.hits) {
      final editions = await catalog.editions(hit.index);
      if (editions.isNotEmpty) {
        matches.add(Match(editions, score: hit.score, corners: result.corners));
      }
    }
    if (engine == RecognitionModel.keypoints && matches.isNotEmpty) {
      return _preferKeypoints(
        matches,
        result.corners,
        file: file,
        frame: frame,
      );
    }
    if (result.mtgHits.isEmpty) return matches;
    final printings = await _mtgPrintings;
    return Match.preferMtg(matches, [
      for (final hit in result.mtgHits)
        if (hit.score >= .25) printings[hit.index],
    ]);
  }

  Future<List<Match>> _preferKeypoints(
    List<Match> matches,
    List<double> corners, {
    String? file,
    PreviewFrame? frame,
  }) async {
    final choice = await refineKeypointScan(
      [for (final match in matches) match.editions],
      corners,
      file: file,
      frame: frame,
    );
    if (choice == null || (choice.artwork == 0 && choice.printing == null)) {
      return matches;
    }
    final picked = matches[choice.artwork];
    final printing = choice.printing;
    final editions = printing == null
        ? picked.editions
        : [
            ...picked.editions.where(
              (e) => e.set == printing.set && e.number == printing.number,
            ),
            ...picked.editions.where(
              (e) => e.set != printing.set || e.number != printing.number,
            ),
          ];
    return [
      Match(editions, score: matches.first.score, corners: picked.corners),
      for (final match in matches)
        if (!identical(match, picked)) match,
    ];
  }

  Future<List<Match>> recognize(
    String file, {
    RecognitionModel engine = RecognitionModel.oracle,
  }) async =>
      _matches(await recognizeFile(catalog!, file, engine), engine, file: file);

  Future<List<Match>> recognizeFrame(
    PreviewFrame frame, {
    RecognitionModel engine = RecognitionModel.oracle,
  }) async => _matches(
    await recognizeCameraFrame(catalog!, frame, engine),
    engine,
    frame: frame,
  );

  Future<List<Match>> recognizeTray({
    String? file,
    PreviewFrame? frame,
    TrayArea? area,
  }) async {
    const engine = RecognitionModel.oracle;
    final installed = catalog!;
    final result = frame == null
        ? await recognizeFile(installed, file!, engine, area)
        : await recognizeCameraFrame(installed, frame, engine, area);
    return _matches(result, engine);
  }

  Future<int> save(Edition card, {ScanReview? review}) async {
    final folder = state.folder;
    final revision = _loadedRevision;
    final seq = await history.add(card, folder: folder, review: review);
    if (isClosed) return seq;
    if (folder != _folder || revision != _revision || state.groups.isEmpty) {
      await _refresh();
      return seq;
    }
    final locations = state.holdings[card.name] ?? const <int, int>{};
    emit(
      LibraryState(
        catalog: catalog,
        folder: folder,
        holdings: review != null
            ? state.holdings
            : {
                ...state.holdings,
                card.name: {...locations, folder: (locations[folder] ?? 0) + 1},
              },
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
        additions: review == null
            ? [
                (folder: folder, card: card, quantity: 1),
                ...state.additions.take(2),
              ]
            : state.additions,
      ),
    );
    return seq;
  }

  Future<void> addFromCatalog(int folder, Edition card, int quantity) async {
    await history.add(card, folder: folder, quantity: quantity);
    await _refresh();
  }

  Future<CardMove> moveCards(int to, Edition card, int quantity) async {
    final move = await history.moveCards(state.folder, to, card, quantity);
    await _refresh();
    _undoable = move;
    return move;
  }

  CardMove? _undoable;
  Future<void> undoMove(CardMove move) async {
    if (_undoable != move) throw StateError('Коллекция уже изменилась');
    _undoable = null;
    await history.undoMove(move);
    await _refresh();
  }

  Future<void> confirmReview(int seq, Edition card) async {
    await history.confirm(state.folder, seq, card);
    await _refresh();
  }

  Future<void> discardScan(int seq, {bool pendingOnly = false}) async {
    if (!pendingOnly) _undoable = null;
    await history.discard(state.folder, seq, pendingOnly: pendingOnly);
    await _refresh();
  }

  Future<void> replace(ScanEntry entry, Edition card) async {
    _undoable = null;
    final folder = state.folder;
    await history.replace(folder, entry.sequence, card);
    await _refresh();
  }

  Future<void> setFlag(Edition card, bool value) async {
    await history.setFlag(state.folder, card, value);
    await _refresh();
  }

  Future<RemovedPrinting> remove(Edition card) async {
    _undoable = null;
    final removed = await history.remove(state.folder, card);
    await _refresh();
    return removed;
  }

  Future<void> restore(RemovedPrinting removed) async {
    await history.restore(removed);
    await _refresh();
  }

  Future<void> takeOne(Edition card) async {
    _undoable = null;
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
