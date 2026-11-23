import 'data/catalog.dart';

class CollectionRow {
  CollectionRow(this.variants);

  final List<CardCount> variants;
  Edition get card => variants.first.card;
  bool get multiple => variants.length > 1;
  String get key =>
      multiple ? 'name/${card.name.toLowerCase()}' : card.printingKey;
  late final int quantity = variants.fold<int>(
    0,
    (sum, row) => sum + row.quantity,
  );

  static List<CollectionRow> from(
    Iterable<CardCount> printings, {
    required bool groupNames,
  }) {
    final groups = <String, List<CardCount>>{};
    for (final item in printings) {
      final key = groupNames
          ? item.card.name.toLowerCase()
          : item.card.printingKey;
      (groups[key] ??= []).add(item);
    }
    return groups.values.map(CollectionRow.new).toList();
  }
}
