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
  /// The solid fill/stroke color, used unless [gradient] is set.
  final Color32 color;

  /// Whether the shape is filled, stroked, or both.
  final LayerPaintStyle style;

  /// Width of the stroke, in the [Scene]'s logical pixel space. Ignored
  /// unless [style] is [LayerPaintStyle.stroke] or `fillAndStroke`.
  final double strokeWidth;

  /// When set, paints the shape (both fill and stroke) with this gradient
  /// instead of the solid [color].
  final Gradient? gradient;

  /// Creates a paint. Defaults to a solid black fill.
  const LayerPaint({
    this.color = Color32.black,
    this.style = LayerPaintStyle.fill,
    this.strokeWidth = 1.0,
    this.gradient,
  });

  /// Returns a copy with the given fields replaced.
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
