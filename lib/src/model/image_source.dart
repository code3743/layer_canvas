import 'dart:typed_data';

/// Where the raw image data for an [ImageLayer] (or a [Scene] background)
/// comes from.
///
/// This is a pure descriptor — the core engine does not decode images here.
/// New source kinds (e.g. a Flutter asset-bundle resolver, provided by an
/// integration layer built on top of this package) can be added as new
/// subclasses without touching this file.
abstract class ImageSource {
  const ImageSource();

  const factory ImageSource.file(String path) = FileImageSource;

  const factory ImageSource.memory(Uint8List bytes) = MemoryImageSource;
}

/// An image read from a file path on disk at render time.
class FileImageSource extends ImageSource {
  final String path;

  const FileImageSource(this.path);

  @override
  String toString() => 'FileImageSource($path)';
}

/// An image already available as encoded bytes (PNG/JPEG/etc.) in memory.
class MemoryImageSource extends ImageSource {
  final Uint8List bytes;

  const MemoryImageSource(this.bytes);

  @override
  String toString() => 'MemoryImageSource(${bytes.lengthInBytes} bytes)';
}
