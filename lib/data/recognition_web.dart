import 'dart:js_interop';

import 'catalog.dart';
import 'frame.dart';
import 'recognition_result.dart';
import 'scan_progress.dart';
import 'tray.dart';

Future<void> warmTitleRecognition() async {}

class PreviewRecognizer {
  static Future<PreviewRecognizer> start(
    Catalog catalog,
    RecognitionModel engine,
  ) => throw UnsupportedError('Прогрев кадров доступен на Android');

  void close() {}
}

@JS('kartoved.scan')
external JSPromise<_ScanResult> _scan(
  String file,
  String engine,
  JSArray<JSNumber>? tray,
  bool outlineOnly,
  JSFunction? progress,
);

extension type _ScanResult(JSObject _) implements JSObject {
  external JSArray<_Hit> get hits;
  external JSArray<_Hit>? get mtgHits;
  external JSArray<JSNumber> get corners;
}

extension type _Hit(JSObject _) implements JSObject {
  external int get index;
  external double get score;
}

Future<Recognition> recognizeFile(
  Catalog catalog,
  String file, {
  RecognitionModel engine = RecognitionModel.oracle,
  TrayArea? tray,
  bool outlineOnly = false,
  ScanProgress? onProgress,
}) async {
  void report(JSString stage, JSArray<JSNumber> card) => onProgress?.call(
    stage.toDart == 'card' ? ScanStage.card : ScanStage.artwork,
    [for (final value in card.toDart) value.toDartDouble],
  );

  final result = await _scan(
    file,
    engine.name,
    tray?.bounds.map((p) => p.toJS).toList().toJS,
    outlineOnly,
    onProgress == null ? null : report.toJS,
  ).toDart;
  return (
    title: null,
    hits: [
      for (final hit in result.hits.toDart)
        (index: hit.index, score: hit.score),
    ],
    mtgHits: [
      for (final hit in result.mtgHits?.toDart ?? const <_Hit>[])
        (index: hit.index, score: hit.score),
    ],
    corners: [
      for (final coordinate in result.corners.toDart) coordinate.toDartDouble,
    ],
  );
}

Future<Recognition> recognizeCameraFrame(
  Catalog catalog,
  PreviewFrame frame, {
  RecognitionModel engine = RecognitionModel.oracle,
  TrayArea? tray,
  bool outlineOnly = false,
  ScanProgress? onProgress,
  PreviewRecognizer? worker,
}) => throw UnsupportedError('В браузере используются снимки с камеры');
