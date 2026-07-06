import 'package:layer_canvas/layer_canvas.dart';
import 'package:layer_canvas/src/renderer/path_dasher.dart';
import 'package:test/test.dart';

/// Sums the length of every LineTo segment in [path] — used to check total
/// "on" coverage without depending on exact point placement (only the
/// straight-line test below asserts exact coordinates).
double _totalLength(LayerPath path) {
  var total = 0.0;
  Point2D current = Point2D.zero;
  for (final command in path.commands) {
    switch (command) {
      case MoveTo(:final point):
        current = point;
      case LineTo(:final point):
        final dx = point.x - current.x;
        final dy = point.y - current.y;
        total += (dx * dx + dy * dy);
        current = point;
      default:
        break;
    }
  }
  return total;
}

void main() {
  group('dashPath', () {
    test('a 4-on/2-off pattern splits a 10-unit line into two runs', () {
      final path = LayerPath(const [
        MoveTo(Point2D(0, 0)),
        LineTo(Point2D(10, 0)),
      ]);

      final dashed = dashPath(path, const [4, 2], 0);

      // Expect: MoveTo(0,0) LineTo(4,0) [gap] MoveTo(6,0) LineTo(10,0).
      expect(dashed.commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(4, 0)),
        const MoveTo(Point2D(6, 0)),
        const LineTo(Point2D(10, 0)),
      ]);
    });

    test('a dashOffset shifts where the pattern starts', () {
      final path = LayerPath(const [
        MoveTo(Point2D(0, 0)),
        LineTo(Point2D(10, 0)),
      ]);

      // Cycle length is 6 (4 on + 2 off). An offset of 4 starts the path
      // already 4 units into the cycle — i.e. right at the on/off boundary,
      // so it begins in the "off" phase with 2 units left (0-2), then on
      // for 4 (2-6), off for 2 (6-8), then on again until the path ends.
      final dashed = dashPath(path, const [4, 2], 4);

      expect(dashed.commands, [
        const MoveTo(Point2D(2, 0)),
        const LineTo(Point2D(6, 0)),
        const MoveTo(Point2D(8, 0)),
        const LineTo(Point2D(10, 0)),
      ]);
    });

    test('an odd-length pattern doubles, matching SVG/CSS convention', () {
      final path = LayerPath(const [
        MoveTo(Point2D(0, 0)),
        LineTo(Point2D(20, 0)),
      ]);

      // [5] behaves as [5, 5]: on for 5, off for 5, on for 5, off for 5.
      final singleValue = dashPath(path, const [5], 0);
      final doubled = dashPath(path, const [5, 5], 0);

      expect(singleValue.commands, doubled.commands);
    });

    test('a degenerate all-zero pattern draws the original path solid', () {
      final path = LayerPath(const [
        MoveTo(Point2D(0, 0)),
        LineTo(Point2D(10, 0)),
      ]);

      final dashed = dashPath(path, const [0, 0], 0);

      expect(dashed.commands, path.commands);
    });

    test('a pattern that starts fully "off" paints nothing', () {
      final path = LayerPath(const [
        MoveTo(Point2D(0, 0)),
        LineTo(Point2D(10, 0)),
      ]);

      // Pattern [0, 100]: zero "on" length, entirely "off" for 100 units -
      // nothing should ever be painted.
      final dashed = dashPath(path, const [0, 100], 0);

      expect(_totalLength(dashed), 0);
    });

    test('dashes a closed path across its closing edge', () {
      final path = LayerPath.polygon(const [
        Point2D(0, 0),
        Point2D(10, 0),
        Point2D(10, 10),
        Point2D(0, 10),
      ]);

      // Perimeter is 40; a [5, 5] pattern (10-unit cycle) should paint
      // roughly half of it, split across multiple "on" runs (each run is
      // its own MoveTo).
      final dashed = dashPath(path, const [5, 5], 0);

      final moveToCount = dashed.commands.whereType<MoveTo>().length;
      expect(moveToCount, greaterThan(1));
    });

    test('flattens curves into short segments before dashing', () {
      // A large quadratic curve dashed with a small pattern must produce
      // more than a single on/off pair, proving the curve was subdivided
      // rather than treated as one straight chord.
      final path = LayerPath(const [
        MoveTo(Point2D(0, 0)),
        QuadraticBezierTo(Point2D(50, 100), Point2D(100, 0)),
      ]);

      final dashed = dashPath(path, const [5, 5], 0);

      final moveToCount = dashed.commands.whereType<MoveTo>().length;
      expect(moveToCount, greaterThan(2));
    });
  });
}
