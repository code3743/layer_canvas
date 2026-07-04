import 'dart:math' as math;

import '../model/geometry.dart';
import '../model/path.dart';

/// An affine 2D transform matrix, in the same `(a, b, c, d, e, f)` form
/// SVG's own `matrix()` transform function uses:
/// ```
/// | a c e |   | x |
/// | b d f | * | y |
/// | 0 0 1 |   | 1 |
/// ```
///
/// Internal to the SVG importer — never exposed publicly. Every SVG
/// `transform` (including shear, which [LayerTransform] can't represent)
/// gets baked directly into absolute path coordinates via this matrix
/// during parsing, rather than becoming a runtime `LayerTransform`.
class SvgMatrix {
  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  const SvgMatrix(this.a, this.b, this.c, this.d, this.e, this.f);

  static const identity = SvgMatrix(1, 0, 0, 1, 0, 0);

  factory SvgMatrix.translate(double tx, [double ty = 0]) =>
      SvgMatrix(1, 0, 0, 1, tx, ty);

  factory SvgMatrix.scale(double sx, [double? sy]) =>
      SvgMatrix(sx, 0, 0, sy ?? sx, 0, 0);

  /// [degrees] follows SVG's convention (clockwise, since SVG's y-axis
  /// points down). When [cx]/[cy] are given, rotates around that point
  /// instead of the local origin.
  factory SvgMatrix.rotate(double degrees, [double cx = 0, double cy = 0]) {
    final radians = degrees * math.pi / 180;
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    final rotation = SvgMatrix(cosA, sinA, -sinA, cosA, 0, 0);
    if (cx == 0 && cy == 0) return rotation;
    return SvgMatrix.translate(
      cx,
      cy,
    ).multiply(rotation).multiply(SvgMatrix.translate(-cx, -cy));
  }

  factory SvgMatrix.skewX(double degrees) =>
      SvgMatrix(1, 0, math.tan(degrees * math.pi / 180), 1, 0, 0);

  factory SvgMatrix.skewY(double degrees) =>
      SvgMatrix(1, math.tan(degrees * math.pi / 180), 0, 1, 0, 0);

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  double get determinant => a * d - b * c;

  /// Returns `this * other` — applying the result to a point is
  /// equivalent to first applying [other], then applying `this` to that
  /// result. Composing SVG transform-list functions left to right means
  /// calling `result = result.multiply(next)` for each one in turn.
  SvgMatrix multiply(SvgMatrix other) {
    return SvgMatrix(
      a * other.a + c * other.b,
      b * other.a + d * other.b,
      a * other.c + c * other.d,
      b * other.c + d * other.d,
      a * other.e + c * other.f + e,
      b * other.e + d * other.f + f,
    );
  }

  Point2D apply(Point2D p) =>
      Point2D(a * p.x + c * p.y + e, b * p.x + d * p.y + f);
}

final _transformFunctionPattern = RegExp(r'(\w+)\s*\(([^)]*)\)');

/// Parses an SVG `transform` attribute value into a single composed
/// [SvgMatrix]. Unrecognized function names (or ones with the wrong
/// argument count) are skipped — contributing identity — rather than
/// failing the whole parse.
SvgMatrix parseSvgTransform(String value) {
  var result = SvgMatrix.identity;
  for (final match in _transformFunctionPattern.allMatches(value)) {
    final name = match.group(1)!;
    final numbers = (match.group(2) ?? '')
        .split(RegExp(r'[,\s]+'))
        .where((s) => s.isNotEmpty)
        .map(double.tryParse)
        .toList();
    if (numbers.any((n) => n == null)) continue;
    final args = numbers.cast<double>();

    final matrix = switch (name) {
      'translate' when args.isNotEmpty => SvgMatrix.translate(
        args[0],
        args.length > 1 ? args[1] : 0,
      ),
      'scale' when args.isNotEmpty => SvgMatrix.scale(
        args[0],
        args.length > 1 ? args[1] : null,
      ),
      'rotate' when args.isNotEmpty => SvgMatrix.rotate(
        args[0],
        args.length > 2 ? args[1] : 0,
        args.length > 2 ? args[2] : 0,
      ),
      'matrix' when args.length == 6 => SvgMatrix(
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
      ),
      'skewx' when args.isNotEmpty => SvgMatrix.skewX(args[0]),
      'skewy' when args.isNotEmpty => SvgMatrix.skewY(args[0]),
      _ => SvgMatrix.identity,
    };
    result = result.multiply(matrix);
  }
  return result;
}

