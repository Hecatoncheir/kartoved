import 'dart:async';

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
    bool fast = false,
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
    if (fast && !best.titleOnly && best.score >= .90 && close.length == 1) {
      return card;
    }
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

enum ScanOption {
  essentials('Только необходимое'),
  consecutive('Одинаковые подряд');

  const ScanOption(this.label);
  final String label;
}

class ScanSession {
  const ScanSession({
    this.mode = ScanMode.manual,
    this.batch = const BatchSettings(),
    this.lastScan,
    this.lastAdded,
    this.showGuide = true,
    this.targets = const {},
    this.model = RecognitionModel.oracle,
    this.options = const {},
    this.repeatSeconds = 0,
  });

  final ScanMode mode;
  final BatchSettings batch;
  final int? lastScan;
  final int? lastAdded;
  final bool showGuide;
  final Set<String> targets;
  final RecognitionModel model;
  final Set<ScanOption> options;
  final int repeatSeconds;

  ScanSession copyWith({
    ScanMode? mode,
    BatchSettings? batch,
    int? lastScan,
    int? lastAdded,
    bool clearLastScan = false,
    bool? showGuide,
    Set<String>? targets,
    RecognitionModel? model,
    Set<ScanOption>? options,
    int? repeatSeconds,
  }) => ScanSession(
    mode: mode ?? this.mode,
    batch: batch ?? this.batch,
    lastScan: clearLastScan ? null : lastScan ?? this.lastScan,
    lastAdded: clearLastScan ? null : lastAdded ?? this.lastAdded,
    showGuide: showGuide ?? this.showGuide,
    targets: targets ?? this.targets,
    model: model ?? this.model,
    options: options ?? this.options,
    repeatSeconds: repeatSeconds ?? this.repeatSeconds,
  );
}

class ScanCubit extends Cubit<ScanSession> {
  ScanCubit() : super(const ScanSession());
  final gate = ScanGate();
  Timer? _countdown;
  Edition? _repeatCard;
  bool get repeatReady => _repeatCard != null && state.repeatSeconds == 0;

  Edition? repeatFor(List<Match> matches) {
    if (_force || !repeatReady || matches.isEmpty) return null;
    final best = matches.first;
    if (best.score < .75 || best.editions.first.name != _repeatCard!.name) {
      return null;
    }
    return _repeatCard;
  }

  void stopRepeats() {
    _countdown?.cancel();
    _repeatCard = null;
    if (state.repeatSeconds != 0) emit(state.copyWith(repeatSeconds: 0));
  }

  void setOption(ScanOption option, bool enabled) {
    if (state.options.contains(option) == enabled) return;
    cancelFrame();
    if (option == ScanOption.consecutive) stopRepeats();
    final options = {...state.options};
    if (enabled) {
      options.add(option);
    } else {
      options.remove(option);
    }
    emit(state.copyWith(options: Set.unmodifiable(options)));
  }

  bool _force = false;
  bool get needsFullFrame => _force || gate.awaitingConfirmation;
  void toggle() =>
      setMode(state.mode.isAutomatic ? ScanMode.manual : ScanMode.automatic);

  void setMode(ScanMode mode) {
    if (state.mode == mode) return;
    stopRepeats();
    cancelFrame();
    emit(state.copyWith(mode: mode));
  }

  void configure(BatchSettings value) {
    stopRepeats();
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
    bool trayScan = false,
  }) async {
    final (:card, :review) = scan.decision;
    final int sequence;
    if (previous == null) {
      sequence = await library.save(card, review: review);
    } else {
      await library.replace(previous, card, review: review);
      sequence = previous.sequence;
    }
    if (!isClosed) {
      recorded(
        sequence,
        card,
        scan.matches,
        added: previous == null,
        repeatable: trayScan && previous == null && review == null,
      );
    }
    return sequence;
  }

  void recorded(
    int seq,
    Edition card,
    List<Match> matches, {
    bool added = true,
    bool repeatable = false,
  }) {
    gate.saved(
      card,
      observedNames: closeMatches(matches).map((m) => m.editions.first.name),
    );
    _countdown?.cancel();
    final repeat =
        repeatable &&
        state.mode == ScanMode.tray &&
        state.options.contains(ScanOption.consecutive);
    _repeatCard = repeat ? card : null;
    emit(
      state.copyWith(
        lastScan: seq,
        lastAdded: added ? seq : null,
        repeatSeconds: repeat ? 2 : 0,
      ),
    );
    if (repeat) {
      _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
        final left = 2 - timer.tick;
        if (left <= 0) timer.cancel();
        emit(state.copyWith(repeatSeconds: left.clamp(0, 2)));
      });
    }
  }

  void undone() {
    stopRepeats();
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
      fast:
          state.options.contains(ScanOption.essentials) && !state.batch.active,
      minimumScore: state.model.minimumScore,
    );
  }

  @override
  Future<void> close() {
    _countdown?.cancel();
    return super.close();
  }
}
