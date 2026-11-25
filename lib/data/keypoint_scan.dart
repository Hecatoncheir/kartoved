import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'android.dart';
import 'catalog.dart';
import 'frame.dart';
import 'keypoints.dart';
import 'pictures.dart';

typedef KeypointChoice = ({int artwork, Edition? printing});
typedef _Reference = ({int artwork, Edition edition, Uint8List? bytes});

Future<KeypointChoice?> refineKeypointScan(
  List<List<Edition>> candidates,
  List<double> corners, {
  String? file,
  PreviewFrame? frame,
  Uint8List? photo,
  void Function()? onCompare,
}) async {
  if (corners.length != 8) return null;
  final options = candidates.take(3).toList();
  final references = await Future.wait([
    for (var index = 0; index < options.length; index++)
      for (final edition in _printings(options[index]).take(index == 0 ? 4 : 1))
        _loadReference(index, edition),
  ]);
  final available = references.where((ref) => ref.bytes != null).toList();
  if (available.isEmpty || available.first.artwork != 0) return null;
  try {
    final crop =
        photo ??
        await AndroidActions.scanPhoto(
          file: file,
          frame: frame,
          corners: corners,
        );
    if (crop == null) return null;
    onCompare?.call();
    final scores = await compute(compareKeypoints, (
      crop: crop,
      references: [for (final ref in available) ref.bytes!],
    ));
    return _select(available, scores);
  } on Exception {
    return null;
  }
}

Iterable<Edition> _printings(List<Edition> options) sync* {
  final seen = <(String, String)>{};
  for (final option in options) {
    if (seen.add((option.set, option.number))) yield option;
  }
}

Future<_Reference> _loadReference(int artwork, Edition edition) async {
  Uint8List? bytes;
  try {
    bytes = await Pictures.shared
        .referenceBytes(edition.id)
        .timeout(const Duration(seconds: 2));
  } on Exception {
    // Без эталона используем обычный результат Oracle.
  }
  return (artwork: artwork, edition: edition, bytes: bytes);
}

KeypointChoice _select(
  List<_Reference> references,
  List<KeypointScore> scores,
) {
  final byArtwork = <int, int>{};
  for (var i = 0; i < scores.length; i++) {
    final score = scores[i].art;
    byArtwork.update(
      references[i].artwork,
      (previous) => math.max(previous, score),
      ifAbsent: () => score,
    );
  }
  final ranked = byArtwork.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final best = ranked.first;
  final rival = ranked.skip(1).firstOrNull;
  final artwork =
      best.value >= 12 && (rival == null || best.value - rival.value >= 6)
      ? best.key
      : 0;
  final printings = [
    for (var i = 0; i < scores.length; i++)
      if (references[i].artwork == artwork && scores[i].art >= 8) i,
  ]..sort((a, b) => scores[b].printing.compareTo(scores[a].printing));
  if (printings.length < 2) return (artwork: artwork, printing: null);
  final [first, second, ...] = printings;
  final evidence = scores[first].printing;
  return (
    artwork: artwork,
    printing: evidence >= 6 && evidence - scores[second].printing >= 4
        ? references[first].edition
        : null,
  );
}
