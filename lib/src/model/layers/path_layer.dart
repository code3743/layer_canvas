import '../color.dart';
import '../geometry.dart';
import '../layer.dart';
import '../paint.dart';
import '../path.dart';
import '../transform.dart';

/// Arbitrary vector geometry — lines and Bézier curves, a circle/ellipse,
/// or a polygon/polyline built from a list of vertices — filled and/or
/// stroked with a [LayerPaint].
///
/// ```dart
/// PathLayer(
///   path: LayerPath.polygon([
///     Point2D(50, 0),
///     Point2D(100, 100),
///     Point2D(0, 100),
///   ]),
///   paint: const LayerPaint(color: Color32.fromRGB(0, 180, 90)),
/// )
///
/// PathLayer(
///   path: LayerPath.circle(Point2D(50, 50), 40),
///   paint: const LayerPaint(color: Color32.fromRGB(0, 180, 90)),
/// )
/// ```
class PathLayer extends Layer {
  final LayerPath path;
  final LayerPaint paint;
  final FillRule fillRule;

  /// [size] is only used to place the rotation/scale pivot when
  /// [LayerTransform.anchor] isn't `(0, 0)` — unlike [RectangleLayer], it
  /// never clips or scales [path] itself, since [path]'s own coordinates
  /// already fully describe what's drawn. When omitted, the pivot falls
  /// back to this layer's local origin `(0, 0)`, same as any other layer
  /// with no explicit size; pass a [size] describing [path]'s intended
  /// bounding box if you want rotation/scale to pivot around its visual
  /// center instead.
  PathLayer({
    required this.path,
    this.paint = const LayerPaint(),
    this.fillRule = FillRule.nonZero,
    super.id,
    super.transform,
    super.size,
    super.opacity,
    super.zIndex,
    super.visible,
  });

  /// A solid-filled [path] — [color] directly, without building
  /// [LayerPaint] yourself. For a stroke, a gradient, or fill+stroke
  /// together, use the main constructor with an explicit [paint].
  ///
  /// ```dart
  /// PathLayer.filled(path: LayerPath.circle(const Point2D(50, 50), 40), color: Color32.fromRGB(0, 180, 90))
  /// ```
  factory PathLayer.filled({
    required LayerPath path,
    required Color32 color,
    FillRule fillRule = FillRule.nonZero,
    String? id,
    LayerTransform transform = const LayerTransform(),
    Size2D? size,
    double opacity = 1.0,
    int zIndex = 0,
    bool visible = true,
  }) {
    return PathLayer(
      path: path,
      paint: LayerPaint(color: color),
      fillRule: fillRule,
      id: id,
      transform: transform,
      size: size,
      opacity: opacity,
      zIndex: zIndex,
      visible: visible,
    );
  }

  @override
  String get type => 'path';

  @override
  Map<String, Object?> get properties => {
    'path': path,
    'paint': paint,
    'fillRule': fillRule.name,
  };
}
