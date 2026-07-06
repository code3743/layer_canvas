import 'color.dart';
import 'gradient.dart';

/// How a shape's geometry should be painted.
enum LayerPaintStyle { fill, stroke, fillAndStroke }

/// Shape of a stroke's two open ends. Ignored for a closed subpath.
enum StrokeCap {
  /// The stroke ends exactly at the path's endpoint, squared off.
  butt,

  /// The stroke ends in a semicircle centered on the endpoint.
  round,

  /// Like [butt], extended past the endpoint by half the stroke width.
  square,
}

/// Shape drawn where two stroked segments meet.
enum StrokeJoin {
  /// A sharp corner, clamped to a [bevel] once [LayerPaint.miterLimit] is
  /// exceeded (matches the SVG/CSS `miter` default).
  miter,

  /// A rounded corner.
  round,

  /// A flat corner cutting straight across the two segments' outer edges.
  bevel,
}

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

  /// Shape of the stroke's open ends. Ignored for [style]
  /// [LayerPaintStyle.fill] or a closed subpath.
  final StrokeCap strokeCap;

  /// Shape drawn at each corner where two stroked segments meet.
  final StrokeJoin strokeJoin;

  /// How far a [StrokeJoin.miter] corner may extend, as a multiple of
  /// [strokeWidth], before it's clamped to a bevel. Ignored unless
  /// [strokeJoin] is [StrokeJoin.miter].
  final double miterLimit;

  /// Alternating on/off lengths (in the [Scene]'s logical pixel space) the
  /// stroke is divided into, e.g. `[4, 2]` for a 4-on/2-off dash. An empty
  /// list (the default) draws a solid stroke. An odd-length list repeats
  /// (matching SVG/CSS: `[4]` behaves like `[4, 4]`).
  ///
  /// Only takes effect on a [PathLayer]'s stroke — a [RectangleLayer]
  /// currently ignores it and always strokes solid, since dashing is
  /// resolved into plain path geometry rather than delegated to the native
  /// engine (Blend2D's own dash support silently draws a solid line
  /// instead — see https://github.com/blend2d/blend2d/issues/48), and a
  /// rectangle has no [LayerPath] of its own to resolve that geometry
  /// from.
  final List<double> dashArray;

  /// Offset into [dashArray]'s repeating pattern at which the dash starts.
  /// Ignored when [dashArray] is empty, and — like [dashArray] — only takes
  /// effect on a [PathLayer].
  final double dashOffset;

  /// When set, paints the shape (both fill and stroke) with this gradient
  /// instead of the solid [color].
  final Gradient? gradient;

  /// Creates a paint. Defaults to a solid black fill.
  const LayerPaint({
    this.color = Color32.black,
    this.style = LayerPaintStyle.fill,
    this.strokeWidth = 1.0,
    this.strokeCap = StrokeCap.butt,
    this.strokeJoin = StrokeJoin.miter,
    this.miterLimit = 4.0,
    this.dashArray = const [],
    this.dashOffset = 0.0,
    this.gradient,
  });

  /// Returns a copy with the given fields replaced.
  LayerPaint copyWith({
    Color32? color,
    LayerPaintStyle? style,
    double? strokeWidth,
    StrokeCap? strokeCap,
    StrokeJoin? strokeJoin,
    double? miterLimit,
    List<double>? dashArray,
    double? dashOffset,
    Gradient? gradient,
  }) {
    return LayerPaint(
      color: color ?? this.color,
      style: style ?? this.style,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeCap: strokeCap ?? this.strokeCap,
      strokeJoin: strokeJoin ?? this.strokeJoin,
      miterLimit: miterLimit ?? this.miterLimit,
      dashArray: dashArray ?? this.dashArray,
      dashOffset: dashOffset ?? this.dashOffset,
      gradient: gradient ?? this.gradient,
    );
  }

  @override
  String toString() =>
      'LayerPaint(color: $color, style: $style, '
      'strokeWidth: $strokeWidth, strokeCap: $strokeCap, '
      'strokeJoin: $strokeJoin, miterLimit: $miterLimit, '
      'dashArray: $dashArray, dashOffset: $dashOffset, gradient: $gradient)';

  /// Converts to a JSON-safe map, see `Scene.toJson`.
  Map<String, Object?> toJson() => {
    'color': color.toJson(),
    'style': style.name,
    'strokeWidth': strokeWidth,
    'strokeCap': strokeCap.name,
    'strokeJoin': strokeJoin.name,
    'miterLimit': miterLimit,
    'dashArray': dashArray,
    'dashOffset': dashOffset,
    'gradient': gradient?.toJson(),
  };

  /// Reconstructs a [LayerPaint] from [toJson]'s output.
  factory LayerPaint.fromJson(Map<String, Object?> json) {
    final gradientJson = json['gradient'] as Map<String, Object?>?;
    return LayerPaint(
      color: Color32.fromJson(json['color'] as int),
      style: LayerPaintStyle.values.byName(json['style'] as String),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      strokeCap: StrokeCap.values.byName(json['strokeCap'] as String),
      strokeJoin: StrokeJoin.values.byName(json['strokeJoin'] as String),
      miterLimit: (json['miterLimit'] as num).toDouble(),
      dashArray: [
        for (final length in json['dashArray'] as List<Object?>)
          (length as num).toDouble(),
      ],
      dashOffset: (json['dashOffset'] as num).toDouble(),
      gradient: gradientJson == null ? null : Gradient.fromJson(gradientJson),
    );
  }
}
