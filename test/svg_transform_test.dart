import 'dart:math' as math;

import 'package:layer_canvas/src/model/geometry.dart';
import 'package:layer_canvas/src/model/path.dart';
import 'package:layer_canvas/src/svg/svg_transform.dart';
import 'package:test/test.dart';

void expectPointClose(Point2D actual, Point2D expected, [double eps = 1e-6]) {
  expect(actual.x, closeTo(expected.x, eps));
  expect(actual.y, closeTo(expected.y, eps));
}

void main() {
  group('SvgMatrix', () {
    test('identity leaves a point unchanged', () {
      expectPointClose(
        SvgMatrix.identity.apply(const Point2D(3, 4)),
        const Point2D(3, 4),
      );
    });

    test('translate shifts a point', () {
      final m = SvgMatrix.translate(10, 20);
      expectPointClose(m.apply(const Point2D(1, 1)), const Point2D(11, 21));
    });

    test('scale scales a point around the origin', () {
      final m = SvgMatrix.scale(2, 3);
      expectPointClose(m.apply(const Point2D(5, 5)), const Point2D(10, 15));
    });

    test('scale with a single argument scales uniformly', () {
      final m = SvgMatrix.scale(2);
      expectPointClose(m.apply(const Point2D(5, 5)), const Point2D(10, 10));
    });

    test('rotate(90) around the origin maps (1,0) to (0,1)', () {
      final m = SvgMatrix.rotate(90);
      expectPointClose(m.apply(const Point2D(1, 0)), const Point2D(0, 1));
    });

    test('rotate around an explicit center leaves that center fixed', () {
      final m = SvgMatrix.rotate(180, 5, 5);
      expectPointClose(m.apply(const Point2D(5, 5)), const Point2D(5, 5));
      expectPointClose(m.apply(const Point2D(6, 5)), const Point2D(4, 5));
    });

    test('multiply composes so other is applied first', () {
      final translateThenScale = SvgMatrix.scale(
        2,
      ).multiply(SvgMatrix.translate(1, 0));
      // (0,0) -> translate -> (1,0) -> scale -> (2,0).
      expectPointClose(
        translateThenScale.apply(Point2D.zero),
        const Point2D(2, 0),
      );
    });

    test('isIdentity', () {
      expect(SvgMatrix.identity.isIdentity, isTrue);
      expect(SvgMatrix.translate(1, 0).isIdentity, isFalse);
    });
  });

  group('parseSvgTransform', () {
    test('translate(tx, ty)', () {
      final m = parseSvgTransform('translate(10, 20)');
      expectPointClose(m.apply(Point2D.zero), const Point2D(10, 20));
    });

    test('translate(tx) defaults ty to 0', () {
      final m = parseSvgTransform('translate(10)');
      expectPointClose(m.apply(Point2D.zero), const Point2D(10, 0));
    });

    test('scale(s)', () {
      final m = parseSvgTransform('scale(2)');
      expectPointClose(m.apply(const Point2D(3, 4)), const Point2D(6, 8));
    });

    test('rotate(angle, cx, cy)', () {
      final m = parseSvgTransform('rotate(180, 5, 5)');
      expectPointClose(m.apply(const Point2D(6, 5)), const Point2D(4, 5));
    });

    test('matrix(a,b,c,d,e,f)', () {
      final m = parseSvgTransform('matrix(1, 0, 0, 1, 7, 8)');
      expectPointClose(m.apply(Point2D.zero), const Point2D(7, 8));
    });

    test('composes multiple functions so the rightmost applies first', () {
      // Per the SVG spec, "scale(2) translate(1, 0)" means
      // M(scale) * M(translate): translate is applied to the point first
      // (innermost), then scale - (0,0) -> translate -> (1,0) -> scale ->
      // (2,0). ("translate(1,0) scale(2)" would instead leave (0,0)
      // unmoved by the scale, then translate to (1,0).)
      final m = parseSvgTransform('scale(2) translate(1, 0)');
      expectPointClose(m.apply(Point2D.zero), const Point2D(2, 0));
    });

    test('unrecognized function is ignored, not fatal', () {
      final m = parseSvgTransform('perspective(500) translate(1, 0)');
      expectPointClose(m.apply(Point2D.zero), const Point2D(1, 0));
    });

    test('accepts comma- and space-separated arguments', () {
      final a = parseSvgTransform('translate(10 20)');
      final b = parseSvgTransform('translate(10, 20)');
      expectPointClose(a.apply(Point2D.zero), b.apply(Point2D.zero));
    });
  });

  group('applySvgMatrix', () {
    test('identity returns the same list instance', () {
      final commands = [const MoveTo(Point2D(1, 2))];
      expect(applySvgMatrix(commands, SvgMatrix.identity), same(commands));
    });

    test('translates every point in a command list', () {
      final commands = [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(10, 0)),
        const QuadraticBezierTo(Point2D(5, 5), Point2D(10, 10)),
        const CubicBezierTo(Point2D(1, 1), Point2D(2, 2), Point2D(3, 3)),
        const ClosePath(),
      ];

      final result = applySvgMatrix(commands, SvgMatrix.translate(100, 0));

      expect(result[0], const MoveTo(Point2D(100, 0)));
      expect(result[1], const LineTo(Point2D(110, 0)));
      expect(
        result[2],
        const QuadraticBezierTo(Point2D(105, 5), Point2D(110, 10)),
      );
      expect(
        result[3],
        const CubicBezierTo(Point2D(101, 1), Point2D(102, 2), Point2D(103, 3)),
      );
      expect(result[4], isA<ClosePath>());
    });

    test(
      'a similarity transform (uniform scale + rotation) keeps ArcTo exact',
      () {
        final commands = [
          const MoveTo(Point2D(100, 0)),
          const ArcTo(radiusX: 100, radiusY: 100, point: Point2D(-100, 0)),
        ];

        final result = applySvgMatrix(commands, SvgMatrix.scale(2));

        final arc = result[1] as ArcTo;
        expect(arc.radiusX, closeTo(200, 1e-9));
        expect(arc.radiusY, closeTo(200, 1e-9));
        expectPointClose(arc.point, const Point2D(-200, 0));
      },
    );

    test('a reflection flips the sweep flag on an ArcTo', () {
      final commands = [
        const MoveTo(Point2D(100, 0)),
        const ArcTo(
          radiusX: 100,
          radiusY: 100,
          sweep: true,
          point: Point2D(-100, 0),
        ),
      ];

      // scale(-1, 1) is a horizontal flip - a reflection (negative
      // determinant).
      final result = applySvgMatrix(commands, SvgMatrix.scale(-1, 1));

      final arc = result[1] as ArcTo;
      expect(arc.sweep, isFalse);
    });

    test(
      'a non-uniform scale approximates ArcTo with cubic Béziers instead',
      () {
        final commands = [
          const MoveTo(Point2D(100, 0)),
          const ArcTo(radiusX: 100, radiusY: 100, point: Point2D(-100, 0)),
        ];

        final result = applySvgMatrix(commands, SvgMatrix.scale(1, 2));

        expect(result[1], isA<CubicBezierTo>());
      },
    );
  });

  group('arcToBeziers', () {
    test('approximates a semicircle ending at the correct endpoint', () {
      const start = Point2D(100, 0);
      const arc = ArcTo(radiusX: 100, radiusY: 100, point: Point2D(-100, 0));

      final beziers = arcToBeziers(start, arc);

      expect(beziers, isNotEmpty);
      expectPointClose(beziers.last.point, arc.point, 1e-6);
    });

    test('a point on the approximated curve lies on the true circle', () {
      const start = Point2D(100, 0);
      const arc = ArcTo(radiusX: 100, radiusY: 100, point: Point2D(-100, 0));

      final beziers = arcToBeziers(start, arc);
      // Sample the midpoint of the first cubic segment (De Casteljau at
      // t=0.5) and check it's ~100 units from the circle's center (0,0).
      final p0 = start;
      final b = beziers.first;
      Point2D lerp(Point2D a, Point2D c, double t) =>
          Point2D(a.x + (c.x - a.x) * t, a.y + (c.y - a.y) * t);
      final a1 = lerp(p0, b.control1, 0.5);
      final a2 = lerp(b.control1, b.control2, 0.5);
      final a3 = lerp(b.control2, b.point, 0.5);
      final b1 = lerp(a1, a2, 0.5);
      final b2 = lerp(a2, a3, 0.5);
      final mid = lerp(b1, b2, 0.5);

      final distanceFromCenter = math.sqrt(mid.x * mid.x + mid.y * mid.y);
      expect(distanceFromCenter, closeTo(100, 1.0));
    });

    test('returns nothing for a zero-length arc', () {
      const p = Point2D(10, 10);
      const arc = ArcTo(radiusX: 5, radiusY: 5, point: p);
      expect(arcToBeziers(p, arc), isEmpty);
    });
  });
}
