import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

void main() {
  group('LayerPath', () {
    test('requires at least one command', () {
      expect(() => LayerPath(const []), throwsA(isA<AssertionError>()));
    });

    test('stores an arbitrary command sequence as-is', () {
      final path = LayerPath([
        MoveTo(Point2D(0, 0)),
        LineTo(Point2D(10, 0)),
        QuadraticBezierTo(Point2D(15, 5), Point2D(10, 10)),
        CubicBezierTo(Point2D(5, 15), Point2D(0, 15), Point2D(0, 10)),
        ClosePath(),
      ]);

      expect(path.commands, hasLength(5));
      expect(path.commands[0], isA<MoveTo>());
      expect(path.commands[1], isA<LineTo>());
      expect(path.commands[2], isA<QuadraticBezierTo>());
      expect(path.commands[3], isA<CubicBezierTo>());
      expect(path.commands[4], isA<ClosePath>());
    });
  });

  group('LayerPath.polygon', () {
    test('starts with MoveTo, connects with LineTo, and closes', () {
      final path = LayerPath.polygon(const [
        Point2D(0, 0),
        Point2D(10, 0),
        Point2D(5, 10),
      ]);

      expect(path.commands, hasLength(4));
      expect(path.commands[0], const MoveTo(Point2D(0, 0)));
      expect(path.commands[1], const LineTo(Point2D(10, 0)));
      expect(path.commands[2], const LineTo(Point2D(5, 10)));
      expect(path.commands[3], isA<ClosePath>());
    });

    test('requires at least 2 vertices', () {
      expect(
        () => LayerPath.polygon(const [Point2D(0, 0)]),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('LayerPath.polyline', () {
    test('starts with MoveTo, connects with LineTo, and does not close', () {
      final path = LayerPath.polyline(const [
        Point2D(0, 0),
        Point2D(10, 0),
        Point2D(5, 10),
      ]);

      expect(path.commands, hasLength(3));
      expect(path.commands[0], const MoveTo(Point2D(0, 0)));
      expect(path.commands[1], const LineTo(Point2D(10, 0)));
      expect(path.commands[2], const LineTo(Point2D(5, 10)));
    });

    test('requires at least 2 vertices', () {
      expect(
        () => LayerPath.polyline(const [Point2D(0, 0)]),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('LayerPath.ellipse', () {
    test('starts at the rightmost point and closes with two arcs', () {
      final path = LayerPath.ellipse(const Point2D(50, 50), 40, 20);

      expect(path.commands, [
        const MoveTo(Point2D(90, 50)),
        const ArcTo(
          radiusX: 40,
          radiusY: 20,
          sweep: true,
          point: Point2D(10, 50),
        ),
        const ArcTo(
          radiusX: 40,
          radiusY: 20,
          sweep: true,
          point: Point2D(90, 50),
        ),
        const ClosePath(),
      ]);
    });

    test('requires positive radii', () {
      expect(
        () => LayerPath.ellipse(const Point2D(0, 0), 0, 10),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => LayerPath.ellipse(const Point2D(0, 0), 10, -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('LayerPath.circle', () {
    test('is an ellipse with equal radii', () {
      expect(
        LayerPath.circle(const Point2D(50, 50), 40).commands,
        LayerPath.ellipse(const Point2D(50, 50), 40, 40).commands,
      );
    });
  });

  group('ArcTo', () {
    test('defaults xAxisRotation/largeArc/sweep', () {
      const arc = ArcTo(radiusX: 100, radiusY: 50, point: Point2D(10, 10));

      expect(arc.xAxisRotation, 0);
      expect(arc.largeArc, isFalse);
      expect(arc.sweep, isFalse);
    });

    test('equality is based on all fields', () {
      const a = ArcTo(radiusX: 100, radiusY: 50, point: Point2D(10, 10));
      const b = ArcTo(radiusX: 100, radiusY: 50, point: Point2D(10, 10));
      const c = ArcTo(
        radiusX: 100,
        radiusY: 50,
        largeArc: true,
        point: Point2D(10, 10),
      );

      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('FillRule', () {
    test('PathLayer defaults to nonZero', () {
      final layer = PathLayer(
        path: LayerPath.polygon(const [
          Point2D(0, 0),
          Point2D(10, 0),
          Point2D(5, 10),
        ]),
      );

      expect(layer.fillRule, FillRule.nonZero);
    });
  });

  group('PathLayer.filled', () {
    test('builds the same path/paint/fillRule as the main constructor', () {
      final path = LayerPath.circle(const Point2D(50, 50), 40);
      final filled = PathLayer.filled(
        path: path,
        color: Color32.white,
        fillRule: FillRule.evenOdd,
      );

      expect(filled.path, same(path));
      expect(filled.paint.color, Color32.white);
      expect(filled.paint.style, LayerPaintStyle.fill);
      expect(filled.fillRule, FillRule.evenOdd);
    });

    test('forwards transform/size/opacity/zIndex/visible/id', () {
      final filled = PathLayer.filled(
        path: LayerPath.circle(const Point2D(0, 0), 10),
        color: Color32.black,
        id: 'my-path',
        transform: const LayerTransform(position: Point2D(5, 5)),
        size: const Size2D(20, 20),
        opacity: 0.5,
        zIndex: 2,
        visible: false,
      );

      expect(filled.id, 'my-path');
      expect(filled.transform.position, const Point2D(5, 5));
      expect(filled.size, const Size2D(20, 20));
      expect(filled.opacity, 0.5);
      expect(filled.zIndex, 2);
      expect(filled.visible, isFalse);
    });
  });
}
