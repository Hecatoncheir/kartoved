typedef Hit = ({int index, double score});
typedef Recognition = ({
  List<Hit> hits,
  List<Hit> mtgHits,
  List<double> corners,
});

const mtgIdentificationAssets = 'assets/mtg_identification';
const nearMatchWindow = .05;

enum RecognitionModel {
  oracle('Oracle', .60),
  mtgIdentification('MTG Card Identification + Oracle', .60),
  mtgStandalone('MTG Card Identification (без Oracle)', .34);

  const RecognitionModel(this.label, this.minimumScore);
  final String label;
  final double minimumScore;

  static RecognitionModel fromName(String? name) => switch (name) {
    'mtgIdentification' => mtgIdentification,
    'mtgStandalone' => mtgStandalone,
    _ => oracle,
  };
}

// Косинусная близость проверяется по разным иллюстрациям после объединения
// результатов всех поворотов. Пограничный результат не записывается в альбом.
Hit? standaloneMtgHit(List<Hit> hits) {
  final best = hits.firstOrNull;
  if (best == null ||
      best.score < RecognitionModel.mtgStandalone.minimumScore) {
    return null;
  }
  final rival = hits.skip(1).firstOrNull;
  return rival == null || best.score - rival.score >= .06 ? best : null;
}
