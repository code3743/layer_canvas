import 'color.dart';
import 'gradient.dart';

/// How a shape's geometry should be painted.
enum LayerPaintStyle { fill, stroke, fillAndStroke }

/// Fill and stroke properties for a shape layer.
///
/// Named `LayerPaint` rather than `Paint` to avoid shadowing `dart:ui`'s
/// `Paint` when imported alongside `material.dart`.
///
/// ```dart
/// const paint = LayerPaint(
///   color: Color32.fromRGB(0, 120, 255),
///   style: LayerPaintStyle.fillAndStroke,
///   strokeWidth: 2,
/// );
/// ```
class LayerPaint {
  final Color32 color;
  final LayerPaintStyle style;
  final double strokeWidth;

  /// When set, paints the shape (both fill and stroke) with this gradient
  /// instead of the solid [color].
  final Gradient? gradient;

  const LayerPaint({
    this.color = Color32.black,
    this.style = LayerPaintStyle.fill,
    this.strokeWidth = 1.0,
    this.gradient,
  });

  LayerPaint copyWith({
    Color32? color,
    LayerPaintStyle? style,
    double? strokeWidth,
    Gradient? gradient,
  }) {
    return LayerPaint(
      color: color ?? this.color,
      style: style ?? this.style,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      gradient: gradient ?? this.gradient,
    );
  }

  @override
  String toString() =>
      'LayerPaint(color: $color, style: $style, '
      'strokeWidth: $strokeWidth, gradient: $gradient)';
}
