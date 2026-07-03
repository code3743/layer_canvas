import 'geometry.dart';

/// How overlapping/self-intersecting regions of a [LayerPath] are filled.
/// Only meaningful for [LayerPaintStyle.fill]/`fillAndStroke` — ignored for
/// a stroke-only paint.
enum FillRule {
  /// A point is inside the shape if the sum of signed crossings of a ray
  /// from it is non-zero. Self-intersecting shapes (e.g. a five-pointed
  /// star drawn as one continuous outline) fill solid all the way through.
  nonZero,

  /// A point is inside the shape if a ray from it crosses the outline an
  /// odd number of times. The same self-intersecting star instead leaves
  /// the innermost overlapping region unfilled.
  evenOdd,
}

/// A single step of a [LayerPath]'s geometry.
///
/// Coordinates on every command are absolute, in the painted layer's own
/// local space — the same origin `(0, 0)` used by e.g. [RectangleLayer]'s
/// own geometry — not fractional like [Gradient]'s.
sealed class PathCommand {
  const PathCommand();
}

/// Starts a new subpath at [point] without drawing anything.
class MoveTo extends PathCommand {
  final Point2D point;
  const MoveTo(this.point);

  @override
  bool operator ==(Object other) => other is MoveTo && other.point == point;

  @override
  int get hashCode => point.hashCode;

  @override
  String toString() => 'MoveTo($point)';
}

/// Draws a straight line from the current point to [point].
class LineTo extends PathCommand {
  final Point2D point;
  const LineTo(this.point);

  @override
  bool operator ==(Object other) => other is LineTo && other.point == point;

  @override
  int get hashCode => point.hashCode;

  @override
  String toString() => 'LineTo($point)';
}

/// Draws a quadratic Bézier curve from the current point to [point], using
/// [control] as its single control point.
class QuadraticBezierTo extends PathCommand {
  final Point2D control;
  final Point2D point;
  const QuadraticBezierTo(this.control, this.point);

  @override
  bool operator ==(Object other) =>
      other is QuadraticBezierTo &&
      other.control == control &&
      other.point == point;

  @override
  int get hashCode => Object.hash(control, point);

  @override
  String toString() => 'QuadraticBezierTo($control, $point)';
}

/// Draws a cubic Bézier curve from the current point to [point], using
/// [control1] and [control2] as its two control points.
class CubicBezierTo extends PathCommand {
  final Point2D control1;
  final Point2D control2;
  final Point2D point;
  const CubicBezierTo(this.control1, this.control2, this.point);

  @override
  bool operator ==(Object other) =>
      other is CubicBezierTo &&
      other.control1 == control1 &&
      other.control2 == control2 &&
      other.point == point;

  @override
  int get hashCode => Object.hash(control1, control2, point);

  @override
  String toString() => 'CubicBezierTo($control1, $control2, $point)';
}

/// Draws an elliptical arc from the current point to [point].
///
/// Uses the same endpoint parameterization as SVG's `A`/`a` path command:
/// [radiusX]/[radiusY] describe the ellipse, [xAxisRotation] (radians)
/// tilts it relative to the local x-axis, and [largeArc]/[sweep] resolve
/// the otherwise-ambiguous choice among the (up to four) ellipses that fit
/// the two endpoints and radii — [largeArc] picks the larger of the two
/// possible arcs, [sweep] picks the clockwise one.
class ArcTo extends PathCommand {
  final double radiusX;
  final double radiusY;
  final double xAxisRotation;
  final bool largeArc;
  final bool sweep;
  final Point2D point;

  const ArcTo({
    required this.radiusX,
    required this.radiusY,
    this.xAxisRotation = 0,
    this.largeArc = false,
    this.sweep = false,
    required this.point,
  });

  @override
  bool operator ==(Object other) =>
      other is ArcTo &&
      other.radiusX == radiusX &&
      other.radiusY == radiusY &&
      other.xAxisRotation == xAxisRotation &&
      other.largeArc == largeArc &&
      other.sweep == sweep &&
      other.point == point;

