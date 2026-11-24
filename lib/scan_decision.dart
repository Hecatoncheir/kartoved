import 'data/catalog.dart';
import 'data/language.dart';
import 'data/review.dart';
import 'data/recognition_result.dart';
import 'model.dart';

class BatchSettings {
  const BatchSettings({this.language, this.setCode});
  final String? language, setCode;
  bool get active => language != null || setCode != null;
  String get label =>
      [setCode, language].nonNulls.map((v) => v.toUpperCase()).join(' · ');
  bool accepts(Edition card) =>
      (language == null || card.language == language) &&
      (setCode == null || card.set == setCode);
}

List<Match> closeMatches(List<Match> matches) => matches
    .where((m) => matches.first.score - m.score < nearMatchWindow)
    .toList();

typedef ScanDecision = ({Edition card, ScanReview? review});

Edition selectScannedEdition(List<Edition> evidence, BatchSettings batch) {
  final matching = evidence.where(batch.accepts).toList();
  final options = matching.isEmpty ? evidence : matching;
  final languages = options.map((card) => card.language).toSet();
  return CardLanguage.select(
    options,
    languages.length == 1 ? languages.single : null,
  );
}

ScanDecision decideScan(
  List<Match> matches,
  List<Edition> evidence,
  BatchSettings batch,
) {
  final close = closeMatches(matches);
  final filtered = {
    for (final e in evidence.where(batch.accepts)) e.printingKey: e,
  };
  final choices = filtered.values;
  final reason = switch (choices.length) {
    0 => ReviewReason.batch,
    _ when matches.first.score < .75 || close.length > 1 =>
      ReviewReason.artwork,
    _
        when choices.map((e) => e.language).toSet().length > 1 ||
            choices.first.language == 'und' =>
      ReviewReason.language,
    1 => null,
    _ => ReviewReason.printing,
  };
  final card = choices.firstOrNull ?? evidence.first;
  if (reason == null) return (card: card, review: null);
  final options = {
    card.printingKey: card,
    ...filtered,
    for (final m in close)
      for (final e in m.editions) e.printingKey: e,
  };
  return (
    card: card,
    review: ScanReview(
      reason,
      options.values.toList(),
      batchLabel: batch.label,
    ),
  );
}
