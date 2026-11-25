import 'dart:typed_data';

import 'data/android.dart';
import 'data/frame.dart';
import 'data/language.dart';
import 'data/pictures.dart';
import 'data/scan_progress.dart';
import 'data/tray.dart';
import 'model.dart';
import 'scan_decision.dart';

typedef PreparedScan = ({ScanDecision decision, List<Match> matches});

Future<PreparedScan?> prepareScan(
  List<Match> detected, {
  required AppModel library,
  required BatchSettings batch,
  required bool Function() isCurrent,
  required bool rescan,
  String? file,
  PreviewFrame? frame,
  TrayArea? tray,
  bool refineTrayMatch = false,
  ScanProgress? onProgress,
}) async {
  final corners = tray?.corners ?? detected.first.corners;
  final readFooter =
      tray != null && (refineTrayMatch || detected.first.editions.length > 1);
  if (readFooter) onProgress?.call(ScanStage.footer, corners);
  final photo = tray == null
      ? null
      : await AndroidActions.trayPhoto(
          file: file,
          frame: frame,
          area: tray,
          readFooter: readFooter,
        );
  if (!isCurrent()) return null;

  final matches = refineTrayMatch
      ? await library.refineTrayMatches(
          detected,
          file: file,
          frame: frame,
          photo: photo?.bytes,
          onProgress: onProgress,
        )
      : detected;
  if (!isCurrent()) return null;
  final options = matches.first.editions;
  void showText() => onProgress?.call(ScanStage.text, corners);
  final evidence = photo == null
      ? await CardLanguage.readOptions(
          file: file,
          frame: frame,
          corners: corners,
          options: options,
          onRead: showText,
        )
      : await CardLanguage.readTrayOptions(photo, options, onRead: showText);
  if (!isCurrent()) return null;

  final decision = rescan || matches.first.titleOnly
      ? decideScan(matches, evidence, batch)
      : (card: selectScannedEdition(evidence, batch), review: null);
  await _saveThumbnail(
    decision.card.id,
    photo?.bytes,
    file,
    frame,
    corners,
    isCurrent,
  );
  return (decision: decision, matches: matches);
}

Future<void> _saveThumbnail(
  String id,
  Uint8List? prepared,
  String? file,
  PreviewFrame? frame,
  List<double> corners,
  bool Function() isCurrent,
) async {
  try {
    final bytes =
        prepared ??
        await AndroidActions.scanPhoto(
          file: file,
          frame: frame,
          corners: corners,
        );
    if (bytes != null && isCurrent()) await Pictures.shared.saveScan(id, bytes);
  } on Exception {
    // Отсутствие миниатюры не мешает записать карту.
  }
}
