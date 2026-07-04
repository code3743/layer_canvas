import 'package:layer_canvas/src/model/geometry.dart';
import 'package:layer_canvas/src/model/path.dart';
import 'package:layer_canvas/src/svg/svg_path_data.dart';
import 'package:test/test.dart';

void main() {
  group('parseSvgPathData — basic commands', () {
    test('M/L absolute', () {
      final commands = parseSvgPathData('M10,10 L20,10 L20,20');
      expect(commands, [
        const MoveTo(Point2D(10, 10)),
        const LineTo(Point2D(20, 10)),
        const LineTo(Point2D(20, 20)),
      ]);
    });

    test('m/l relative', () {
      final commands = parseSvgPathData('m10,10 l10,0 l0,10');
      expect(commands, [
        const MoveTo(Point2D(10, 10)),
        const LineTo(Point2D(20, 10)),
        const LineTo(Point2D(20, 20)),
      ]);
    });

    test('a moveto followed by extra coordinate pairs is implicit lineto', () {
      final commands = parseSvgPathData('M0,0 10,0 10,10');
      expect(commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(10, 0)),
        const LineTo(Point2D(10, 10)),
      ]);
    });

    test('H/h horizontal lineto', () {
      final commands = parseSvgPathData('M0,0 H10 h5');
      expect(commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(10, 0)),
        const LineTo(Point2D(15, 0)),
      ]);
    });

    test('V/v vertical lineto', () {
      final commands = parseSvgPathData('M0,0 V10 v5');
      expect(commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(0, 10)),
        const LineTo(Point2D(0, 15)),
      ]);
    });

    test('Z closes the subpath without an explicit endpoint', () {
      final commands = parseSvgPathData('M0,0 L10,0 L10,10 Z');
      expect(commands.last, isA<ClosePath>());
    });

    test('implicit command repetition for L', () {
      final commands = parseSvgPathData('M0,0 L10,0 10,10 0,10');
      expect(commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(10, 0)),
        const LineTo(Point2D(10, 10)),
        const LineTo(Point2D(0, 10)),
      ]);
    });
  });

  group('parseSvgPathData — curves', () {
    test('C absolute cubic', () {
      final commands = parseSvgPathData('M0,0 C1,1 2,2 3,3');
      expect(commands, [
        const MoveTo(Point2D(0, 0)),
        const CubicBezierTo(Point2D(1, 1), Point2D(2, 2), Point2D(3, 3)),
      ]);
    });

    test('c relative cubic', () {
      final commands = parseSvgPathData('M10,10 c1,1 2,2 3,3');
      expect(commands, [
        const MoveTo(Point2D(10, 10)),
        const CubicBezierTo(Point2D(11, 11), Point2D(12, 12), Point2D(13, 13)),
      ]);
    });

    test('Q absolute quadratic', () {
      final commands = parseSvgPathData('M0,0 Q5,5 10,0');
      expect(commands, [
        const MoveTo(Point2D(0, 0)),
        const QuadraticBezierTo(Point2D(5, 5), Point2D(10, 0)),
      ]);
    });

    test('S reflects the previous C control point', () {
      // After C ...,8,2 10,0, the reflection of (8,2) around (10,0) is
      // (12,-2).
      final commands = parseSvgPathData('M0,0 C2,2 8,2 10,0 S14,2 20,0');
      final smooth = commands[2] as CubicBezierTo;
      expect(smooth.control1, const Point2D(12, -2));
      expect(smooth.control2, const Point2D(14, 2));
      expect(smooth.point, const Point2D(20, 0));
    });

    test('S with no preceding C uses the current point as control1', () {
      final commands = parseSvgPathData('M0,0 S10,10 20,0');
      final smooth = commands[1] as CubicBezierTo;
      expect(smooth.control1, const Point2D(0, 0));
    });

    test('T reflects the previous Q control point', () {
      // After Q 5,5 10,0, the reflection of (5,5) around (10,0) is (15,-5).
      final commands = parseSvgPathData('M0,0 Q5,5 10,0 T20,0');
      final smooth = commands[2] as QuadraticBezierTo;
      expect(smooth.control, const Point2D(15, -5));
      expect(smooth.point, const Point2D(20, 0));
    });
  });

  group('parseSvgPathData — arcs', () {
    test('A absolute with comma-separated flags', () {
      final commands = parseSvgPathData('M0,0 A5,5,0,1,1,10,0');
      expect(
        commands[1],
        const ArcTo(
          radiusX: 5,
          radiusY: 5,
          xAxisRotation: 0,
          largeArc: true,
          sweep: true,
          point: Point2D(10, 0),
        ),
      );
    });

    test('arc flags packed with no separator before the next number', () {
      // A classic SVG path-parsing gotcha: "...0 0110 20" is large-arc=0,
      // sweep=1, then the number "10" (not "110").
      final commands = parseSvgPathData('M0,0 A5,5 0 0110,20');
      final arc = commands[1] as ArcTo;
      expect(arc.largeArc, isFalse);
      expect(arc.sweep, isTrue);
      expect(arc.point, const Point2D(10, 20));
    });

    test('a relative arc', () {
      final commands = parseSvgPathData('M10,10 a5,5 0 0 1 10,0');
      final arc = commands[1] as ArcTo;
      expect(arc.point, const Point2D(20, 10));
    });
  });

  group('parseSvgPathData — number tokenizing', () {
    test('back-to-back numbers with no separator split at the decimal '
        'point', () {
      final commands = parseSvgPathData('M0.5.5 L1.1.1');
      expect(commands, [
        const MoveTo(Point2D(0.5, 0.5)),
        const LineTo(Point2D(1.1, 0.1)),
      ]);
    });

    test('negative numbers with no separator', () {
      final commands = parseSvgPathData('M10-20 L5-5');
      expect(commands, [
        const MoveTo(Point2D(10, -20)),
        const LineTo(Point2D(5, -5)),
      ]);
    });

    test('scientific notation', () {
      final commands = parseSvgPathData('M1e1,2e0');
      expect(commands, [const MoveTo(Point2D(10, 2))]);
    });
  });

  group('parseSvgPathData — malformed input', () {
    test('empty string returns no commands', () {
      expect(parseSvgPathData(''), isEmpty);
    });

    test('truncates at the first unparseable command', () {
      final commands = parseSvgPathData('M0,0 L10,0 X99,99 L20,20');
      expect(commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(10, 0)),
      ]);
    });

    test('truncates when a command runs out of required numbers', () {
      final commands = parseSvgPathData('M0,0 L10');
      expect(commands, [const MoveTo(Point2D(0, 0))]);
    });
  });
}
