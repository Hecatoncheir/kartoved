import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'frame.dart';
import 'oracle.dart';

Recognition _photo(({String directory, String file}) input) =>
    identifyPhoto(input.directory, input.file);
Recognition _preview(({String directory, PreviewFrame frame}) input) =>
    identifyImage(input.directory, frameImage(input.frame));

Future<Recognition> recognizeFile(Catalog catalog, String file) =>
    compute(_photo, (directory: catalog.directory.path, file: file));
Future<Recognition> recognizeCameraFrame(Catalog catalog, PreviewFrame frame) =>
    compute(_preview, (directory: catalog.directory.path, frame: frame));
