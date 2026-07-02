import '../geometry.dart';
import '../layer.dart';
import '../paint.dart';

/// A filled and/or stroked rectangle, optionally with rounded corners.
class RectangleLayer extends Layer {
  final LayerPaint paint;
  final double cornerRadius;

  RectangleLayer({
    required Size2D size,
    this.paint = const LayerPaint(),
    this.cornerRadius = 0,
    super.id,
    super.transform,
    super.opacity,
    super.zIndex,
    super.visible,
  }) : super(size: size);

  @override
  String get type => 'rectangle';

  @override
  Map<String, Object?> get properties => {
        'paint': paint,
        'cornerRadius': cornerRadius,
      };
}
