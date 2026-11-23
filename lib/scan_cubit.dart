import 'package:flutter_bloc/flutter_bloc.dart';

import 'model.dart';
import 'data/catalog.dart';

// Два уверенных совпадения подряд. Пропуск кадра не снимает защиту от дубля.
class ScanGate {
  String? _candidate;
  Edition? _last;

  void clearCandidate() => _candidate = null;
  void saved(Edition card) {
    _last = card;
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
    if (best.score < .75 || _uncertain(matches) || _sameCard(card, _last)) {
      clearCandidate();
      return null;
    }
    final stable = _candidate == card.id;
    _candidate = card.id;
    return stable ? card : null;
  }

  bool _uncertain(List<Match> matches) =>
      matches.length > 1 && matches[0].score - matches[1].score < .05;
  bool _sameCard(Edition card, Edition? previous) =>
      previous != null &&
      (card.name == previous.name ||
          card.id.replaceFirst(RegExp(r'-1$'), '') ==
              previous.id.replaceFirst(RegExp(r'-1$'), ''));
}

enum ScanMode { manual, automatic }

class ScanCubit extends Cubit<ScanMode> {
  ScanCubit() : super(ScanMode.manual);
  final gate = ScanGate();
  bool _force = false;
  void toggle() {
    _force = false;
    gate.clearCandidate();
    emit(state == ScanMode.manual ? ScanMode.automatic : ScanMode.manual);
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
