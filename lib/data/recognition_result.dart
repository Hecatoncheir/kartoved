typedef Hit = ({int index, double score});
typedef TitleRead = ({String text, double confidence, List<double> corners});
typedef Recognition = ({
  List<Hit> hits,
  List<Hit> mtgHits,
  List<double> corners,
  TitleRead? title,
});

const mtgIdentificationAssets = 'assets/mtg_identification';
const nearMatchWindow = .05;

enum RecognitionModel {
  oracle('Oracle', .60),
  mtgIdentification('MTG Card Identification + Oracle', .60),
  keypoints('Ключевые точки + Oracle', .60);

  const RecognitionModel(this.label, this.minimumScore);
  final String label;
  final double minimumScore;

  static RecognitionModel fromName(String? name) => switch (name) {
    'mtgIdentification' => mtgIdentification,
    'keypoints' => keypoints,
    _ => oracle,
  };
}
