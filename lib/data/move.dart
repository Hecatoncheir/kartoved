part of 'collections.dart';

typedef _Portion = ({int original, int moved, int quantity});

class CardMove {
  const CardMove._(this.from, this.to, this.card, this.flagged, this._portions);
  final int from, to;
  final Edition card;
  final bool flagged;
  final List<_Portion> _portions;
}

extension CardTransfers on History {
  Future<void> resolvePrinting(
    int folder,
    Edition unknown,
    Edition selected, {
    int? sequence,
  }) => _db.transaction((db) async {
    if (!unknown.needsPrinting ||
        selected.needsPrinting ||
        unknown.name != selected.name) {
      throw ArgumentError('Выберите издание этой карты');
    }
    final rows = await db.query(
      'scans',
      where: sequence == null ? _printing : '$_printing AND seq=?',
      whereArgs: [..._printingArgs(folder, unknown), ?sequence],
      orderBy: 'seq DESC',
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Издание уже уточнено');
    final row = rows.single;
    final flagged = await _flag(
      db,
      folder,
      selected,
      fallback: row['flagged'] == 1,
    );
    await _movePortion(
      db,
      row['seq'] as int,
      selected,
      {...selected.row, 'folder': folder, 'flagged': flagged},
      1,
      row['qty'] as int,
    );
  });

  Future<CardMove> moveCards(int from, int to, Edition card, int quantity) =>
      _db.transaction((db) => _move(db, from, to, card, quantity));

  Future<CardMove> moveToNewCollection(
    int from,
    String name,
    Edition card,
    int quantity,
  ) => _db.transaction((db) async {
    final to = await _createFolder(db, name);
    return _move(db, from, to, card, quantity);
  });

  Future<CardMove> _move(
    Transaction db,
    int from,
    int to,
    Edition card,
    int quantity,
  ) async {
    if (from == to || quantity < 1) {
      throw ArgumentError('Проверьте коллекцию и количество');
    }
    final rows = await db.query(
      'scans',
      where: _printing,
      whereArgs: _printingArgs(from, card),
      orderBy: 'seq DESC',
    );
    final flagged = rows.firstOrNull?['flagged'] == 1;
    final targetFlag = await _flag(db, to, card, fallback: flagged);
    final target = {'folder': to, 'flagged': targetFlag};
    final portions = <_Portion>[];
    var left = quantity;
    for (final row in rows) {
      if (left == 0) break;
      final seq = row['seq'] as int;
      final available = row['qty'] as int;
      final amount = left < available ? left : available;
      final moved = await _movePortion(
        db,
        seq,
        card,
        target,
        amount,
        available,
      );
      portions.add((original: seq, moved: moved, quantity: amount));
      left -= amount;
    }
    if (left != 0) throw StateError('В коллекции недостаточно экземпляров');
    return CardMove._(from, to, card, flagged, portions);
  }

  Future<int> _movePortion(
    Transaction db,
    int seq,
    Edition card,
    Map<String, Object?> target,
    int amount,
    int available,
  ) async {
    if (amount == available) {
      await db.update('scans', target, where: 'seq=?', whereArgs: [seq]);
      return seq;
    }
    await db.update(
      'scans',
      {'qty': available - amount},
      where: 'seq=?',
      whereArgs: [seq],
    );
    return db.insert('scans', {...card.row, ...target, 'qty': amount});
  }

  Future<void> undoMove(CardMove move) => _db.transaction((db) async {
    final flag = await _flag(db, move.from, move.card, fallback: move.flagged);
    for (final part in move._portions) {
      const where = '$_printing AND seq=? AND qty=?';
      final args = [
        ..._printingArgs(move.to, move.card),
        part.moved,
        part.quantity,
      ];
      if (part.original == part.moved) {
        _requireRow(
          await db.update(
            'scans',
            {'folder': move.from, 'flagged': flag},
            where: where,
            whereArgs: args,
          ),
        );
      } else {
        _requireRow(await db.delete('scans', where: where, whereArgs: args));
        _requireRow(
          await db.rawUpdate(
            'UPDATE scans SET qty=qty+? WHERE $_printing AND seq=?',
            [
              part.quantity,
              ..._printingArgs(move.from, move.card),
              part.original,
            ],
          ),
        );
      }
    }
  });

  void _requireRow(int changed) {
    if (changed != 1) throw StateError('Экземпляры уже изменились');
  }
}