// Relative tolerance used to decide whether a matrix is a "similarity"
// (uniform scale + rotation + optional reflection, no shear) — the case
// where an ellipse stays an ellipse after the transform.
const double _similarityTolerance = 1e-4;

/// Applies [matrix] to every point in [commands], baking the transform
/// directly into absolute coordinates.
///
/// An [ArcTo] whose ellipse survives the transform intact (uniform scale +
/// rotation, no shear) keeps using the exact native arc command with
/// adjusted radii/rotation/sweep; otherwise (non-uniform scale or skew
/// present) it's approximated with cubic Béziers instead, since
/// transforming an elliptical arc's endpoint parameterization under a
/// general affine map would require converting to conic form and back —
/// Bézier control points, by contrast, transform correctly under any
/// affine map by just transforming the points themselves.
List<PathCommand> applySvgMatrix(List<PathCommand> commands, SvgMatrix matrix) {
  if (matrix.isIdentity) return commands;

  final result = <PathCommand>[];
  var currentPoint = Point2D.zero; // in the ORIGINAL (untransformed) space.
  for (final command in commands) {
    switch (command) {
      case MoveTo(:final point):
        result.add(MoveTo(matrix.apply(point)));
        currentPoint = point;
      case LineTo(:final point):
        result.add(LineTo(matrix.apply(point)));
        currentPoint = point;
      case QuadraticBezierTo(:final control, :final point):
        result.add(
          QuadraticBezierTo(matrix.apply(control), matrix.apply(point)),
        );
        currentPoint = point;
      case CubicBezierTo(:final control1, :final control2, :final point):
        result.add(
          CubicBezierTo(
            matrix.apply(control1),
            matrix.apply(control2),
            matrix.apply(point),
          ),
        );
        currentPoint = point;
      case ClosePath():
        result.add(command);
      case final ArcTo arc:
        result.addAll(_transformArc(currentPoint, arc, matrix));
        currentPoint = arc.point;
    }
  }
  return result;
}

List<PathCommand> _transformArc(Point2D start, ArcTo arc, SvgMatrix matrix) {
  final sx = math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
  final sy = math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);
  final dot = matrix.a * matrix.c + matrix.b * matrix.d;
  final scaleMagnitude = math.max(math.max(sx, sy), 1e-9);

  final isUniformScale =
      (sx - sy).abs() <= _similarityTolerance * scaleMagnitude;
  final isOrthogonal = dot.abs() <= _similarityTolerance * sx * sy;

  if (isUniformScale && isOrthogonal) {
    final rot = arc.xAxisRotation;
    final axisX = matrix.a * math.cos(rot) + matrix.c * math.sin(rot);
    final axisY = matrix.b * math.cos(rot) + matrix.d * math.sin(rot);
    final isReflection = matrix.determinant < 0;

    return [
      ArcTo(
        radiusX: arc.radiusX * sx,
        radiusY: arc.radiusY * sy,
        xAxisRotation: math.atan2(axisY, axisX),
        largeArc: arc.largeArc,
        sweep: isReflection ? !arc.sweep : arc.sweep,
        point: matrix.apply(arc.point),
      ),
    ];
  }

  // Shear or non-uniform scale: approximate with cubic Béziers in the
  // original (untransformed) space first, then map each control point
  // through `matrix` — correct for any affine map.
  return [
    for (final bezier in arcToBeziers(start, arc))
      CubicBezierTo(
        matrix.apply(bezier.control1),
        matrix.apply(bezier.control2),
        matrix.apply(bezier.point),
      ),
  ];
}

