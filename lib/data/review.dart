import 'dart:convert';

import 'catalog.dart' show Edition;

enum ReviewReason { artwork, language, printing, batch }

class ScanReview {
  const ScanReview(this.reason, this.choices, {this.batchLabel = ''});
  final ReviewReason reason;
  final List<Edition> choices;
  final String batchLabel;

  String encode() => jsonEncode({
    'reason': reason.name,
    if (batchLabel.isNotEmpty) 'batch': batchLabel,
    'choices': [for (final card in choices) card.row],
  });

  factory ScanReview.decode(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    return ScanReview(ReviewReason.values.byName(data['reason'] as String), [
      for (final row in data['choices'] as List)
        Edition.fromRow(row as Map<String, dynamic>),
    ], batchLabel: data['batch'] as String? ?? '');
  }
}
