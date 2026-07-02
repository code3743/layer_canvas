import '../image_source.dart';
import '../layer.dart';

/// How an [ImageLayer]'s source image is fit inside its [Layer.size].
enum ImageFit { fill, contain, cover, none }

/// A single image, decoded from an [ImageSource] and composited with the
/// common [Layer] transform/opacity/stacking properties.
class ImageLayer extends Layer {
  final ImageSource source;
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
  Map<String, Object?> get properties => {
        'source': source,
        'fit': fit.name,
      };
}
