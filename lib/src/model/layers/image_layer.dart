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
  final LayerImageSource source;
  final ImageFit fit;

  ImageLayer({
    required this.source,
    this.fit = ImageFit.fill,
    super.id,
    super.transform,
    super.size,
    super.opacity,
    super.zIndex,
    super.visible,
  });

  @override
  String get type => 'image';

  @override
  Map<String, Object?> get properties => {'source': source, 'fit': fit.name};
}
