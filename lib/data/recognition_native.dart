import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'frame.dart';
import 'oracle.dart';

final _mtgGraph = _loadGraph('recognize');
final _poseGraph = _loadGraph('pose');

Future<Uint8List> _loadGraph(String name) async {
  final data = await rootBundle.load('$mtgIdentificationAssets/$name.onnx');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

typedef _Models = ({Uint8List? mtg, Uint8List? pose});

Future<_Models> _graphs(RecognitionModel engine) async => (
  mtg:
      engine == RecognitionModel.mtgIdentification ||
          engine == RecognitionModel.mtgStandalone
      ? await _mtgGraph
      : null,
  pose: engine == RecognitionModel.mtgStandalone ? await _poseGraph : null,
);

Recognition _photo(({String directory, String file, _Models models}) input) =>
    identifyPhoto(
      input.directory,
      input.file,
      mtgGraph: input.models.mtg,
      poseGraph: input.models.pose,
    );

Recognition _preview(
  ({String directory, PreviewFrame frame, _Models models}) input,
) => identifyImage(
  input.directory,
  frameImage(input.frame),
  mtgGraph: input.models.mtg,
  poseGraph: input.models.pose,
);

Future<Recognition> recognizeFile(
  Catalog catalog,
  String file, [
  RecognitionModel engine = RecognitionModel.oracle,
]) async => compute(_photo, (
  directory: catalog.directory.path,
  file: file,
  models: await _graphs(engine),
));

Future<Recognition> recognizeCameraFrame(
  Catalog catalog,
  PreviewFrame frame, [
  RecognitionModel engine = RecognitionModel.oracle,
]) async => compute(_preview, (
  directory: catalog.directory.path,
  frame: frame,
  models: await _graphs(engine),
));
