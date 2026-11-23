import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Pictures {
  static final shared = Pictures();
  final Map<String, Future<File>> _pending = {};
  final _photos = StreamController<String>.broadcast();
  Stream<String> get photos => _photos.stream;
  Future<Directory>? _root;

  Future<Directory> get _directory =>
      _root ??= getApplicationSupportDirectory().then(
        (dir) =>
            Directory(p.join(dir.path, 'pictures')).create(recursive: true),
      );

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

  Future<File> get(String id, {bool large = false}) async {
    final key = large ? '$id.normal' : id;
    final url = address(id, large: large);
    final root = await _directory;
    final file = File(p.join(root.path, '$key.jpg'));
    if (await file.exists()) return file;
    final photo = _scanFile(root, id);
    if (await photo.exists()) return photo;
    return _pending.putIfAbsent(
      key,
      () => _download(url, file).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  File _scanFile(Directory root, String id) =>
      File(p.join(root.path, '$id.scan.jpg'));

  Future<void> saveScan(String id, Uint8List bytes) async {
    address(id);
    final photo = _scanFile(await _directory, id);
    if (await photo.exists()) return;
    final temp = File('${photo.path}.part');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(photo.path);
      _photos.add(id);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<File> _download(Uri url, File file) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = 'Kartoved Android (github.com/Hecatoncheir/kartoved)';
    final temp = File('${file.path}.part');
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200 ||
          response.headers.contentType?.primaryType != 'image') {
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
