import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'frame.dart';
import 'oracle.dart';
import 'paddle_title.dart';
import 'scan_progress.dart';
import 'tray.dart';

final _mtgGraph = _loadMtgGraph();
Future<PaddleTitleAssets?>? _paddle;

Future<PaddleTitleAssets?> _loadPaddle() async {
  if (!Platform.isAndroid) return null;
  try {
    final (data, dictionary) = await (
      rootBundle.load('$paddleTitleAssets/title.onnx'),
      rootBundle.loadString('$paddleTitleAssets/alphabet.json'),
    ).wait;
    return (
      graph: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      alphabet: (jsonDecode(dictionary) as List).cast<String>(),
    );
  } catch (_) {
    return null;
  }
}

Future<void> warmTitleRecognition() async {
  await (_paddle ??= _loadPaddle());
}

Future<Uint8List> _loadMtgGraph() async {
  final data = await rootBundle.load('$mtgIdentificationAssets/recognize.onnx');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

typedef _Input = ({
  String directory,
  String? file,
  PreviewFrame? frame,
  Uint8List? mtgGraph,
  PaddleTitleAssets? titleAssets,
  TrayArea? tray,
  bool outlineOnly,
  SendPort? updates,
});

Recognition _recognize(_Input input) {
  final port = input.updates;
  final ScanProgress? publish = port == null
      ? null
      : (stage, card) => port.send((stage, card));
  try {
    if (input.file case final file?) {
      return identifyPhoto(
        input.directory,
        file,
        mtgGraph: input.mtgGraph,
        titleAssets: input.titleAssets,
        tray: input.tray,
        outlineOnly: input.outlineOnly,
        onProgress: publish,
      );
    }
    final maxSide = switch ((input.titleAssets, input.tray)) {
      (null, _) => 640,
      (_, null) => 1080,
      _ => 960,
    };
    return identifyImage(
      input.directory,
      frameImage(input.frame!, maxSide: maxSide),
      mtgGraph: input.mtgGraph,
      titleAssets: input.titleAssets,
      tray: input.tray,
      outlineOnly: input.outlineOnly,
      onProgress: publish,
    );
  } finally {
    port?.send(null);
  }
}

Future<Recognition> recognizeFile(
  Catalog catalog,
  String file, {
  RecognitionModel engine = RecognitionModel.oracle,
  TrayArea? tray,
  bool outlineOnly = false,
  ScanProgress? onProgress,
}) => _run(
  catalog,
  file: file,
  engine: engine,
  tray: tray,
  outlineOnly: outlineOnly,
  onProgress: onProgress,
);

Future<Recognition> recognizeCameraFrame(
  Catalog catalog,
  PreviewFrame frame, {
  RecognitionModel engine = RecognitionModel.oracle,
  TrayArea? tray,
  bool outlineOnly = false,
  ScanProgress? onProgress,
}) => _run(
  catalog,
  frame: frame,
  engine: engine,
  tray: tray,
  outlineOnly: outlineOnly,
  onProgress: onProgress,
);

Future<Recognition> _run(
  Catalog catalog, {
  String? file,
  PreviewFrame? frame,
  required RecognitionModel engine,
  required TrayArea? tray,
  required bool outlineOnly,
  required ScanProgress? onProgress,
}) async {
  final mtgGraph = engine == RecognitionModel.mtgIdentification
      ? await _mtgGraph
      : null;
  final titleAssets = outlineOnly ? null : await (_paddle ??= _loadPaddle());
  final updates = onProgress == null ? null : ReceivePort();
  final delivered = Completer<void>();
  updates?.listen((message) {
    if (message case (final ScanStage stage, final List<double> card)) {
      onProgress?.call(stage, card);
    } else if (message == null) {
      delivered.complete();
    }
  });
  try {
    final result = await compute(_recognize, (
      directory: catalog.directory.path,
      file: file,
      frame: frame,
      mtgGraph: mtgGraph,
      titleAssets: titleAssets,
      tray: tray,
      outlineOnly: outlineOnly,
      updates: updates?.sendPort,
    ));
    if (updates != null) await delivered.future;
    return result;
  } finally {
    updates?.close();
  }
}
