import 'package:flutter_bloc/flutter_bloc.dart';

import 'model.dart';
import 'data/catalog.dart';
import 'scan_decision.dart';

// Два кадра с одинаковыми кандидатами. Пропуск кадра не снимает защиту от дубля.
class ScanGate {
  String? _candidate;
  Edition? _last;
  Set<String> _seenNames = {};

  void clearCandidate() => _candidate = null;
  void saved(Edition card, {Iterable<String> observedNames = const []}) {
    _last = card;
    _seenNames = {card.name, ...observedNames};
    clearCandidate();
  }

  Edition? accept(List<Match> matches, {bool manual = false}) {
    if (matches.isEmpty) {
      clearCandidate();
      return null;
    }
    final best = matches.first;
    final card = best.editions.first;
    if (manual) {
      return best.editions.where((e) => e.id == _last?.id).firstOrNull ?? card;
    }
    final candidates = closeMatches(matches).map((m) => m.editions.first);
    if (best.score < .60 ||
        candidates.any((e) => _seenNames.contains(e.name)) ||
        _sameCard(card, _last)) {
      clearCandidate();
      return null;
    }
    final key = (candidates.map((e) => e.id).toList()..sort()).join('\n');
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

enum ScanMode { manual, automatic }

typedef ScanSession = ({
  ScanMode mode,
  BatchSettings batch,
  int? lastScan,
  bool showGuide,
  Set<String> targets,
});

class ScanCubit extends Cubit<ScanSession> {
  ScanCubit()
    : super((
        mode: ScanMode.manual,
        batch: const BatchSettings(),
        lastScan: null,
        showGuide: true,
        targets: const {},
      ));
  final gate = ScanGate();
  bool _force = false;
  void toggle() {
    _force = false;
    gate.clearCandidate();
    emit((
      mode: state.mode == ScanMode.manual
          ? ScanMode.automatic
          : ScanMode.manual,
      batch: state.batch,
      lastScan: state.lastScan,
      showGuide: state.showGuide,
      targets: state.targets,
    ));
  }

  void configure(BatchSettings value) {
    cancelFrame();
    emit((
      mode: state.mode,
      batch: value,
      lastScan: state.lastScan,
      showGuide: state.showGuide,
      targets: state.targets,
    ));
  }

  void setGuide(bool visible) => emit((
    mode: state.mode,
    batch: state.batch,
    lastScan: state.lastScan,
    showGuide: visible,
    targets: state.targets,
  ));

  void addTarget(String name) {
    if (state.targets.contains(name)) return;
    _setTargets({...state.targets, name});
  }

  void removeTarget(String name) {
    if (!state.targets.contains(name)) return;
    _setTargets({...state.targets}..remove(name));
  }

  void _setTargets(Set<String> targets) => emit((
    mode: state.mode,
    batch: state.batch,
    lastScan: state.lastScan,
    showGuide: state.showGuide,
    targets: Set.unmodifiable(targets),
  ));

  void recorded(int seq, Edition card, List<Match> matches) {
    gate.saved(
      card,
      observedNames: closeMatches(matches).map((m) => m.editions.first.name),
    );
    emit((
      mode: state.mode,
      batch: state.batch,
      lastScan: seq,
      showGuide: state.showGuide,
      targets: state.targets,
    ));
  }

  void undone() {
    cancelFrame();
    emit((
      mode: state.mode,
      batch: state.batch,
      lastScan: null,
      showGuide: state.showGuide,
      targets: state.targets,
    ));
  }

  void shutter() => _force = true;
  void cancelFrame() {
    _force = false;
    gate.clearCandidate();
  }

  Edition? evaluate(List<Match> matches) {
    final manual = _force;
    _force = false;
    return gate.accept(matches, manual: manual);
  }
}
