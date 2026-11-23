import 'dart:js_interop';

import 'catalog.dart';
import 'frame.dart';
import 'recognition_result.dart';

@JS('kartoved.scan')
external JSPromise<_ScanResult> _scan(String file);

extension type _ScanResult(JSObject _) implements JSObject {
  external JSArray<_Hit> get hits;
  external JSArray<JSNumber> get corners;
}

extension type _Hit(JSObject _) implements JSObject {
  external int get index;
  external double get score;
}

Future<Recognition> recognizeFile(Catalog catalog, String file) async {
  final result = await _scan(file).toDart;
  return (
    hits: [
      for (final hit in result.hits.toDart)
        (index: hit.index, score: hit.score),
    ],
    corners: [
      for (final coordinate in result.corners.toDart) coordinate.toDartDouble,
    ],
  );
}

Future<Recognition> recognizeCameraFrame(Catalog catalog, PreviewFrame frame) =>
    throw UnsupportedError('В браузере используются снимки с камеры');
