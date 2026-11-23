import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef CardFaceText = ({
  String name,
  String? type,
  String? mana,
  String? stats,
  String? printed,
  String? oracle,
  String? flavor,
});
typedef CardRuling = ({String text, String? date});

class CardReference {
  CardReference.fromJson(Map<String, dynamic> card, List<dynamic>? rulings)
    : faces = [
        for (final face in (card['card_faces'] as List<dynamic>?) ?? [card])
          _face(face as Map<String, dynamic>),
      ],
      setName = _text(card['set_name']),
      rarity = _text(card['rarity']),
      artist = _text(card['artist']),
      manaValue = card['cmc'] as num?,
      legalities = Map<String, String>.from(card['legalities'] as Map? ?? {}),
      rulings = rulings
          ?.whereType<Map<String, dynamic>>()
          .map(
            (ruling) => (
              text: ruling['comment'] as String,
              date: _text(ruling['published_at']),
            ),
          )
          .toList();

  final List<CardFaceText> faces;
  final String? setName, rarity, artist;
  final num? manaValue;
  final Map<String, String> legalities;
  final List<CardRuling>? rulings;

  static String? _text(Object? value) => switch (value) {
    String text when text.trim().isNotEmpty => text,
    _ => null,
  };

  static CardFaceText _face(Map<String, dynamic> data) {
    final stats = [
      if (data['power'] case final String power)
        if (data['toughness'] case final String toughness) '$power/$toughness',
      if (data['loyalty'] case final String loyalty) 'Верность $loyalty',
      if (data['defense'] case final String defense) 'Защита $defense',
    ];
    return (
      name: _text(data['printed_name']) ?? data['name'] as String,
      type: _text(data['printed_type_line']) ?? _text(data['type_line']),
      mana: _text(data['mana_cost']),
      stats: stats.isEmpty ? null : stats.join(' · '),
      printed: _text(data['printed_text']),
      oracle: _text(data['oracle_text']),
      flavor: _text(data['flavor_text']),
    );
  }
}

class CardReferences {
  static final shared = CardReferences();
  static final _id = RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
  final _pending = <String, Future<CardReference>>{};
  final _clock = Stopwatch()..start();
  int _nextRequest = 0;

  Future<CardReference> get(String printingId) async {
    final id = printingId.replaceFirst(RegExp(r'-1$'), '');
    if (!_id.hasMatch(id)) throw const FormatException('Некорректное издание');
    return _pending.putIfAbsent(
      id,
      () => _load(id).whenComplete(() => _pending.remove(id)),
    );
  }

  Future<CardReference> _load(String id) async {
    final root = await getApplicationSupportDirectory();
    final folder = await Directory(p.join(root.path, 'card-reference'))
        .create(recursive: true);
    final file = File(p.join(folder.path, '$id.json'));
    final cached = await _readCache(file);
    final savedCard = cached?['card'] as Map<String, dynamic>?;
    final savedRulings = cached?['rulings'] as List<dynamic>?;
    if (savedCard != null && savedRulings != null) {
      return CardReference.fromJson(savedCard, savedRulings);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..userAgent = 'Kartoved Android (github.com/Hecatoncheir/kartoved)';
    try {
      final card = savedCard ?? await _request(client, '/cards/$id');
      final rulings = await _rulings(client, id);
      final result = CardReference.fromJson(card, rulings);
      await _saveCache(file, {'card': card, 'rulings': rulings});
      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<dynamic>?> _rulings(HttpClient client, String id) async {
    try {
      final result = <dynamic>[];
      var page = 1;
      while (true) {
        final data = await _request(client, '/cards/$id/rulings', {
          'page': '$page',
        });
        result.addAll(data['data'] as List<dynamic>);
        if (data['has_more'] != true) return result;
        page++;
      }
    } on Exception {
      return null;
    }
  }

  Future<Map<String, dynamic>> _request(
    HttpClient client,
    String path, [
    Map<String, String>? query,
  ]) async {
    final now = _clock.elapsedMilliseconds;
    final wait = (_nextRequest - now).clamp(0, _nextRequest);
    _nextRequest = now + wait + 120;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    const timeout = Duration(seconds: 7);
    final request = await client
        .getUrl(Uri.https('api.scryfall.com', path, query))
        .timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('Данные карты недоступны');
    }
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> _readCache(File file) async {
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) return data;
      }
    } on Exception {
      // Повреждённый кэш можно заполнить повторно.
    }
    return null;
  }

  Future<void> _saveCache(File file, Map<String, dynamic> data) async {
    final temp = File('${file.path}.part');
    try {
      await temp.writeAsString(jsonEncode(data));
      await temp.rename(file.path);
    } on FileSystemException {
      // Сведения остаются доступными в открытой карточке.
    }
  }
}
