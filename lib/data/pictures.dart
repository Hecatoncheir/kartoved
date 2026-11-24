import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'browser.dart';

class Pictures {
  static final shared = Pictures();
  final Map<String, Future<File>> _pending = {};
  final Map<String, Future<Uint8List>> _browserPending = {};
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

  Future<ImageProvider> official(String id, {bool large = false}) async {
    if (!kIsWeb) return FileImage(await _getFile(id, large: large));
    try {
      return MemoryImage(await _getBrowser(id, large: large));
    } on Exception {
      return NetworkImage(
        address(id, large: large).toString(),
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      );
    }
  }

  Future<Uint8List> referenceBytes(String id) async => kIsWeb
      ? _getBrowser(id, large: true)
      : (await _getFile(id, large: true)).readAsBytes();

  Future<ImageProvider?> cachedThumbnail(String id) async {
    if (kIsWeb) {
      final bytes = await _cachedBrowserThumbnail(id);
      return bytes == null ? null : MemoryImage(bytes);
    }
    final file = await _cachedFileThumbnail(id);
    return file == null ? null : FileImage(file);
  }

  Future<Uint8List> thumbnailBytes(String id) async {
    if (kIsWeb) {
      return await _cachedBrowserThumbnail(id) ?? _getBrowser(id, large: false);
    }
    final file =
        await _cachedFileThumbnail(id) ?? await _getFile(id, large: false);
    return file.readAsBytes();
  }

  Future<Uint8List?> _cachedBrowserThumbnail(String id) async =>
      await browserCacheRead('images/$id/small') ??
      await browserCacheRead('scans/$id');

  Future<File?> _cachedFileThumbnail(String id) async {
    address(id);
    final root = await _directory;
    final image = File(p.join(root.path, '$id.jpg'));
    if (await image.exists()) return image;
    final scan = _scanFile(root, id);
    return await scan.exists() ? scan : null;
  }

  Future<Uint8List> _getBrowser(String id, {required bool large}) async {
    final url = address(id, large: large);
    final key = 'images/$id/${large ? 'large' : 'small'}';
    final cached = await browserCacheRead(key);
    if (cached != null) return cached;
    return _browserPending.putIfAbsent(
      key,
      () => _downloadBrowser(url, key)
          .then((bytes) {
            if (!large) _photos.add(id);
            return bytes;
          })
          .whenComplete(() {
            _browserPending.remove(key);
          }),
    );
  }

  Future<Uint8List> _downloadBrowser(Uri url, String key) async {
    final response = await http.get(url).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200 ||
        response.headers['content-type']?.startsWith('image/') != true ||
        response.bodyBytes.isEmpty) {
      throw const FormatException('Изображение недоступно');
    }
    await browserCacheWrite(key, response.bodyBytes);
    return response.bodyBytes;
  }

  Future<File> _getFile(String id, {required bool large}) async {
    final key = large ? '$id.normal' : id;
    final url = address(id, large: large);
    final root = await _directory;
    final file = File(p.join(root.path, '$key.jpg'));
    if (await file.exists()) return file;
    return _pending.putIfAbsent(
      key,
      () => _download(url, file)
          .then((image) {
            if (!large) _photos.add(id);
            return image;
          })
          .whenComplete(() {
            _pending.remove(key);
          }),
    );
  }

  File _scanFile(Directory root, String id) =>
      File(p.join(root.path, '$id.scan.jpg'));

  Future<void> saveScan(String id, Uint8List bytes) async {
    address(id);
    if (kIsWeb) {
      if (await browserCacheRead('scans/$id') != null) return;
      await browserCacheWrite('scans/$id', bytes);
      _photos.add(id);
      return;
    }
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
      if (await temp.length() == 0) {
        throw const FormatException('Пустое изображение');
      }
      return await temp.rename(file.path);
    } finally {
      client.close(force: true);
      if (await temp.exists()) await temp.delete();
    }
  }
}
