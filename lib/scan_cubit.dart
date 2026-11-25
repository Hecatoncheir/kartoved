import 'package:flutter_bloc/flutter_bloc.dart';

import 'model.dart';
import 'data/catalog.dart';
import 'data/recognition_result.dart';
import 'scan_decision.dart';
import 'scan_processing.dart';

// Два кадра с одинаковыми кандидатами. Пропуск кадра не снимает защиту от дубля.
class ScanGate {
  String? _candidate;
  Edition? _last;
  Set<String> _seenNames = {};

  bool get awaitingConfirmation => _candidate != null;

  void clearCandidate() => _candidate = null;
  void saved(Edition card, {Iterable<String> observedNames = const []}) {
    _last = card;
    _seenNames = {card.name, ...observedNames};
    clearCandidate();
  }

  Edition? accept(
    List<Match> matches, {
    bool manual = false,
    double minimumScore = .60,
  }) {
    if (matches.isEmpty) {
      clearCandidate();
      return null;
    }
    final best = matches.first;
    final card = best.editions.first;
    if (manual) {
      return best.editions.where((e) => e.id == _last?.id).firstOrNull ?? card;
    }
    final close = closeMatches(matches);
    final candidates = close.map((m) => m.editions.first);
    if (best.score < minimumScore ||
        candidates.any((e) => _seenNames.contains(e.name)) ||
        _sameCard(card, _last)) {
      clearCandidate();
      return null;
    }
    final key =
        (close
                .map(
                  (m) =>
                      m.fromTitle ? m.editions.first.name : m.editions.first.id,
                )
                .toList()
              ..sort())
            .join('\n');
    final stable = _candidate == key;
    _candidate = key;
    return stable ? card : null;
  }

  bool _sameCard(Edition card, Edition? previous) =>
      previous != null &&
      (card.name == previous.name ||
          card.id.replaceFirst(RegExp(r'-1$'), '') ==
              previous.id.replaceFirst(RegExp(r'-1$'), ''));
}

enum ScanMode {
  manual,
  automatic,
  tray;

  bool get isAutomatic => this != manual;
}

class ScanSession {
  const ScanSession({
    this.mode = ScanMode.manual,
    this.batch = const BatchSettings(),
    this.lastScan,
    this.showGuide = true,
    this.targets = const {},
    this.model = RecognitionModel.oracle,
  });

  final ScanMode mode;
  final BatchSettings batch;
  final int? lastScan;
  final bool showGuide;
  final Set<String> targets;
  final RecognitionModel model;

  ScanSession copyWith({
    ScanMode? mode,
    BatchSettings? batch,
    int? lastScan,
    bool clearLastScan = false,
    bool? showGuide,
    Set<String>? targets,
    RecognitionModel? model,
  }) => ScanSession(
    mode: mode ?? this.mode,
    batch: batch ?? this.batch,
    lastScan: clearLastScan ? null : lastScan ?? this.lastScan,
    showGuide: showGuide ?? this.showGuide,
    targets: targets ?? this.targets,
    model: model ?? this.model,
  );
}

class ScanCubit extends Cubit<ScanSession> {
  ScanCubit() : super(const ScanSession());
  final gate = ScanGate();
  bool _force = false;
  void toggle() =>
      setMode(state.mode.isAutomatic ? ScanMode.manual : ScanMode.automatic);

  void setMode(ScanMode mode) {
    if (state.mode == mode) return;
    cancelFrame();
    emit(state.copyWith(mode: mode));
  }

  void configure(BatchSettings value) {
    cancelFrame();
    emit(state.copyWith(batch: value));
  }

  void setGuide(bool visible) => emit(state.copyWith(showGuide: visible));

  void setModel(RecognitionModel model) {
    if (state.model == model) return;
    cancelFrame();
    emit(state.copyWith(model: model));
  }

  void addTarget(String name) {
    if (state.targets.contains(name)) return;
    _setTargets({...state.targets, name});
  }

  void removeTarget(String name) {
    if (!state.targets.contains(name)) return;
    _setTargets({...state.targets}..remove(name));
  }

  void _setTargets(Set<String> targets) =>
      emit(state.copyWith(targets: Set.unmodifiable(targets)));

  Future<int> save(
    AppModel library,
    PreparedScan scan, {
    ScanEntry? previous,
  }) async {
    final (:card, :review) = scan.decision;
    final int sequence;
    if (previous == null) {
      sequence = await library.save(card, review: review);
    } else {
      await library.replace(previous, card, review: review);
      sequence = previous.sequence;
    }
    if (!isClosed) recorded(sequence, card, scan.matches);
    return sequence;
  }

  void recorded(int seq, Edition card, List<Match> matches) {
    gate.saved(
      card,
      observedNames: closeMatches(matches).map((m) => m.editions.first.name),
    );
    emit(state.copyWith(lastScan: seq));
  }

  void undone() {
    cancelFrame();
    emit(state.copyWith(clearLastScan: true));
  }

  void shutter() => _force = true;
  void cancelFrame() {
    _force = false;
    gate.clearCandidate();
  }

  Edition? evaluate(List<Match> matches) {
    final manual = _force;
    _force = false;
    return gate.accept(
      matches,
      manual: manual,
      minimumScore: state.model.minimumScore,
    );
  }
}
