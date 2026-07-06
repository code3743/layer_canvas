import 'dart:typed_data';

/// Reads a single pixel out of an uncompressed 32-bpp BMP — just enough of
/// the format to verify [Renderer]'s BMP output actually contains the
/// colors it was asked to paint, not just the right magic bytes.
(int, int, int) readBmpPixel(Uint8List bytes, int x, int y) {
  final data = ByteData.sublistView(bytes);
  final dataOffset = data.getUint32(10, Endian.little);
  final width = data.getInt32(18, Endian.little);
  final rawHeight = data.getInt32(22, Endian.little);
  final bpp = data.getUint16(28, Endian.little);
  if (bpp != 32) {
    throw UnsupportedError('readBmpPixel only supports 32-bpp BMPs');
  }

  final topDown = rawHeight < 0;
  final height = rawHeight.abs();
  final rowSize = ((width * bpp + 31) ~/ 32) * 4;
  final row = topDown ? y : (height - 1 - y);
  final offset = dataOffset + row * rowSize + x * 4;

  return (bytes[offset + 2], bytes[offset + 1], bytes[offset]); // BGR -> RGB
}
