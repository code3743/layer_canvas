import 'dart:convert';
import 'dart:typed_data';

/// Where the raw image data for an [ImageLayer] (or a [Scene] background)
/// comes from.
///
/// This is a pure descriptor — the core engine does not decode images here.
/// New source kinds (e.g. a Flutter asset-bundle resolver, provided by an
/// integration layer built on top of this package) can be added as new
/// subclasses without touching this file.
///
/// Named `LayerImageSource` rather than `ImageSource` on purpose: several
/// widely used Flutter packages (e.g. `image_picker`) already export an
/// `ImageSource`, and this package is meant to be imported unprefixed
/// alongside them.
abstract class LayerImageSource {
  /// Const constructor for subclasses.
  const LayerImageSource();

  /// An image read from [path] on disk at render time. See [FileImageSource].
  const factory LayerImageSource.file(String path) = FileImageSource;

  /// An image already available as encoded [bytes] in memory. See
  /// [MemoryImageSource].
  const factory LayerImageSource.memory(Uint8List bytes) = MemoryImageSource;

  /// Converts to a JSON-safe map, see `Scene.toJson`. A subclass added
  /// outside this file (per this class's own doc comment above) needs its
  /// own `toJson` override, plus a decoder registered via
  /// `LayerRegistry.registerImageSource` to round-trip through
  /// [Scene.fromJson].
  Map<String, Object?> toJson();
}

/// An image read from a file path on disk at render time.
class FileImageSource extends LayerImageSource {
  /// The file path to read from at render time.
  final String path;

  /// Creates a source reading from [path].
  const FileImageSource(this.path);

  @override
  String toString() => 'FileImageSource($path)';

  @override
  Map<String, Object?> toJson() => {'type': 'file', 'path': path};

  /// Reconstructs a [FileImageSource] from [toJson]'s output.
  factory FileImageSource.fromJson(Map<String, Object?> json) =>
      FileImageSource(json['path'] as String);
}

/// An image already available as encoded bytes (PNG/JPEG/etc.) in memory.
class MemoryImageSource extends LayerImageSource {
  /// The encoded (PNG/JPEG/etc.) image bytes.
  final Uint8List bytes;

  /// Creates a source from already-encoded [bytes].
  const MemoryImageSource(this.bytes);

  @override
  String toString() => 'MemoryImageSource(${bytes.lengthInBytes} bytes)';

  @override
  Map<String, Object?> toJson() => {
    'type': 'memory',
    'bytes': base64Encode(bytes),
  };

  /// Reconstructs a [MemoryImageSource] from [toJson]'s output.
  factory MemoryImageSource.fromJson(Map<String, Object?> json) =>
      MemoryImageSource(base64Decode(json['bytes'] as String));
}
