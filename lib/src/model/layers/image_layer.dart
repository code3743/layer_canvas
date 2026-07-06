import '../image_source.dart';
import '../layer.dart';

/// How an [ImageLayer]'s source image is scaled inside its [Layer.size].
///
/// - `fill` — stretch to fill, ignoring aspect ratio.
/// - `contain` — scale uniformly until one dimension fits; may letterbox.
/// - `cover` — scale uniformly until both dimensions are covered; may crop.
/// - `none` — no scaling; image is drawn at its natural pixel size.
enum ImageFit { fill, contain, cover, none }

/// A single image composited as a layer.
///
/// The image source is a [LayerImageSource] descriptor; actual decoding
/// happens inside the native backend at render time.
class ImageLayer extends Layer {
  /// Where the encoded image bytes come from.
  final LayerImageSource source;

  /// How the image is scaled inside [Layer.size].
  final ImageFit fit;

  /// Creates an image layer from [source].
  ImageLayer({
    required this.source,
    this.fit = ImageFit.fill,
    super.id,
    super.transform,
    super.size,
    super.opacity,
    super.zIndex,
    super.visible,
    super.clipToBounds,
  });

  @override
  String get type => 'image';

  @override
  Map<String, Object?> get properties => {'source': source, 'fit': fit.name};

  @override
  Map<String, Object?> toJson() => {
    ...commonJson(),
    'properties': {'source': source.toJson(), 'fit': fit.name},
  };

  /// Reconstructs an [ImageLayer] from [toJson]'s output. [decodeSource]
  /// resolves the `'source'` field's `LayerImageSource` — pass
  /// `LayerRegistry.decodeImageSource` (the default every built-in decoder
  /// uses) unless you've built your own registry.
  factory ImageLayer.fromJson(
    Map<String, Object?> json, {
    required LayerImageSource Function(Map<String, Object?>) decodeSource,
  }) {
    final common = parseCommonLayerJson(json);
    final properties = json['properties'] as Map<String, Object?>;
    return ImageLayer(
      id: common.id,
      transform: common.transform,
      size: common.size,
      opacity: common.opacity,
      zIndex: common.zIndex,
      visible: common.visible,
      clipToBounds: common.clipToBounds,
      source: decodeSource(properties['source'] as Map<String, Object?>),
      fit: ImageFit.values.byName(properties['fit'] as String),
    );
  }
}
