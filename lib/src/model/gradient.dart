import 'color.dart';
import 'geometry.dart';

/// How a gradient behaves outside its defined `0.0..1.0` offset range.
enum GradientExtendMode {
  /// The edge colors are extended to fill the remaining area (default).
  pad,

  /// The gradient repeats from the start once the end is reached.
  repeat,

  /// The gradient repeats in alternating mirrored copies.
  reflect,
}

/// A single color stop within a [Gradient]'s ramp.
///
/// [offset] is in the `0.0..1.0` range, where `0.0` is the gradient's start
/// and `1.0` its end.
class GradientStop {
  final double offset;
  final Color32 color;

  const GradientStop(this.offset, this.color);

  @override
  bool operator ==(Object other) =>
      other is GradientStop && other.offset == offset && other.color == color;

  @override
  int get hashCode => Object.hash(offset, color);

  @override
  String toString() => 'GradientStop($offset, $color)';
}

/// A smooth transition between colors, used as a [LayerPaint.gradient] fill
/// source in place of a solid [LayerPaint.color].
///
/// Concrete subclasses ([LinearGradient], [RadialGradient], [ConicGradient])
/// place their geometry in fractional coordinates (`0.0..1.0`) relative to
/// the painted layer's own size — the same convention [LayerTransform.anchor]
/// uses — so a gradient defined once keeps its relative position as the
/// layer is resized, and inherits the layer's rotation/scale automatically.
sealed class Gradient {
  final List<GradientStop> stops;
  final GradientExtendMode extendMode;

  const Gradient({
    required this.stops,
    this.extendMode = GradientExtendMode.pad,
  });
}

/// Builds a [GradientStop] list from parallel [colors]/[positions] lists —
/// [positions] evenly spaced across `0.0..1.0` when omitted, the same
/// default `LinearGradient` uses in Flutter's own `dart:ui`-adjacent
/// painting library.
List<GradientStop> _colorsToStops(
  List<Color32> colors,
  List<double>? positions,
) {
  assert(colors.length >= 2, 'a gradient needs at least 2 colors');
  assert(
    positions == null || positions.length == colors.length,
    'stops must have the same length as colors when provided',
  );
  final resolvedPositions =
      positions ??
      [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
  return [
    for (var i = 0; i < colors.length; i++)
      GradientStop(resolvedPositions[i], colors[i]),
  ];
}

/// A gradient that transitions along a straight line from [start] to [end].
class LinearGradient extends Gradient {
  final Point2D start;
  final Point2D end;

  const LinearGradient({
    required this.start,
    required this.end,
    required super.stops,
    super.extendMode,
  });

  /// Builds [stops] from parallel [colors]/[stops] lists instead of a
  /// [GradientStop] list — [stops] (the `0.0..1.0` position of each color)
  /// default to evenly spaced when omitted, so `colors: [a, b]` alone is
  /// enough for a simple two-color gradient.
  factory LinearGradient.colors({
    required Point2D start,
    required Point2D end,
    required List<Color32> colors,
    List<double>? stops,
    GradientExtendMode extendMode = GradientExtendMode.pad,
  }) {
    return LinearGradient(
      start: start,
      end: end,
      stops: _colorsToStops(colors, stops),
      extendMode: extendMode,
    );
  }

  @override
  String toString() =>
      'LinearGradient(start: $start, end: $end, stops: $stops, '
      'extendMode: $extendMode)';
}

/// A gradient that radiates outward from [center] up to [radius].
///
/// [radius] is fractional relative to the layer's own width; on a
/// non-square layer the gradient circle is stretched to match the layer's
/// aspect ratio.
class RadialGradient extends Gradient {
  final Point2D center;
  final double radius;

  const RadialGradient({
    required this.center,
    required this.radius,
    required super.stops,
    super.extendMode,
  });

  /// Builds [stops] from parallel [colors]/[stops] lists — see
  /// [LinearGradient.colors] for the exact semantics.
  factory RadialGradient.colors({
    required Point2D center,
    required double radius,
    required List<Color32> colors,
    List<double>? stops,
    GradientExtendMode extendMode = GradientExtendMode.pad,
  }) {
    return RadialGradient(
      center: center,
      radius: radius,
      stops: _colorsToStops(colors, stops),
      extendMode: extendMode,
    );
  }

  @override
  String toString() =>
      'RadialGradient(center: $center, radius: $radius, stops: $stops, '
      'extendMode: $extendMode)';
}

/// A gradient that sweeps around [center], starting at [angle] radians.
class ConicGradient extends Gradient {
  final Point2D center;
  final double angle;

  const ConicGradient({
    required this.center,
    this.angle = 0,
    required super.stops,
    super.extendMode,
  });

  /// Builds [stops] from parallel [colors]/[stops] lists — see
  /// [LinearGradient.colors] for the exact semantics.
  factory ConicGradient.colors({
    required Point2D center,
    double angle = 0,
    required List<Color32> colors,
    List<double>? stops,
    GradientExtendMode extendMode = GradientExtendMode.pad,
  }) {
    return ConicGradient(
      center: center,
      angle: angle,
      stops: _colorsToStops(colors, stops),
      extendMode: extendMode,
    );
  }

  @override
  String toString() =>
      'ConicGradient(center: $center, angle: $angle, stops: $stops, '
      'extendMode: $extendMode)';
}
