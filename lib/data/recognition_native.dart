import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'frame.dart';
import 'oracle.dart';
import 'tray.dart';

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

Recognition _photo(
  ({String directory, String file, _Models models, TrayArea? tray}) input,
) => identifyPhoto(
  input.directory,
  input.file,
  mtgGraph: input.models.mtg,
  poseGraph: input.models.pose,
  tray: input.tray,
);

Recognition _preview(
  ({String directory, PreviewFrame frame, _Models models, TrayArea? tray})
  input,
) => identifyImage(
  input.directory,
  frameImage(input.frame),
  mtgGraph: input.models.mtg,
  poseGraph: input.models.pose,
  tray: input.tray,
);

Future<Recognition> recognizeFile(
  Catalog catalog,
  String file, [
  RecognitionModel engine = RecognitionModel.oracle,
  TrayArea? tray,
]) async => compute(_photo, (
  directory: catalog.directory.path,
  file: file,
  models: await _graphs(engine),
  tray: tray,
));

Future<Recognition> recognizeCameraFrame(
  Catalog catalog,
  PreviewFrame frame, [
  RecognitionModel engine = RecognitionModel.oracle,
  TrayArea? tray,
]) async => compute(_preview, (
  directory: catalog.directory.path,
  frame: frame,
  models: await _graphs(engine),
  tray: tray,
));
