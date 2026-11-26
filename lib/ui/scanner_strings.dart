import 'package:flutter/widgets.dart';

import '../data/recognition_result.dart';
import '../data/review.dart';
import '../data/scan_progress.dart';
import '../l10n/strings.dart';

extension ScanStageLanguage on ScanStage {
  String label(BuildContext context) => switch (this) {
    ScanStage.card => context.strings.scanCardOutline,
    ScanStage.title => context.strings.scanReadingTitle,
    ScanStage.artwork => context.strings.scanCheckingArtwork,
    ScanStage.details => context.strings.scanCheckingDetails,
    ScanStage.footer => context.strings.scanReadingFooter,
    ScanStage.text => context.strings.scanCheckingText,
  };
}

extension ScanReviewLanguage on ReviewReason {
  String label(BuildContext context) => switch (this) {
    ReviewReason.artwork => context.strings.reviewSimilarArt,
    ReviewReason.language => context.strings.reviewLanguage,
    ReviewReason.printing => context.strings.reviewPrinting,
    ReviewReason.batch => context.strings.reviewBatchMismatch,
  };
}

extension RecognitionModelLanguage on RecognitionModel {
  String label(BuildContext context) => switch (this) {
    RecognitionModel.oracle => 'Oracle',
    RecognitionModel.mtgIdentification => 'MTG Card Identification + Oracle',
    RecognitionModel.keypoints => context.strings.keypointsModel,
  };
}
