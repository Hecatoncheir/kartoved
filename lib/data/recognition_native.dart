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

Recognition _recognize(_Input input, [OracleRecognizer? recognizer]) {
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
      recognizer: recognizer,
    );
  } finally {
    if (recognizer == null) port?.send(null);
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
  PreviewRecognizer? worker,
}) =>
    worker?.recognize(frame, tray: tray, onProgress: onProgress) ??
    _run(
      catalog,
      frame: frame,
      engine: engine,
      tray: tray,
      outlineOnly: outlineOnly,
      onProgress: onProgress,
    );

typedef _PreviewRequest = ({PreviewFrame frame, TrayArea? tray, bool progress});
typedef _PreviewSetup = ({
  String directory,
  Uint8List? mtgGraph,
  PaddleTitleAssets? titleAssets,
  SendPort events,
});

// В главном изоляте остаются камера и каталог, сессии ONNX принадлежат обработчику.
class PreviewRecognizer {
  PreviewRecognizer._() {
    _events.listen(_receive);
  }

  final _events = ReceivePort();
  final _ready = Completer<void>();
  Completer<Recognition>? _response;
  ScanProgress? _onProgress;
  SendPort? _commands;

  static Future<PreviewRecognizer> start(
    Catalog catalog,
    RecognitionModel engine,
  ) async {
    final (mtgGraph, titleAssets) = await (
      engine == RecognitionModel.mtgIdentification
          ? _mtgGraph
          : Future<Uint8List?>.value(),
      _paddle ??= _loadPaddle(),
    ).wait;
    final worker = PreviewRecognizer._();
    final events = worker._events.sendPort;
    unawaited(
      Isolate.spawn(
        _recognizePreviews,
        (
          directory: catalog.directory.path,
          mtgGraph: mtgGraph,
          titleAssets: titleAssets,
          events: events,
        ),
        onError: events,
        onExit: events,
        debugName: 'kartoved-preview',
      ).then<void>((_) {}, onError: worker._fail),
    );
    await worker._ready.future;
    return worker;
  }

  Future<Recognition> recognize(
    PreviewFrame frame, {
    TrayArea? tray,
    ScanProgress? onProgress,
  }) async {
    final commands = _commands;
    if (commands == null || _response != null) {
      throw StateError('Обработчик кадров недоступен');
    }
    final response = _response = Completer<Recognition>();
    _onProgress = onProgress;
    try {
      commands.send((frame: frame, tray: tray, progress: onProgress != null));
      return await response.future;
    } finally {
      _response = null;
      _onProgress = null;
    }
  }

  void close() {
    _commands?.send(null);
    _commands = null;
  }

  void _receive(Object? message) {
    switch (message) {
      case final SendPort commands:
        _commands = commands;
        _ready.complete();
      case (final ScanStage stage, final List<double> corners):
        _onProgress?.call(stage, corners);
      case final Recognition result:
        _response?.complete(result);
      case [final String error, final String trace]:
        _fail(StateError(error), StackTrace.fromString(trace));
      case null:
        _fail(StateError('Обработчик кадров завершён'), StackTrace.current);
    }
  }

  void _fail(Object error, StackTrace trace) {
    _commands = null;
    _events.close();
    if (!_ready.isCompleted) _ready.completeError(error, trace);
    final response = _response;
    if (response != null && !response.isCompleted) {
      response.completeError(error, trace);
    }
  }
}

Future<void> _recognizePreviews(_PreviewSetup setup) async {
  final (:directory, :mtgGraph, :titleAssets, :events) = setup;
  final recognizer = OracleRecognizer(directory);
  final commands = ReceivePort();
  try {
    recognizer.warm(mtgGraph: mtgGraph, titleAssets: titleAssets);
    events.send(commands.sendPort);
    await for (final request in commands) {
      if (request is! _PreviewRequest) break;
      final result = _recognize((
        directory: directory,
        file: null,
        frame: request.frame,
        mtgGraph: mtgGraph,
        titleAssets: titleAssets,
        tray: request.tray,
        outlineOnly: false,
        updates: request.progress ? events : null,
      ), recognizer);
      events.send(result);
    }
  } finally {
    commands.close();
    recognizer.close();
  }
}

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
