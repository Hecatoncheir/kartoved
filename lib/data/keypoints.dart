import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

typedef KeypointScore = ({int art, int printing});
typedef KeypointInput = ({Uint8List crop, List<Uint8List> references});

const _width = 224;
const _height = 312;
const _radius = 9;
const _step = 10;

// Выровненные изображения сравниваются в одной системе координат.
List<KeypointScore> compareKeypoints(KeypointInput input) {
  final query = _features(input.crop);
  return [
    for (final bytes in input.references) _compare(query, _features(bytes)),
  ];
}

typedef _Point = ({int x, int y, List<int> descriptor});
typedef _Pair = ({_Point point, int dx, int dy, int distance});

final _tests = _comparisonOffsets();

List<(int, int)> _comparisonOffsets() {
  final random = math.Random(37);
  int offset() => random.nextInt(2 * _radius - 1) - _radius + 1;
  int sample() => offset() * _width + offset();
  return List.generate(96, (_) => (sample(), sample()));
}

List<_Point> _features(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) return [];
  final gray = image
      .grayscale(
        image.copyResize(
          decoded,
          width: _width,
          height: _height,
          interpolation: image.Interpolation.average,
        ),
      )
      .getBytes(order: image.ChannelOrder.red);
  final points = <_Point>[];
  for (var top = 13; top < _height - 13 - _step; top += _step) {
    for (var left = 13; left < _width - 13 - _step; left += _step) {
      var best = 240.0;
      int? corner;
      for (var y = top; y < top + _step; y += 2) {
        for (var x = left; x < left + _step; x += 2) {
          final position = y * _width + x;
          final score = _cornerScore(gray, position);
          if (score > best) {
            best = score;
            corner = position;
          }
        }
      }
      if (corner != null) {
        points.add((
          x: corner % _width,
          y: corner ~/ _width,
          descriptor: _describe(gray, corner),
        ));
      }
    }
  }
  return points;
}

double _cornerScore(Uint8List gray, int center) {
  var xx = 0, yy = 0, xy = 0;
  for (var y = -_width; y <= _width; y += _width) {
    for (var x = -1; x <= 1; x++) {
      final p = center + y + x;
      final dx = gray[p + 1] - gray[p - 1];
      final dy = gray[p + _width] - gray[p - _width];
      xx += dx * dx;
      yy += dy * dy;
      xy += dx * dy;
    }
  }
  return (xx * yy - xy * xy) / (xx + yy + 1);
}

List<int> _describe(Uint8List gray, int center) {
  final words = List.filled(4, 0);
  for (var i = 0; i < _tests.length; i++) {
    final (a, b) = _tests[i];
    if (gray[center + a] < gray[center + b]) {
      words[i ~/ 24] |= 1 << (i % 24);
    }
  }
  return words;
}

final _bitCounts = List.generate(256, (value) {
  var count = 0;
  for (var n = value; n != 0; n &= n - 1) {
    count++;
  }
  return count;
});

int _distance(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i++) {
    final bits = a[i] ^ b[i];
    count +=
        _bitCounts[bits & 255] +
        _bitCounts[(bits >> 8) & 255] +
        _bitCounts[bits >> 16];
  }
  return count;
}

List<_Pair> _pairs(List<_Point> query, List<_Point> reference) {
  final pairs = <_Point, _Pair>{};
  for (final point in query) {
    _Point? closest;
    var best = 96, second = 96;
    for (final other in reference) {
      if ((point.x - other.x).abs() > 18 || (point.y - other.y).abs() > 22) {
        continue;
      }
      final distance = _distance(point.descriptor, other.descriptor);
      if (distance < best) {
        closest = other;
        second = best;
        best = distance;
      } else if (distance < second) {
        second = distance;
      }
    }
    if (closest == null || best > 28 || best * 5 >= second * 4) continue;
    if (best >= (pairs[closest]?.distance ?? 96)) continue;
    pairs[closest] = (
      point: point,
      dx: closest.x - point.x,
      dy: closest.y - point.y,
      distance: best,
    );
  }
  return pairs.values.toList();
}

bool _near(_Pair a, _Pair b) =>
    (a.dx - b.dx).abs() <= 5 && (a.dy - b.dy).abs() <= 5;

bool _insideArt(_Point p) =>
    p.x >= 35 && p.x <= _width - 35 && p.y >= 48 && p.y <= 169;

bool _insidePrinting(_Point p) =>
    p.y >= 272 || (p.x >= 156 && p.y >= 161 && p.y <= 202);

KeypointScore _compare(List<_Point> query, List<_Point> reference) {
  final pairs = _pairs(query, reference);
  final art = pairs.where((pair) => _insideArt(pair.point)).toList();
  _Pair? anchor;
  var count = 0;
  for (final pair in art) {
    final votes = art.where((other) => _near(pair, other)).length;
    if (votes > count) {
      anchor = pair;
      count = votes;
    }
  }
  if (anchor == null || count < 8) return (art: 0, printing: 0);
  final printing = pairs
      .where((pair) => _insidePrinting(pair.point) && _near(anchor!, pair))
      .length;
  return (art: count, printing: printing);
}
