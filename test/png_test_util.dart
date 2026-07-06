import 'dart:io';
import 'dart:typed_data';

/// A decoded 8-bit RGBA PNG, for tests that need to assert on actual pixel
/// content rather than just "the encoded bytes changed" — see
/// `renderer_test.dart`'s stroke cap/dash tests, where two renders can
/// legitimately differ in encoded bytes for reasons unrelated to the
/// property under test.
///
/// Deliberately dependency-free: PNG's IDAT stream is zlib-compressed,
/// which `dart:io`'s [ZLibDecoder] already handles, so decoding needs only
/// chunk parsing and the PNG filter (unfiltering) algorithm — both trivial
/// enough to inline here rather than pull in an image-decoding package.
class DecodedPng {
  final int width;
  final int height;
  final Uint8List _rgba;

  DecodedPng._(this.width, this.height, this._rgba);

  /// Parses [bytes] (a full PNG file, 8-bit-per-channel RGBA/RGB only).
  factory DecodedPng.decode(Uint8List bytes) {
    var pos = 8; // skip the 8-byte PNG signature.
    late int width, height, bitDepth, colorType;
    final idat = BytesBuilder();

    while (pos < bytes.length) {
      final length = ByteData.sublistView(
        bytes,
        pos,
        pos + 4,
      ).getUint32(0);
      final type = String.fromCharCodes(bytes, pos + 4, pos + 8);
      final data = bytes.sublist(pos + 8, pos + 8 + length);
      if (type == 'IHDR') {
        final view = ByteData.sublistView(data);
        width = view.getUint32(0);
        height = view.getUint32(4);
        bitDepth = data[8];
        colorType = data[9];
      } else if (type == 'IDAT') {
        idat.add(data);
      }
      pos += 8 + length + 4; // length + type + data + CRC
    }

    if (bitDepth != 8 || (colorType != 6 && colorType != 2)) {
      throw UnsupportedError(
        'DecodedPng only supports 8-bit RGB/RGBA PNGs '
        '(bitDepth=$bitDepth, colorType=$colorType)',
      );
    }
    final channels = colorType == 6 ? 4 : 3;

    final raw = Uint8List.fromList(ZLibDecoder().convert(idat.toBytes()));
    final stride = width * channels;
    final out = Uint8List(width * height * 4);
    var prev = Uint8List(stride);
    var idx = 0;
    for (var y = 0; y < height; y++) {
      final filterType = raw[idx++];
      final line = Uint8List.sublistView(raw, idx, idx + stride);
      idx += stride;
      final cur = Uint8List(stride);
      for (var x = 0; x < stride; x++) {
        final a = x >= channels ? cur[x - channels] : 0;
        final b = prev[x];
        final c = x >= channels ? prev[x - channels] : 0;
        final raw8 = line[x];
        cur[x] = switch (filterType) {
          0 => raw8,
          1 => (raw8 + a) & 0xff,
          2 => (raw8 + b) & 0xff,
          3 => (raw8 + ((a + b) >> 1)) & 0xff,
          4 => (raw8 + _paeth(a, b, c)) & 0xff,
          _ => throw UnsupportedError('Unknown PNG filter type $filterType'),
        };
      }
      for (var x = 0; x < width; x++) {
        final srcOffset = x * channels;
        final dstOffset = (y * width + x) * 4;
        out[dstOffset] = cur[srcOffset];
        out[dstOffset + 1] = cur[srcOffset + 1];
        out[dstOffset + 2] = cur[srcOffset + 2];
        out[dstOffset + 3] = channels == 4 ? cur[srcOffset + 3] : 255;
      }
      prev = cur;
    }

    return DecodedPng._(width, height, out);
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }

  /// The `(r, g, b, a)` pixel at `(x, y)`.
  (int, int, int, int) pixel(int x, int y) {
    final o = (y * width + x) * 4;
    return (_rgba[o], _rgba[o + 1], _rgba[o + 2], _rgba[o + 3]);
  }

  /// Count of pixels whose alpha channel is above [threshold] — a proxy for
  /// "how much ink is on the canvas", used to compare coverage between two
  /// renders (e.g. a dashed stroke must cover less than a solid one).
  int countPaintedPixels({int threshold = 0}) {
    var count = 0;
    for (var i = 3; i < _rgba.length; i += 4) {
      if (_rgba[i] > threshold) count++;
    }
    return count;
  }
}
