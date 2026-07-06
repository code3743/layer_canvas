import 'dart:math' as math;

import '../model/geometry.dart';
import '../model/path.dart';
import '../svg/svg_transform.dart' show arcToBeziers;

/// Number of line segments a single Bézier curve is subdivided into when
/// flattening for dashing - fine enough that the seams are invisible at
/// typical stroke widths, without the cost/complexity of adaptive
/// subdivision.
const _curveFlattenSteps = 24;

/// Splits [path] into its "on" segments per [dashArray]/[dashOffset],
/// returning a new [LayerPath] containing only those segments as
/// MoveTo/LineTo commands - i.e. bakes dashing into plain geometry instead
/// of relying on Blend2D's own dash support, which silently draws a solid
/// line regardless of the dash array
/// (https://github.com/blend2d/blend2d/issues/48, open since 2019: the
/// stroker's dash fields are stored but never consumed when generating
/// stroke geometry).
///
/// Curves (including arcs, via [arcToBeziers]) are flattened into short
/// line segments first, since dashing needs to measure and split by arc
/// length and an exact analytic split of a Bézier curve by length has no
/// closed form.
///
/// [dashArray] must be non-empty — callers should skip calling this
/// entirely for a solid stroke — and its lengths are assumed non-negative.
LayerPath dashPath(LayerPath path, List<double> dashArray, double dashOffset) {
  assert(dashArray.isNotEmpty, 'dashPath requires a non-empty dashArray');

  // SVG/CSS convention: an odd-length pattern is conceptually doubled so it
  // has a well-defined repeating on/off cycle (e.g. [4] behaves as [4, 4]).
  final pattern = dashArray.length.isOdd
      ? [...dashArray, ...dashArray]
      : dashArray;
  final total = pattern.fold<double>(0, (sum, length) => sum + length);
  if (total <= 0) {
    // Degenerate pattern (e.g. all zeros) - draw the solid path rather than
    // nothing, same "never fail, degrade gracefully" philosophy as an
    // unrecognized layer kind elsewhere in this package.
    return path;
  }

  final onRuns = <List<Point2D>>[
    for (final polyline in _flattenToPolylines(path))
      ..._dashPolyline(polyline, pattern, total, dashOffset),
  ];

  if (onRuns.isEmpty) {
    // The whole path fell in "off" phases - an empty stroke is a
    // legitimate (if unusual) result. LayerPath asserts at least one
    // command, so emit a degenerate single-point MoveTo that paints
    // nothing instead of throwing.
    return LayerPath(const [MoveTo(Point2D.zero)]);
  }

  return LayerPath([
    for (final run in onRuns) ...[
      MoveTo(run.first),
      for (final point in run.skip(1)) LineTo(point),
    ],
  ]);
}

/// Flattens [path] into one polyline per subpath (split on [MoveTo]), each
/// a list of straight-line vertices approximating the original curves.
/// [ClosePath] appends the subpath's start point, so the closing edge is
/// itself dashed like any other segment.
List<List<Point2D>> _flattenToPolylines(LayerPath path) {
  final result = <List<Point2D>>[];
  List<Point2D>? current;
  var currentPoint = Point2D.zero;
  var subpathStart = Point2D.zero;

  void finish() {
    if (current != null && current!.length >= 2) {
      result.add(current!);
    }
    current = null;
  }

  for (final command in path.commands) {
    switch (command) {
      case MoveTo(:final point):
        finish();
        current = [point];
        currentPoint = point;
        subpathStart = point;
      case LineTo(:final point):
        current ??= [currentPoint];
        current!.add(point);
        currentPoint = point;
      case QuadraticBezierTo(:final control, :final point):
        current ??= [currentPoint];
        _flattenQuadratic(current!, currentPoint, control, point);
        currentPoint = point;
      case CubicBezierTo(:final control1, :final control2, :final point):
        current ??= [currentPoint];
        _flattenCubic(current!, currentPoint, control1, control2, point);
        currentPoint = point;
      case final ArcTo arc:
        current ??= [currentPoint];
        for (final bezier in arcToBeziers(currentPoint, arc)) {
          _flattenCubic(
            current!,
            currentPoint,
            bezier.control1,
            bezier.control2,
            bezier.point,
          );
          currentPoint = bezier.point;
        }
      case ClosePath():
        current ??= [currentPoint];
        current!.add(subpathStart);
        currentPoint = subpathStart;
        finish();
    }
  }
  finish();
  return result;
}

void _flattenQuadratic(
  List<Point2D> out,
  Point2D start,
  Point2D control,
  Point2D end,
) {
  for (var i = 1; i <= _curveFlattenSteps; i++) {
    final t = i / _curveFlattenSteps;
    final mt = 1 - t;
    out.add(
      Point2D(
        mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x,
        mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y,
      ),
    );
  }
}

void _flattenCubic(
  List<Point2D> out,
  Point2D start,
  Point2D control1,
  Point2D control2,
  Point2D end,
) {
  for (var i = 1; i <= _curveFlattenSteps; i++) {
    final t = i / _curveFlattenSteps;
    final mt = 1 - t;
    out.add(
      Point2D(
        mt * mt * mt * start.x +
            3 * mt * mt * t * control1.x +
            3 * mt * t * t * control2.x +
            t * t * t * end.x,
        mt * mt * mt * start.y +
            3 * mt * mt * t * control1.y +
            3 * mt * t * t * control2.y +
            t * t * t * end.y,
      ),
    );
  }
}

/// Walks a flattened polyline applying the repeating [pattern] (already
/// normalized to even length, summing to [total] > 0), starting [offset]
/// into it, and returns each contiguous "on" run as its own point list.
List<List<Point2D>> _dashPolyline(
  List<Point2D> points,
  List<double> pattern,
  double total,
  double offset,
) {
  var patternIndex = 0;
  var remaining = pattern[0];
  var on = true;

  var normalizedOffset = offset % total;
  if (normalizedOffset < 0) normalizedOffset += total;
  while (normalizedOffset > 0) {
    final step = math.min(normalizedOffset, remaining);
    remaining -= step;
    normalizedOffset -= step;
    if (remaining <= 1e-9) {
      patternIndex = (patternIndex + 1) % pattern.length;
      remaining = pattern[patternIndex];
      on = !on;
    }
  }

  final runs = <List<Point2D>>[];
  var currentRun = on ? [points.first] : null;

  for (var i = 0; i < points.length - 1; i++) {
    var segmentStart = points[i];
    final segmentEnd = points[i + 1];
    var segmentLength = _distance(segmentStart, segmentEnd);

    while (segmentLength > 0) {
      final step = math.min(segmentLength, remaining);
      final t = step / segmentLength;
      final splitPoint = Point2D(
        segmentStart.x + (segmentEnd.x - segmentStart.x) * t,
        segmentStart.y + (segmentEnd.y - segmentStart.y) * t,
      );

      if (on) {
        currentRun ??= [segmentStart];
        currentRun.add(splitPoint);
      }

      remaining -= step;
      segmentLength -= step;
      segmentStart = splitPoint;

      if (remaining <= 1e-9) {
        if (on && currentRun != null && currentRun.length >= 2) {
          runs.add(currentRun);
        }
        currentRun = null;
        patternIndex = (patternIndex + 1) % pattern.length;
        remaining = pattern[patternIndex];
        on = !on;
        if (on) currentRun = [splitPoint];
      }
    }
  }

  if (on && currentRun != null && currentRun.length >= 2) {
    runs.add(currentRun);
  }

  return runs;
}

double _distance(Point2D a, Point2D b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}