/// Approximates an SVG-parameterized elliptical arc from [start] to
/// [arc]'s endpoint as a sequence of cubic Bézier curves (each spanning at
/// most 90°), using the standard endpoint-to-center conversion from the
/// SVG implementation notes
/// (https://www.w3.org/TR/SVG/implnote.html#ArcConversionEndpointToCenter).
List<CubicBezierTo> arcToBeziers(Point2D start, ArcTo arc) {
  final x1 = start.x, y1 = start.y;
  final x2 = arc.point.x, y2 = arc.point.y;

  if ((x1 - x2).abs() < 1e-12 && (y1 - y2).abs() < 1e-12) return const [];

  var rx = arc.radiusX.abs();
  var ry = arc.radiusY.abs();
  if (rx < 1e-12 || ry < 1e-12) {
    // Degenerate ellipse - draw as a straight (flat) "curve" instead.
    return [CubicBezierTo(start, arc.point, arc.point)];
  }

  final phi = arc.xAxisRotation;
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);

  final dx2 = (x1 - x2) / 2;
  final dy2 = (y1 - y2) / 2;
  final x1p = cosPhi * dx2 + sinPhi * dy2;
  final y1p = -sinPhi * dx2 + cosPhi * dy2;

  final lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lambda > 1) {
    final scale = math.sqrt(lambda);
    rx *= scale;
    ry *= scale;
  }

  final rxSq = rx * rx, rySq = ry * ry;
  final x1pSq = x1p * x1p, y1pSq = y1p * y1p;
  final sign = arc.largeArc != arc.sweep ? 1.0 : -1.0;
  final numerator = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq;
  final denominator = rxSq * y1pSq + rySq * x1pSq;
  final co = denominator == 0
      ? 0.0
      : sign * math.sqrt(math.max(0, numerator) / denominator);
  final cxp = co * (rx * y1p) / ry;
  final cyp = co * -(ry * x1p) / rx;

  final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
  final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

  double angleBetween(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    var angle = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) angle = -angle;
    return angle;
  }

  final theta1 = angleBetween(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  var deltaTheta = angleBetween(
    (x1p - cxp) / rx,
    (y1p - cyp) / ry,
    (-x1p - cxp) / rx,
    (-y1p - cyp) / ry,
  );
  if (!arc.sweep && deltaTheta > 0) deltaTheta -= 2 * math.pi;
  if (arc.sweep && deltaTheta < 0) deltaTheta += 2 * math.pi;

  final segmentCount = (deltaTheta.abs() / (math.pi / 2)).ceil().clamp(1, 4);
  final segmentSweep = deltaTheta / segmentCount;

  Point2D ellipsePoint(double u, double v) => Point2D(
    cx + rx * u * cosPhi - ry * v * sinPhi,
    cy + rx * u * sinPhi + ry * v * cosPhi,
  );

  final result = <CubicBezierTo>[];
  for (var i = 0; i < segmentCount; i++) {
    final segStart = theta1 + i * segmentSweep;
    final segEnd = segStart + segmentSweep;
    // Standard tangent-matching control-point offset for a Bézier segment
    // spanning at most 90° - exact at 90° (kappa ≈ 0.5523) and shrinks
    // smoothly to 0 as segmentSweep -> 0.
    final alpha = 4 / 3 * math.tan(segmentSweep / 4);

    final cosStart = math.cos(segStart), sinStart = math.sin(segStart);
    final cosEnd = math.cos(segEnd), sinEnd = math.sin(segEnd);

    result.add(
      CubicBezierTo(
        ellipsePoint(cosStart - alpha * sinStart, sinStart + alpha * cosStart),
        ellipsePoint(cosEnd + alpha * sinEnd, sinEnd - alpha * cosEnd),
        ellipsePoint(cosEnd, sinEnd),
      ),
    );
  }

  return result;
}