  @override
  int get hashCode =>
      Object.hash(radiusX, radiusY, xAxisRotation, largeArc, sweep, point);

  @override
  String toString() =>
      'ArcTo(radiusX: $radiusX, radiusY: $radiusY, '
      'xAxisRotation: $xAxisRotation, largeArc: $largeArc, sweep: $sweep, '
      'point: $point)';
}

/// Closes the current subpath with a straight line back to its starting
/// point (the most recent [MoveTo]).
class ClosePath extends PathCommand {
  const ClosePath();

  @override
  bool operator ==(Object other) => other is ClosePath;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ClosePath()';
}

/// An ordered sequence of [PathCommand]s describing arbitrary vector
/// geometry, used as [PathLayer.path].
///
/// Named `LayerPath` rather than `Path` to avoid shadowing `dart:ui`'s
/// `Path` when imported alongside `material.dart`.
///
/// ```dart
/// final triangle = LayerPath([
///   MoveTo(Point2D(50, 0)),
///   LineTo(Point2D(100, 100)),
///   LineTo(Point2D(0, 100)),
///   ClosePath(),
/// ]);
/// ```
class LayerPath {
  final List<PathCommand> commands;

  LayerPath(this.commands)
    : assert(commands.isNotEmpty, 'a LayerPath needs at least one command');

  /// A closed shape connecting [vertices] in order, with a final edge back
  /// to the first vertex.
  factory LayerPath.polygon(List<Point2D> vertices) {
    assert(vertices.length >= 2, 'a polygon needs at least 2 vertices');
    return LayerPath([
      MoveTo(vertices.first),
      for (final vertex in vertices.skip(1)) LineTo(vertex),
      const ClosePath(),
    ]);
  }

  /// An open shape connecting [vertices] in order.
  ///
  /// The default [PathLayer.paint] style is [LayerPaintStyle.fill], which
  /// implicitly closes an open path before filling it — pass
  /// `paint: LayerPaint(style: LayerPaintStyle.stroke)` (or
  /// `fillAndStroke`) if you want the polyline drawn as an open outline
  /// instead of a filled shape.
  factory LayerPath.polyline(List<Point2D> vertices) {
    assert(vertices.length >= 2, 'a polyline needs at least 2 vertices');
    return LayerPath([
      MoveTo(vertices.first),
      for (final vertex in vertices.skip(1)) LineTo(vertex),
    ]);
  }

  /// A circle centered at [center] with the given [radius].
  ///
  /// ```dart
  /// PathLayer(path: LayerPath.circle(const Point2D(50, 50), 40))
  /// ```
  factory LayerPath.circle(Point2D center, double radius) =>
      LayerPath.ellipse(center, radius, radius);

  /// An ellipse centered at [center] with independent [radiusX]/[radiusY].
  ///
  /// Built from two semicircular [ArcTo] arcs, so there's no arc-flag
  /// arithmetic to get right yourself — [ArcTo] is still there directly for
  /// partial arcs/pie slices, but a full circle or ellipse is common enough
  /// to deserve its own one-liner, the same way [polygon] and [polyline]
  /// exist instead of requiring [MoveTo]/[LineTo] every time.
  factory LayerPath.ellipse(Point2D center, double radiusX, double radiusY) {
    assert(radiusX > 0 && radiusY > 0, 'radiusX/radiusY must be positive');
    return LayerPath([
      MoveTo(Point2D(center.x + radiusX, center.y)),
      ArcTo(
        radiusX: radiusX,
        radiusY: radiusY,
        sweep: true,
        point: Point2D(center.x - radiusX, center.y),
      ),
      ArcTo(
        radiusX: radiusX,
        radiusY: radiusY,
        sweep: true,
        point: Point2D(center.x + radiusX, center.y),
      ),
      const ClosePath(),
    ]);
  }

  @override
  String toString() => 'LayerPath($commands)';
}
