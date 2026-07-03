import 'dart:math' as math;

import 'package:layer_canvas/layer_canvas.dart';
import 'package:layer_canvas/src/renderer/scene_flattener.dart';
import 'package:test/test.dart';

RectangleLayer _rect({
  LayerTransform transform = const LayerTransform(),
  Size2D size = const Size2D(10, 10),
  double opacity = 1.0,
  int zIndex = 0,
  bool visible = true,
}) {
  return RectangleLayer(
    transform: transform,
    size: size,
    opacity: opacity,
    zIndex: zIndex,
    visible: visible,
    paint: const LayerPaint(color: Color32.black),
  );
}

void main() {
  group('flattenScene', () {
    test('passes through a flat scene, sorted by zIndex, invisible dropped', () {
      final back = _rect(zIndex: 0);
      final hidden = _rect(zIndex: 1, visible: false);
      final front = _rect(zIndex: 2);

      final resolved = flattenScene([front, hidden, back]);

      expect(resolved.map((r) => r.source), [back, front]);
    });

    test('a group translates every child by its own position', () {
      final child = _rect(transform: const LayerTransform(position: Point2D(5, 5)));
      final group = Group(
        transform: const LayerTransform(position: Point2D(100, 200)),
        children: [child],
      );

      final resolved = flattenScene([group]);

      expect(resolved, hasLength(1));
      expect(resolved.single.transform.position, const Point2D(105, 205));
    });

    test('a group multiplies its opacity into every child', () {
      final child = _rect(opacity: 0.5);
      final group = Group(opacity: 0.4, children: [child]);

      final resolved = flattenScene([group]);

      expect(resolved.single.opacity, closeTo(0.2, 1e-9));
    });

    test('an invisible group hides its entire subtree', () {
      final group = Group(visible: false, children: [_rect(), _rect()]);

      expect(flattenScene([group]), isEmpty);
    });

    test('nested groups compose position through both levels', () {
      final child = _rect(transform: const LayerTransform(position: Point2D(1, 1)));
      final inner = Group(
        transform: const LayerTransform(position: Point2D(10, 10)),
        children: [child],
      );
      final outer = Group(
        transform: const LayerTransform(position: Point2D(100, 100)),
        children: [inner],
      );

      final resolved = flattenScene([outer]);

      expect(resolved.single.transform.position, const Point2D(111, 111));
    });

    test('a group rotation carries a child\'s local offset with it', () {
      // A 90° (clockwise) group rotation should carry a child positioned
      // 10px to its "right" (local +x) around to local +y in world space.
      final child = _rect(transform: const LayerTransform(position: Point2D(10, 0)));
      final group = Group(
        transform: LayerTransform(position: Point2D.zero, rotation: math.pi / 2),
        children: [child],
      );

      final resolved = flattenScene([group]);

      final position = resolved.single.transform.position;
      expect(position.x, closeTo(0, 1e-9));
      expect(position.y, closeTo(10, 1e-9));
    });

    test('a 180° rotation around a centered anchor moves the reduced '
        'position by exactly the layer size', () {
      const size = Size2D(20, 8);
      final layer = _rect(
        transform: LayerTransform(
          position: const Point2D(50, 50),
          rotation: math.pi,
        ),
        size: size,
      );

      final resolved = flattenScene([layer]);

      final position = resolved.single.transform.position;
      expect(position.x, closeTo(50 + size.width, 1e-9));
      expect(position.y, closeTo(50 + size.height, 1e-9));
      // Anchor is always folded away in the flattened output.
      expect(resolved.single.transform.anchor, Point2D.zero);
    });
  });
}
