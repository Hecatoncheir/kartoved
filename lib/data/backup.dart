import 'dart:convert';
import 'dart:io';

import 'review.dart';

typedef BackupRow = Map<String, Object?>;

const _invalid = FormatException('Файл резервной копии повреждён');

class LibraryBackup {
  LibraryBackup._(this.folders, this.scans, this.copies, this.pending);

  final List<BackupRow> folders, scans;
  final int copies, pending;

  static Future<LibraryBackup> read(String path) async {
    final Object? json;
    try {
      json = jsonDecode(await File(path).readAsString());
    } on FormatException {
      throw _invalid;
    }
    return LibraryBackup.fromJson(json);
  }

  factory LibraryBackup.fromJson(Object? json) {
    if (json is! BackupRow || json['format'] != 'kartoved') {
      throw const FormatException('Выберите резервную копию Картоведа');
    }
    if (json['version'] is! int || json['version'] != 1) {
      throw const FormatException('Эта версия формата не поддерживается');
    }
    final folderIds = <int>{};
    final folders = [
      for (final row in _rows(json['folders']))
        {
          'folder': _unique(row['folder'], folderIds),
          'title': _string(row['title']),
        },
    ];
    if (!folderIds.contains(1)) throw _invalid;
    final sequences = <int>{};
    final scans = [
      for (final row in _rows(json['scans'])) _scan(row, folderIds, sequences),
    ];
    final confirmed = scans.where((row) => row['review'] == null);
    var copies = 0;
    for (final row in confirmed) {
      final quantity = _positive(row['qty']);
      if (copies > 0x7fffffffffffffff - quantity) throw _invalid;
      copies += quantity;
    }
    return LibraryBackup._(
      folders,
      scans,
      copies,
      scans.length - confirmed.length,
    );
  }

  static Future<void> write(
    ({String path, List<BackupRow> folders, List<BackupRow> scans}) snapshot,
  ) async {
    final json = {
      'format': 'kartoved',
      'version': 1,
      'folders': snapshot.folders,
      'scans': [
        for (final row in snapshot.scans)
          {
            ...row,
            'review': switch (row['review']) {
              String text => jsonDecode(text),
              _ => null,
            },
          },
      ],
    };
    await File(snapshot.path).writeAsString(jsonEncode(json), flush: true);
  }
}

Iterable<BackupRow> _rows(Object? value) sync* {
  if (value is! List) throw _invalid;
  for (final row in value) {
    if (row is! BackupRow) throw _invalid;
    yield row;
  }
}

int _positive(Object? value) {
  if (value is! int || value < 1) throw _invalid;
  return value;
}

int _unique(Object? value, Set<int> seen) {
  final id = _positive(value);
  if (!seen.add(id)) throw _invalid;
  return id;
}

int _bit(Object? value) => switch (value) {
  int n when n == 0 || n == 1 => n,
  _ => throw _invalid,
};

String _string(Object? value) {
  if (value is! String) throw _invalid;
  return value;
}

BackupRow _edition(BackupRow row) => {
  for (final key in ['id', 'name', 'set_code', 'number', 'lang'])
    key: _string(row[key]),
  'foil': _bit(row['foil']),
};

BackupRow _scan(BackupRow row, Set<int> folders, Set<int> sequences) {
  final folder = _positive(row['folder']);
  if (!folders.contains(folder) || !row.containsKey('review')) throw _invalid;
  return {
    ..._edition(row),
    'seq': _unique(row['seq'], sequences),
    'folder': folder,
    'qty': _positive(row['qty']),
    'flagged': _bit(row['flagged']),
    'review': _review(row['review']),
  };
}

String? _review(Object? value) {
  if (value == null) return null;
  if (value is! BackupRow) throw _invalid;
  final reason = _string(value['reason']);
  if (!ReviewReason.values.any((r) => r.name == reason)) throw _invalid;
  final choices = _rows(value['choices']).map(_edition).toList();
  if (choices.isEmpty) throw _invalid;
  return jsonEncode({
    'reason': reason,
    if (value.containsKey('batch')) 'batch': _string(value['batch']),
    'choices': choices,
  });
}
