import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

void main() {
  group('GradientStop', () {
    test('equality is based on offset and color', () {
      expect(
        const GradientStop(0.5, Color32.white),
        const GradientStop(0.5, Color32.white),
      );
      expect(
        const GradientStop(0.5, Color32.white),
        isNot(const GradientStop(0.6, Color32.white)),
      );
    });
  });

  group('LinearGradient', () {
    test('stores start/end points, stops and extend mode', () {
      const gradient = LinearGradient(
        start: Point2D(0, 0),
        end: Point2D(1, 0),
        stops: [GradientStop(0, Color32.black), GradientStop(1, Color32.white)],
        extendMode: GradientExtendMode.repeat,
      );

      expect(gradient.start, const Point2D(0, 0));
      expect(gradient.end, const Point2D(1, 0));
      expect(gradient.stops, hasLength(2));
      expect(gradient.extendMode, GradientExtendMode.repeat);
    });

    test('defaults to pad extend mode', () {
      const gradient = LinearGradient(
        start: Point2D(0, 0),
        end: Point2D(1, 1),
        stops: [GradientStop(0, Color32.black)],
      );

      expect(gradient.extendMode, GradientExtendMode.pad);
    });
  });

  group('LinearGradient.colors', () {
    test('two colors with no stops are spaced 0 and 1', () {
      final gradient = LinearGradient.colors(
        start: const Point2D(0, 0),
        end: const Point2D(1, 0),
        colors: const [Color32.black, Color32.white],
      );

      expect(gradient.stops, const [
        GradientStop(0, Color32.black),
        GradientStop(1, Color32.white),
      ]);
    });

    test('three colors with no stops are spaced evenly', () {
      final gradient = LinearGradient.colors(
        start: const Point2D(0, 0),
        end: const Point2D(1, 0),
        colors: const [Color32.black, Color32.white, Color32.transparent],
      );

      expect(gradient.stops, const [
        GradientStop(0, Color32.black),
        GradientStop(0.5, Color32.white),
        GradientStop(1, Color32.transparent),
      ]);
    });

    test('explicit stops are used as-is', () {
      final gradient = LinearGradient.colors(
        start: const Point2D(0, 0),
        end: const Point2D(1, 0),
        colors: const [Color32.black, Color32.white],
        stops: const [0, 0.3],
      );

      expect(gradient.stops, const [
        GradientStop(0, Color32.black),
        GradientStop(0.3, Color32.white),
      ]);
    });

    test('throws with fewer than 2 colors', () {
      expect(
        () => LinearGradient.colors(
          start: const Point2D(0, 0),
          end: const Point2D(1, 0),
          colors: const [Color32.black],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws when stops and colors lengths differ', () {
      expect(
        () => LinearGradient.colors(
          start: const Point2D(0, 0),
          end: const Point2D(1, 0),
          colors: const [Color32.black, Color32.white],
          stops: const [0, 0.5, 1],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('RadialGradient', () {
    test('stores center, radius and stops', () {
      const gradient = RadialGradient(
        center: Point2D(0.5, 0.5),
        radius: 0.5,
        stops: [GradientStop(0, Color32.white), GradientStop(1, Color32.black)],
      );

      expect(gradient.center, const Point2D(0.5, 0.5));
      expect(gradient.radius, 0.5);
      expect(gradient.stops, hasLength(2));
    });
  });

  group('RadialGradient.colors', () {
    test('builds center/radius plus evenly spaced stops', () {
      final gradient = RadialGradient.colors(
        center: const Point2D(0.5, 0.5),
        radius: 0.5,
        colors: const [Color32.white, Color32.black],
      );

      expect(gradient.center, const Point2D(0.5, 0.5));
      expect(gradient.radius, 0.5);
      expect(gradient.stops, const [
        GradientStop(0, Color32.white),
        GradientStop(1, Color32.black),
      ]);
    });
  });

  group('ConicGradient', () {
    test('defaults angle to 0', () {
      const gradient = ConicGradient(
        center: Point2D(0.5, 0.5),
        stops: [GradientStop(0, Color32.black)],
      );

      expect(gradient.angle, 0);
    });

    test('stores a custom start angle', () {
      const gradient = ConicGradient(
        center: Point2D(0.5, 0.5),
        angle: 1.5,
        stops: [GradientStop(0, Color32.black)],
      );

      expect(gradient.angle, 1.5);
    });
  });

  group('ConicGradient.colors', () {
    test('builds center/angle plus evenly spaced stops', () {
      final gradient = ConicGradient.colors(
        center: const Point2D(0.5, 0.5),
        angle: 1.5,
        colors: const [Color32.black, Color32.white],
      );

      expect(gradient.center, const Point2D(0.5, 0.5));
      expect(gradient.angle, 1.5);
      expect(gradient.stops, const [
        GradientStop(0, Color32.black),
        GradientStop(1, Color32.white),
      ]);
    });
  });

  group('LayerPaint.gradient', () {
    test('defaults to null (solid color paint)', () {
      const paint = LayerPaint(color: Color32.white);
      expect(paint.gradient, isNull);
    });

    test('copyWith sets a gradient', () {
      const paint = LayerPaint(color: Color32.white);
      const gradient = LinearGradient(
        start: Point2D(0, 0),
        end: Point2D(1, 1),
        stops: [GradientStop(0, Color32.black)],
      );

      final updated = paint.copyWith(gradient: gradient);

      expect(updated.gradient, gradient);
      expect(updated.color, Color32.white);
    });

    test('copyWith preserves an existing gradient when not overridden', () {
      const gradient = LinearGradient(
        start: Point2D(0, 0),
        end: Point2D(1, 1),
        stops: [GradientStop(0, Color32.black)],
      );
      const paint = LayerPaint(gradient: gradient);

      final updated = paint.copyWith(strokeWidth: 3);

      expect(updated.gradient, gradient);
      expect(updated.strokeWidth, 3);
    });
  });
}
