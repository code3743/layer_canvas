import 'color.dart';

enum LayerPaintStyle { fill, stroke, fillAndStroke }

/// Describes how a shape should be painted: fill color, stroke color/width.
///
/// This is intentionally minimal and backend-agnostic — it only describes
/// *what* to paint, never *how* a specific graphics backend paints it.
///
/// Named `LayerPaint` rather than `Paint` on purpose: `dart:ui` (and
/// therefore every Flutter app) already exports a `Paint`, and this
/// package is meant to be imported unprefixed alongside `material.dart`.
class LayerPaint {
  final Color32 color;
  final LayerPaintStyle style;
  final double strokeWidth;

  const LayerPaint({
    this.color = Color32.black,
    this.style = LayerPaintStyle.fill,
    this.strokeWidth = 1.0,
  });

  LayerPaint copyWith({
    Color32? color,
    LayerPaintStyle? style,
    double? strokeWidth,
  }) {
    return LayerPaint(
      color: color ?? this.color,
      style: style ?? this.style,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  @override
  String toString() =>
      'LayerPaint(color: $color, style: $style, strokeWidth: $strokeWidth)';
}
