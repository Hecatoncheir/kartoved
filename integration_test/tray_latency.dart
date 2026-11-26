import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:kartoved/data/android.dart';
import 'package:kartoved/data/frame.dart';
import 'package:kartoved/data/recognition.dart';
import 'package:kartoved/data/tray.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/scan_processing.dart';

Future<void> compareTrayLatency(
  AppModel library,
  Map<String, PreviewFrame> frames,
) async {
  const engine = RecognitionModel.oracle;
  final areas = <String, TrayArea>{};
  for (final entry in frames.entries) {
    final matches = await library.recognizeFrame(entry.value);
    areas[entry.key] = TrayArea.calibrate(matches.first.corners)!;
  }

  final warmup = Stopwatch()..start();
  final worker = await PreviewRecognizer.start(library.catalog!, engine);
  debugPrint(
    'Быстрый лоток: подготовка моделей ${warmup.elapsedMilliseconds} мс',
  );
  try {
    final timings = <(String, ScanMode), List<int>>{};
    for (var run = 0; run < 3; run++) {
      for (final entry in frames.entries) {
        for (final mode
            in run.isEven
                ? [ScanMode.tray, ScanMode.fast]
                : [ScanMode.fast, ScanMode.tray]) {
          final result = await _timeScan(
            library,
            entry.value,
            areas[entry.key]!,
            mode,
            worker,
          );
          if (result.language != entry.key) {
            throw StateError(
              'Кадр ${entry.key} распознан как ${result.language}',
            );
          }
          timings.putIfAbsent((entry.key, mode), () => []).add(result.ms);
          debugPrint(
            'Лоток ${entry.key}/${mode.name}: ${result.ms} мс, кадров ${result.frames}',
          );
        }
      }
    }
    for (final entry in timings.entries) {
      final values = entry.value..sort();
      debugPrint(
        'Лоток ${entry.key.$1}/${entry.key.$2.name}: медиана ${values[1]} мс, замеры $values',
      );
    }
  } finally {
    worker.close();
  }
}

Future<({int ms, int frames, String language})> _timeScan(
  AppModel library,
  PreviewFrame frame,
  TrayArea tray,
  ScanMode mode,
  PreviewRecognizer worker,
) async {
  const engine = RecognitionModel.oracle;
  final scan = ScanCubit()..setMode(mode);
  final fast = mode == ScanMode.fast;
  var frames = 0;
  final timer = Stopwatch()..start();
  try {
    while (++frames <= 3) {
      final matches = await library.recognizePreview(
        frame: frame,
        engine: engine,
        tray: tray,
        worker: fast ? worker : null,
        onOutline: (_) {},
      );
      if (scan.evaluate(matches) == null) {
        await Future<void>.delayed(Duration(milliseconds: mode.frameDelay()));
        continue;
      }
      final result = (await prepareScan(
        matches,
        library: library,
        batch: scan.state.batch,
        isCurrent: () => true,
        rescan: false,
        frame: frame,
        tray: tray,
        fast: fast,
      ))!;
      final (:card, :review) = result.decision;
      if (review != null || card.name != "Bouncer's Beatdown") {
        throw StateError('Лоток не смог уверенно распознать контрольную карту');
      }
      final sequence = await scan.save(library, result);
      final ms = timer.elapsedMilliseconds;
      await AndroidActions.chime(ScanSound.added);
      await result.saveThumbnail?.call();
      await library.discardScan(sequence);
      return (ms: ms, frames: frames, language: card.language);
    }
    throw StateError('Лоток не принял контрольный кадр');
  } finally {
    await scan.close();
  }
}

img.Image trayFixture(Uint8List jpg) {
  final scene = img.Image(width: 720, height: 960);
  img.fill(scene, color: img.ColorRgb8(80, 75, 66));
  return img.compositeImage(
    scene,
    img.bakeOrientation(img.decodeJpg(jpg)!),
    dstX: 127,
    dstY: 154,
    dstW: 466,
    dstH: 651,
  );
}
