import 'group.dart';
import 'image_source.dart';
import 'layer.dart';
import 'layers/image_layer.dart';
import 'layers/path_layer.dart';
import 'layers/rectangle_layer.dart';
import 'layers/text_layer.dart';

/// Decodes a JSON map (as produced by [Layer.toJson]) back into a [Layer].
typedef LayerFromJson = Layer Function(Map<String, Object?> json);

/// Decodes a JSON map (as produced by [LayerImageSource.toJson]) back into a
/// [LayerImageSource].
typedef ImageSourceFromJson =
    LayerImageSource Function(Map<String, Object?> json);

/// Maps a serialized [Layer.type]/[LayerImageSource] `'type'` tag back to a
/// decoder, so `Scene.fromJson` can reconstruct a polymorphic layer/
/// image-source tree without hardcoding every possible subclass — the same
/// "subclass it, no core changes needed" extensibility [Layer]'s own doc
/// comment already promises for rendering, extended to JSON round-tripping.
///
/// The five built-in layer kinds (`rectangle`/`text`/`image`/`path`/`group`)
/// and two built-in image sources (`file`/`memory`) are registered by
/// default. A custom [Layer] or [LayerImageSource] subclass that implements
/// `toJson` needs a matching decoder registered here before
/// `Scene.fromJson` can reconstruct a scene containing one — otherwise it
/// throws [ArgumentError] on that unknown `'type'` tag.
class LayerRegistry {
  LayerRegistry._();

  static final Map<String, LayerFromJson> _layerDecoders = {
    'rectangle': RectangleLayer.fromJson,
    'text': TextLayer.fromJson,
    'image': (json) => ImageLayer.fromJson(json, decodeSource: decodeImageSource),
    'path': PathLayer.fromJson,
    'group': (json) => Group.fromJson(json, decodeChild: decodeLayer),
  };

  static final Map<String, ImageSourceFromJson> _imageSourceDecoders = {
    'file': FileImageSource.fromJson,
    'memory': MemoryImageSource.fromJson,
  };

  /// Registers [decoder] for [type], so a [Layer] subclass whose `type`
  /// getter returns [type] can round-trip through `Scene.toJson`/
  /// `Scene.fromJson` (including nested inside a [Group]). Replaces any
  /// decoder already registered under [type], including a built-in one.
  static void registerLayer(String type, LayerFromJson decoder) {
    _layerDecoders[type] = decoder;
  }

  /// Registers [decoder] for [type], so a [LayerImageSource] subclass whose
  /// `toJson` emits `'type': type` can round-trip through `Scene.toJson`/
  /// `Scene.fromJson` (including as an [ImageLayer]'s source or a [Scene]'s
  /// background). Replaces any decoder already registered under [type],
  /// including a built-in one.
  static void registerImageSource(String type, ImageSourceFromJson decoder) {
    _imageSourceDecoders[type] = decoder;
  }

  /// Decodes [json] into a [Layer] by dispatching on its `'type'` field.
  /// Throws [ArgumentError] if no decoder is registered for that type.
  static Layer decodeLayer(Map<String, Object?> json) {
    final type = json['type'] as String;
    final decoder = _layerDecoders[type];
    if (decoder == null) {
      throw ArgumentError(
        'Unknown layer type "$type" - register a decoder first via '
        'LayerRegistry.registerLayer.',
      );
    }
    return decoder(json);
  }

  /// Decodes [json] into a [LayerImageSource] by dispatching on its
  /// `'type'` field. Throws [ArgumentError] if no decoder is registered for
  /// that type.
  static LayerImageSource decodeImageSource(Map<String, Object?> json) {
    final type = json['type'] as String;
    final decoder = _imageSourceDecoders[type];
    if (decoder == null) {
      throw ArgumentError(
        'Unknown image source type "$type" - register a decoder first via '
        'LayerRegistry.registerImageSource.',
      );
    }
    return decoder(json);
  }
}
