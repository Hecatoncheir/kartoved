typedef Hit = ({int index, double score});
typedef TitleCandidate = ({String text, double confidence});
typedef TitleRead = ({
  String text,
  double confidence,
  List<double> corners,
  TitleCandidate? contrast,
});
typedef Recognition = ({
  List<Hit> hits,
  List<Hit> mtgHits,
  List<double> corners,
  TitleRead? title,
});

const mtgIdentificationAssets = 'assets/mtg_identification';
const nearMatchWindow = .05;

enum RecognitionModel {
  oracle(.60),
  mtgIdentification(.60),
  keypoints(.60);

  const RecognitionModel(this.minimumScore);
  final double minimumScore;

  static RecognitionModel fromName(String? name) => switch (name) {
    'mtgIdentification' => mtgIdentification,
    'keypoints' => keypoints,
    _ => oracle,
  };
}
