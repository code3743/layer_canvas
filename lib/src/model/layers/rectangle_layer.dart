import '../color.dart';
import '../geometry.dart';
import '../layer.dart';
import '../paint.dart';
import '../transform.dart';

/// A filled and/or stroked rectangle with optional rounded corners.
///
/// ```dart
/// RectangleLayer(
///   size: const Size2D(200, 80),
///   paint: const LayerPaint(
///     color: Color32.fromARGB(180, 0, 0, 0),
///     style: LayerPaintStyle.fill,
///   ),
///   cornerRadius: 12,
/// )
/// ```
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

  /// A solid-filled rectangle — [width]/[height]/[color] directly, without
  /// building [Size2D] or [LayerPaint] yourself. For a stroke, a gradient,
  /// or fill+stroke together, use the main constructor with an explicit
  /// [paint].
  ///
  /// ```dart
  /// RectangleLayer.filled(width: 800, height: 600, color: Color32.fromRGB(30, 30, 30))
  /// ```
  factory RectangleLayer.filled({
    required double width,
    required double height,
    required Color32 color,
    double cornerRadius = 0,
    String? id,
    LayerTransform transform = const LayerTransform(),
    double opacity = 1.0,
    int zIndex = 0,
    bool visible = true,
  }) {
    return RectangleLayer(
      size: Size2D(width, height),
      paint: LayerPaint(color: color),
      cornerRadius: cornerRadius,
      id: id,
      transform: transform,
      opacity: opacity,
      zIndex: zIndex,
      visible: visible,
    );
  }

  @override
  String get type => 'rectangle';

  @override
  Map<String, Object?> get properties => {
    'paint': paint,
    'cornerRadius': cornerRadius,
  };
}
