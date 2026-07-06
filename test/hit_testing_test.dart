import 'dart:math' as math;

import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

RectangleLayer _rect({
  String? id,
  LayerTransform transform = const LayerTransform(),
  Size2D size = const Size2D(10, 10),
  int zIndex = 0,
  bool visible = true,
}) {
  return RectangleLayer(
    id: id,
    transform: transform,
    size: size,
    zIndex: zIndex,
    visible: visible,
    paint: const LayerPaint(color: Color32.black),
  );
}

Scene _sceneOf(List<Layer> layers) {
  final scene = Scene(width: 400, height: 400);
  scene.addAll(layers);
  return scene;
}

void main() {
  group('hitTestScene', () {
    test('finds a layer whose bounding box contains the point', () {
      final layer = _rect(
        id: 'a',
        transform: const LayerTransform(position: Point2D(10, 10)),
      );
      final scene = _sceneOf([layer]);

      expect(hitTestScene(scene, const Point2D(15, 15))?.id, 'a');
    });

    test('returns null just outside the bounding box', () {
      final layer = _rect(transform: const LayerTransform(position: Point2D(10, 10)));
      final scene = _sceneOf([layer]);

      expect(hitTestScene(scene, const Point2D(9.9, 15)), isNull);
      expect(hitTestScene(scene, const Point2D(20.1, 15)), isNull);
    });

    test('returns null for an empty scene', () {
      expect(hitTestScene(_sceneOf([]), const Point2D(0, 0)), isNull);
    });

    test('picks the higher zIndex when two layers overlap', () {
      final back = _rect(id: 'back', zIndex: 0);
      final front = _rect(id: 'front', zIndex: 1);
      final scene = _sceneOf([back, front]);

      expect(hitTestScene(scene, const Point2D(5, 5))?.id, 'front');
    });

    test('ties broken by insertion order (later wins)', () {
      final first = _rect(id: 'first');
      final second = _rect(id: 'second');
      final scene = _sceneOf([first, second]);

      expect(hitTestScene(scene, const Point2D(5, 5))?.id, 'second');
    });

    test('skips an invisible layer', () {
      final hidden = _rect(id: 'hidden', visible: false);
      final scene = _sceneOf([hidden]);

      expect(hitTestScene(scene, const Point2D(5, 5)), isNull);
    });

    test('never matches a layer with no explicit (intrinsic) size', () {
      // TextLayer is one of the layer kinds that allows a null size (the
      // native backend derives it from laid-out text bounds) - unlike
      // RectangleLayer, whose size is always required.
      final layer = TextLayer(text: 'hi');
      final scene = _sceneOf([layer]);

      expect(hitTestScene(scene, const Point2D(0, 0)), isNull);
    });

    test('a rotated layer\'s bounding box rotates with it', () {
      // A 20x20 square centered at (50, 50) (position (40, 40), default
      // anchor 0.5/0.5), rotated 45 degrees - its axis-aligned corners
      // (40,40)/(60,40)/(60,60)/(40,60) are no longer inside it, but the
      // rotated corner in the +x direction from the center now is.
      final layer = _rect(
        id: 'rotated',
        size: const Size2D(20, 20),
        transform: const LayerTransform(
          position: Point2D(40, 40),
          rotation: math.pi / 4,
        ),
      );
      final scene = _sceneOf([layer]);

      // Center is always inside regardless of rotation.
      expect(hitTestScene(scene, const Point2D(50, 50))?.id, 'rotated');
      // A corner of the *unrotated* box, now rotated away from that point.
      expect(hitTestScene(scene, const Point2D(59, 41)), isNull);
    });

    test('a scaled layer\'s bounding box scales with it', () {
      final layer = _rect(
        id: 'scaled',
        size: const Size2D(10, 10),
        transform: const LayerTransform(
          position: Point2D(0, 0),
          scale: Point2D(3, 1),
          anchor: Point2D.zero,
        ),
      );
      final scene = _sceneOf([layer]);

      expect(hitTestScene(scene, const Point2D(25, 5))?.id, 'scaled');
      expect(hitTestScene(scene, const Point2D(35, 5)), isNull);
    });

    test('a group carries its children\'s hit boxes along its own transform', () {
      final child = _rect(
        id: 'child',
        transform: const LayerTransform(position: Point2D(5, 5)),
      );
      final group = Group(
        transform: const LayerTransform(position: Point2D(100, 100)),
        children: [child],
      );
      final scene = _sceneOf([group]);

      expect(hitTestScene(scene, const Point2D(110, 110))?.id, 'child');
      expect(hitTestScene(scene, const Point2D(10, 10)), isNull);
    });
  });
}
