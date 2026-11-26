import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'data/android.dart';
import 'data/browser.dart';
import 'data/catalog.dart';
import 'data/frame.dart';
import 'data/language.dart';
import 'data/pictures.dart';
import 'data/scan_progress.dart';
import 'data/tray.dart';
import 'model.dart';
import 'scan_decision.dart';

class PreparedScan {
  const PreparedScan(this.decision, this.matches, {this.saveThumbnail});

  final ScanDecision decision;
  final List<Match> matches;
  final Future<void> Function()? saveThumbnail;
}

enum TrayRepeatCheck { firstCopy, replacement }

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
  bool essentials = false,
  bool fast = false,
  TrayRepeatCheck? repeatCheck,
  ScanProgress? onProgress,
}) async {
  final corners = tray?.corners ?? detected.first.corners;
  final quick =
      (essentials || fast) &&
      !rescan &&
      !batch.active &&
      repeatCheck != TrayRepeatCheck.replacement;
  final readFooter =
      !quick &&
      tray != null &&
      (repeatCheck != null ||
          refineTrayMatch ||
          detected.first.editions.length > 1);
  if (readFooter) onProgress?.call(ScanStage.footer, corners);
  var photo = await _preparePhoto(
    fast && !readFooter ? null : tray,
    readFooter: readFooter,
    needTitle: quick && kIsWeb,
    file: file,
    frame: frame,
    corners: corners,
  );
  if (!isCurrent()) return null;

  final matches = refineTrayMatch && !quick
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
  final englishEdition = quick
      ? await _englishEdition(
          matches.first,
          photo,
          () => onProgress?.call(ScanStage.title, corners),
        )
      : null;
  if (!isCurrent()) return null;
  // Прежде чем запомнить экземпляр для серии, проверяем непрочитанное название по выходным данным.
  final verifyPrinting = repeatCheck != null && englishEdition == null;
  if (verifyPrinting && tray != null && !readFooter) {
    onProgress?.call(ScanStage.footer, corners);
    photo =
        await AndroidActions.trayPhoto(
          file: file,
          frame: frame,
          area: tray,
          readFooter: true,
        ) ??
        photo;
    if (!isCurrent()) return null;
  }
  Future<List<Edition>> readOptions() async {
    final candidates = verifyPrinting
        ? await _printingOptions(library.catalog, options)
        : quick
        ? await _languageOptions(library.catalog, options)
        : options;
    if (!isCurrent()) return candidates;
    final currentPhoto = photo;
    return currentPhoto == null
        ? CardLanguage.readOptions(
            file: file,
            frame: frame,
            corners: corners,
            options: candidates,
            onRead: showText,
            languageOnly: quick && !verifyPrinting,
          )
        : CardLanguage.readTrayOptions(
            currentPhoto,
            candidates,
            onRead: showText,
            languageOnly: quick && !verifyPrinting,
          );
  }

  final evidence = englishEdition == null
      ? await readOptions()
      : [englishEdition];
  if (!isCurrent()) return null;

  final ambiguous =
      quick &&
      (matches.first.score < .75 ||
          closeMatches(matches)
              .any((m) => m.editions.first.name != options.first.name));
  final needsLanguage =
      fast && evidence.map((e) => e.language).toSet().length > 1;
  var decision = verifyPrinting
      ? decideTrayRepeat(matches, evidence, batch)
      : rescan ||
            matches.first.titleOnly ||
            ambiguous ||
            needsLanguage ||
            (fast && batch.active)
      ? decideScan(matches, evidence, batch)
      : (card: selectScannedEdition(evidence, batch), review: null);
  if (quick && !verifyPrinting && decision.review == null) {
    final card = decision.card;
    final candidates = closeMatches(matches)
        .expand((m) => m.editions)
        .where(
          (e) =>
              e.name == card.name &&
              (card.language == 'und' || e.language == card.language),
        );
    final printings = candidates.map((e) => (e.set, e.number)).toSet();
    if (printings.length != 1 || !printings.contains((card.set, card.number))) {
      decision = (card: card.withoutPrinting(), review: null);
    }
  }
  Future<void> saveThumbnail() => _saveThumbnail(
    decision.card.id,
    photo?.bytes,
    file,
    frame,
    corners,
    fast ? () => true : isCurrent,
  );
  if (fast) {
    return PreparedScan(decision, matches, saveThumbnail: saveThumbnail);
  }
  await saveThumbnail();
  return PreparedScan(decision, matches);
}

Future<List<Edition>> _printingOptions(
  Catalog? catalog,
  List<Edition> artwork,
) async {
  final editions =
      await catalog?.byName(artwork.first.name) ?? const <Edition>[];
  return {
    for (final e in [...artwork, ...editions]) e.id: e,
  }.values.toList();
}

Future<TrayPhoto?> _preparePhoto(
  TrayArea? tray, {
  required bool readFooter,
  required bool needTitle,
  String? file,
  PreviewFrame? frame,
  required List<double> corners,
}) async {
  if (tray != null) {
    return AndroidActions.trayPhoto(
      file: file,
      frame: frame,
      area: tray,
      readFooter: readFooter,
    );
  }
  if (!needTitle) return null;
  try {
    final bytes = await AndroidActions.scanPhoto(
      file: file,
      frame: frame,
      corners: corners,
    );
    return bytes == null ? null : (bytes: bytes, footer: '');
  } on Exception {
    return null;
  }
}

Future<Edition?> _englishEdition(
  Match match,
  TrayPhoto? photo,
  void Function() onRead,
) async {
  final english = match.editions.where((e) => e.language == 'en').firstOrNull;
  if (english == null || match.englishTitle) return english;
  if (!kIsWeb || photo == null) return null;
  onRead();
  try {
    final title = await browserEnglishTitle(photo.bytes);
    return CardLanguage.matchesEnglishTitle(title, english.name)
        ? english
        : null;
  } catch (_) {
    return null;
  }
}

Future<List<Edition>> _languageOptions(
  Catalog? catalog,
  List<Edition> options,
) async {
  if (catalog == null || options.any((e) => e.language != 'en')) return options;
  // У одного рисунка иногда есть только английская запись. Перевод ищем по названию.
  final languages = {'en'};
  return [
    ...options,
    for (final e in await catalog.byName(options.first.name))
      if (languages.add(e.language)) e,
  ];
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
