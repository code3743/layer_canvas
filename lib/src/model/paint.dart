import 'color.dart';

enum PaintStyle { fill, stroke, fillAndStroke }

/// Describes how a shape should be painted: fill color, stroke color/width.
///
/// This is intentionally minimal and backend-agnostic — it only describes
/// *what* to paint, never *how* a specific graphics backend paints it.
class Paint {
  final Color32 color;
  final PaintStyle style;
  final double strokeWidth;

  const Paint({
    this.color = Color32.black,
    this.style = PaintStyle.fill,
    this.strokeWidth = 1.0,
  });

  Paint copyWith({Color32? color, PaintStyle? style, double? strokeWidth}) {
    return Paint(
      color: color ?? this.color,
      style: style ?? this.style,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  @override
  String toString() =>
      'Paint(color: $color, style: $style, strokeWidth: $strokeWidth)';
}
