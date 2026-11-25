import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;

// CameraX возвращает один непрерывный буфер NV21.
typedef PreviewFrame = ({Uint8List bytes, int width, int height, int rotation});

Map<String, Object?> scanArguments({
  String? file,
  PreviewFrame? frame,
  required List<double> corners,
}) => {
  'corners': corners,
  if (frame == null)
    'file': file
  else ...{
    'bytes': frame.bytes,
    'width': frame.width,
    'height': frame.height,
    'rotation': frame.rotation,
  },
};

im.Image frameImage(PreviewFrame frame, {int maxSide = 640}) {
  final scale = math.min(1.0, maxSide / math.max(frame.width, frame.height));
  final rgb = im.Image(
    width: (frame.width * scale).round(),
    height: (frame.height * scale).round(),
  );
  final lumaSize = frame.width * frame.height;
  if (frame.bytes.length < lumaSize * 3 ~/ 2) {
    throw const FormatException('Неполный кадр NV21');
  }
  for (final pixel in rgb) {
    final x = (pixel.x / scale).floor(), y = (pixel.y / scale).floor();
    final chroma = lumaSize + (y ~/ 2) * frame.width + (x & ~1);
    final light = 1.164 * (frame.bytes[y * frame.width + x] - 16);
    final v = frame.bytes[chroma] - 128, u = frame.bytes[chroma + 1] - 128;
    pixel.setRgb(
      (light + 1.596 * v).round().clamp(0, 255),
      (light - .392 * u - .813 * v).round().clamp(0, 255),
      (light + 2.017 * u).round().clamp(0, 255),
    );
  }
  return im.copyRotate(rgb, angle: frame.rotation);
}
