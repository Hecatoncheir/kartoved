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
import 'data/language.dart';
import 'data/moxfield.dart';
import 'data/review.dart';

class Match {
  const Match(
    this.editions, {
    this.score = 1,
    this.corners = const [],
    this.fromTitle = false,
    this.titleOnly = false,
    this.englishTitle = false,
  });
  final List<double> corners;
  final List<Edition> editions;
  final double score;
  final bool fromTitle, titleOnly;
  final bool englishTitle;

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

enum LibraryLoadError { collections, catalog }

class LibraryState {
  const LibraryState({
    this.catalog,
    this.groups = const [],
    this.covers = const {},
    this.pendingByFolder = const {},
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
  final Map<int, List<Edition>> covers;
  final Map<int, int> pendingByFolder;
  final Holdings holdings;
  int owned(String name) =>
      holdings[name]?.values.fold<int>(0, (n, qty) => n + qty) ?? 0;
  final int folder;
  final List<ScanEntry> recent;
  final List<LibraryAddition> additions;
  final Set<String> flags;
  final Map<int, ScanReview> reviews;
  final LibraryLoadError? error;
  LibraryState withCatalog(Catalog? catalog, {LibraryLoadError? error}) =>
      LibraryState(
        catalog: catalog,
        groups: groups,
        covers: covers,
        pendingByFolder: pendingByFolder,
        holdings: holdings,
        folder: folder,
        recent: recent,
        additions: additions,
        flags: flags,
        reviews: reviews,
        error: error,
      );

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
  bool get libraryReady => _loadedRevision > 0 || state.groups.isNotEmpty;
  Catalog? _base;
  Catalog? get catalog => state.catalog;
  LibraryLoadError? get initialError => state.error;

  Future<void>? _initializing;
  Future<void> initialize() => _initializing ??= _initialize().whenComplete(() {
    _initializing = null;
  });

  Future<void> _initialize() async {
    if (!libraryReady) {
      try {
        await history.open();
        await _refresh();
      } catch (e, stack) {
        debugPrint('Открытие коллекций: $e\n$stack');
        if (!isClosed) {
          emit(state.withCatalog(null, error: LibraryLoadError.collections));
        }
        return;
      }
    }
    if (isClosed) return;
    emit(state.withCatalog(_base));
    try {
      _base = await store.initialize();
      if (!isClosed) emit(state.withCatalog(_base));
    } catch (e, stack) {
      debugPrint('Подготовка каталога: $e\n$stack');
      if (!isClosed) {
        emit(state.withCatalog(_base, error: LibraryLoadError.catalog));
      }
    }
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    final groups = await history.folders();
    final covers = await history.albumCovers();
    final pending = await history.pendingCounts();
    final folder = groups.any((group) => group.id == _folder)
        ? _folder
        : groups.lastOrNull?.id ?? 1;
    final timeline = await history.timeline(folder);
    final additions = await history.latestAdditions();
    final flags = await history.flags(folder);
    final holdings = await history.holdings();
    if (revision != _revision || isClosed) return;
    _folder = folder;
    _loadedRevision = revision;
    emit(
      LibraryState(
        catalog: _base,
        error: state.error,
        groups: groups,
        covers: covers,
        pendingByFolder: pending,
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

  Future<void> renameFolder(int folder, String title) async {
    await history.renameFolder(folder, title);
    await _refresh();
  }

  Future<void> deleteFolder(int folder, {int? moveTo}) async {
    await history.deleteFolder(folder, moveTo: moveTo);
    _undoable = null;
    if (_folder == folder && moveTo != null) _folder = moveTo;
    await _refresh();
  }

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
      return text == null ? null : LibraryBackup.parse(text);
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

  (Catalog, String?, String?, bool)? _lastTitleQuery;
  Future<({String name, bool fromContrast})?>? _lastTitle;

  Future<List<Match>> _matches(
    Recognition result,
    RecognitionModel engine, {
    String? file,
    PreviewFrame? frame,
    ScanProgress? onProgress,
  }) async {
    if (result.hits.isEmpty && result.title == null) return [];
    final catalog = this.catalog!;
    final matches = <Match>[];
    for (final hit in result.hits) {
      final editions = await catalog.editions(hit.index);
      if (editions.isNotEmpty) {
        matches.add(Match(editions, score: hit.score, corners: result.corners));
      }
    }
    if (engine == RecognitionModel.keypoints && matches.isNotEmpty) {
      final refined = await _preferKeypoints(
        matches,
        result.corners,
        file: file,
        frame: frame,
        onProgress: onProgress,
      );
      return _preferTitle(catalog, result, refined);
    }
    if (result.mtgHits.isEmpty) return _preferTitle(catalog, result, matches);
    final printings = await _mtgPrintings;
    final refined = Match.preferMtg(matches, [
      for (final hit in result.mtgHits)
        if (hit.score >= .25) printings[hit.index],
    ]);
    return _preferTitle(catalog, result, refined);
  }

  Future<List<Match>> _preferTitle(
    Catalog catalog,
    Recognition result,
    List<Match> visual,
  ) async {
    final title = result.title;
    if (title == null) return visual;
    final color = title.confidence >= .86 ? title.text : null;
    final contrast = title.contrast;
    final alternate =
        contrast != null && contrast.confidence >= .86 && contrast.text != color
        ? contrast.text
        : null;
    if (color == null && alternate == null) return visual;
    try {
      final allowOneEdit =
          title.confidence >= .89 && (visual.firstOrNull?.score ?? 0) < .74;
      final choice = await _matchTitle(
        catalog,
        visual,
        color,
        alternate,
        allowOneEdit,
      );
      if (choice == null) return visual;
      final (name: name, :fromContrast) = choice;
      final confidence = fromContrast ? contrast!.confidence : title.confidence;
      final matching = visual
          .where((m) => m.editions.first.name == name)
          .toList();
      if (matching.isEmpty &&
          (visual.firstOrNull?.score ?? 0) >= .82 &&
          confidence < .95) {
        return visual;
      }
      final printings = <String, Edition>{
        for (final match in matching)
          for (final card in match.editions) card.printingKey: card,
      };
      if (printings.isEmpty) {
        for (final card in await catalog.byName(name)) {
          printings[card.printingKey] = card;
        }
      }
      if (printings.isEmpty) return visual;
      return [
        Match(
          printings.values.toList(),
          score: confidence,
          corners: title.corners,
          fromTitle: true,
          titleOnly: matching.isEmpty,
          englishTitle: CardLanguage.matchesEnglishTitle(
            fromContrast ? alternate : color,
            name,
          ),
        ),
      ];
    } catch (_) {
      _lastTitle = null;
      return visual;
    }
  }

  Future<({String name, bool fromContrast})?> _matchTitle(
    Catalog catalog,
    List<Match> visual,
    String? color,
    String? contrast,
    bool allowOneEdit,
  ) async {
    for (final match in visual) {
      final name = match.editions.first.name;
      if (CardLanguage.matchesEnglishTitle(color, name)) {
        return (name: name, fromContrast: false);
      }
    }
    final query = (catalog, color, contrast, allowOneEdit);
    if (_lastTitleQuery != query || _lastTitle == null) {
      _lastTitleQuery = query;
      _lastTitle = _scanTitle(catalog, color, contrast, allowOneEdit);
    }
    return _lastTitle;
  }

  Future<({String name, bool fromContrast})?> _scanTitle(
    Catalog catalog,
    String? color,
    String? contrast,
    bool allowOneEdit,
  ) async {
    if (color != null) {
      final name = await catalog.nameForScannedTitle(
        color,
        allowOneEdit: contrast == null && allowOneEdit,
      );
      if (name != null) return (name: name, fromContrast: false);
    }
    if (contrast != null) {
      final name = await catalog.nameForScannedTitle(contrast);
      if (name != null) return (name: name, fromContrast: true);
      if (color != null && allowOneEdit) {
        final near = await catalog.nameForScannedTitle(
          color,
          allowOneEdit: true,
        );
        if (near != null) return (name: near, fromContrast: false);
      }
    }
    return null;
  }

  Future<List<Match>> _preferKeypoints(
    List<Match> matches,
    List<double> corners, {
    String? file,
    PreviewFrame? frame,
    Uint8List? photo,
    ScanProgress? onProgress,
  }) async {
    final choice = await refineKeypointScan(
      [for (final match in matches) match.editions],
      corners,
      file: file,
      frame: frame,
      photo: photo,
      onCompare: () => onProgress?.call(ScanStage.details, corners),
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
      Match(
        editions,
        score: matches.first.score,
        corners: picked.corners,
        fromTitle: picked.fromTitle,
        titleOnly: picked.titleOnly,
      ),
      for (final match in matches)
        if (!identical(match, picked)) match,
    ];
  }

  Future<List<Match>> recognize(
    String file, {
    RecognitionModel engine = RecognitionModel.oracle,
    ScanProgress? onProgress,
  }) async => _matches(
    await recognizeFile(catalog!, file, engine: engine, onProgress: onProgress),
    engine,
    file: file,
    onProgress: onProgress,
  );

  Future<Recognition> _inspectPreview({
    String? file,
    PreviewFrame? frame,
    required RecognitionModel engine,
    TrayArea? tray,
    bool outlineOnly = false,
    ScanProgress? onProgress,
    PreviewRecognizer? worker,
  }) => frame == null
      ? recognizeFile(
          catalog!,
          file!,
          engine: engine,
          tray: tray,
          outlineOnly: outlineOnly,
          onProgress: onProgress,
        )
      : recognizeCameraFrame(
          catalog!,
          frame,
          engine: engine,
          tray: tray,
          outlineOnly: outlineOnly,
          onProgress: onProgress,
          worker: worker,
        );

  Future<List<Match>> recognizeFrame(
    PreviewFrame frame, {
    RecognitionModel engine = RecognitionModel.oracle,
  }) async => _matches(
    await _inspectPreview(frame: frame, engine: engine),
    engine,
    frame: frame,
  );

  Future<List<double>> previewOutline({
    String? file,
    PreviewFrame? frame,
  }) async {
    final result = await _inspectPreview(
      file: file,
      frame: frame,
      engine: RecognitionModel.oracle,
      outlineOnly: true,
    );
    return result.corners;
  }

  Future<List<Match>> recognizePreview({
    String? file,
    PreviewFrame? frame,
    required RecognitionModel engine,
    TrayArea? tray,
    bool deferKeypoints = false,
    PreviewRecognizer? worker,
    required void Function(List<double>) onOutline,
    ScanProgress? onProgress,
  }) async {
    final result = await _inspectPreview(
      file: file,
      frame: frame,
      engine: engine,
      tray: tray,
      onProgress: onProgress,
      worker: worker,
    );
    final matches = await _matches(
      (
        hits: result.hits,
        mtgHits: result.mtgHits,
        corners: tray?.corners ?? result.corners,
        title: result.title,
      ),
      deferKeypoints && engine == RecognitionModel.keypoints
          ? RecognitionModel.oracle
          : engine,
      file: file,
      frame: frame,
      onProgress: onProgress,
    );
    final hit = matches.firstOrNull;
    onOutline(
      tray == null && hit?.fromTitle == true ? hit!.corners : result.corners,
    );
    return matches;
  }

  Future<List<Match>> refineTrayMatches(
    List<Match> matches, {
    String? file,
    PreviewFrame? frame,
    Uint8List? photo,
    ScanProgress? onProgress,
  }) => _preferKeypoints(
    matches,
    matches.first.corners,
    file: file,
    frame: frame,
    photo: photo,
    onProgress: onProgress,
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
    final locations = state.holdings[card.name] ?? const <int, int>{};
    emit(
      LibraryState(
        catalog: catalog,
        error: state.error,
        folder: folder,
        holdings: review != null
            ? state.holdings
            : {
                ...state.holdings,
                card.name: {...locations, folder: (locations[folder] ?? 0) + 1},
              },
        flags: state.flags,
        covers: review != null
            ? state.covers
            : {
                ...state.covers,
                folder: [
                  card,
                  ...?state.covers[folder]
                      ?.where((e) => e.name != card.name)
                      .take(2),
                ],
              },
        pendingByFolder: review == null
            ? state.pendingByFolder
            : {
                ...state.pendingByFolder,
                folder: (state.pendingByFolder[folder] ?? 0) + 1,
              },
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

  Future<CardMove> moveCards(int to, Edition card, int quantity) =>
      _finishMove(history.moveCards(state.folder, to, card, quantity));

  Future<CardMove> moveToNewCollection(
    String name,
    Edition card,
    int quantity,
  ) => _finishMove(
    history.moveToNewCollection(state.folder, name, card, quantity),
  );

  Future<CardMove> _finishMove(Future<CardMove> operation) async {
    final move = await operation;
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

  Future<void> replace(
    ScanEntry entry,
    Edition card, {
    ScanReview? review,
  }) async {
    _undoable = null;
    final folder = state.folder;
    await history.replace(folder, entry.sequence, card, review: review);
    await _refresh();
  }

  Future<void> setFlag(Edition card, bool value) async {
    await history.setFlag(state.folder, card, value);
    await _refresh();
  }

  Future<void> resolvePrinting(
    int folder,
    Edition unknown,
    Edition selected, {
    int? sequence,
  }) async {
    await history.resolvePrinting(
      folder,
      unknown,
      selected,
      sequence: sequence,
    );
    _undoable = null;
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

  Future<String> export({
    bool flaggedOnly = false,
    bool includePending = true,
  }) async {
    final base = catalog;
    final rows = await history.list(
      folder: state.folder,
      flaggedOnly: flaggedOnly,
      includePending: includePending,
    );
    final byPrinting = <String, CardCount>{};
    for (final row in rows) {
      final front = (await base!.front(row.card))
          .withLanguage(row.card.language)
          .withFoil(row.card.foil);
      final card = row.card.needsPrinting ? front.withoutPrinting() : front;
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
