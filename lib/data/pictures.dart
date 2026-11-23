import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Pictures {
  static final shared = Pictures();
  final Map<String, Future<File>> _pending = {};
  Future<Directory>? _root;

  static Uri address(String id, {bool large = false}) {
    final matched = RegExp(
      r'^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(-1)?$',
    ).firstMatch(id);
    if (matched == null) {
      throw const FormatException('Некорректный код издания');
    }
    final uuid = matched[1]!;
    final side = matched[2] == null ? 'front' : 'back';
    return Uri.https(
      'cards.scryfall.io',
      '/${large ? 'normal' : 'small'}/$side/${uuid[0]}/${uuid[1]}/$uuid.jpg',
    );
  }

  Future<File> get(String id, {bool large = false}) {
    final key = large ? '$id.normal' : id;
    return _pending.putIfAbsent(
      key,
      () => _load(id, key, large).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<File> _load(String id, String key, bool large) async {
    final url = address(id, large: large);
    final root = await (_root ??= getApplicationSupportDirectory().then(
      (d) => Directory(p.join(d.path, 'pictures')).create(recursive: true),
    ));
    final file = File(p.join(root.path, '$key.jpg'));
    if (await file.exists()) return file;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = 'Kartoved Android';
    final temp = File('${file.path}.part');
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200 ||
          response.headers.contentType?.mimeType != 'image/jpeg') {
        throw HttpException('Изображение недоступно', uri: url);
      }
      await response
          .timeout(const Duration(seconds: 10))
          .pipe(temp.openWrite());
      return await temp.rename(file.path);
    } finally {
      client.close(force: true);
      if (await temp.exists()) await temp.delete();
    }
  }
}
