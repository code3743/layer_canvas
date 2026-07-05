import 'dart:typed_data';

import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

void main() {
  group('Scene', () {
    test('starts empty with the given dimensions', () {
      final scene = Scene(width: 1080, height: 1920);
      expect(scene.width, 1080);
      expect(scene.height, 1920);
      expect(scene.background, isNull);
      expect(scene.layers, isEmpty);
    });

    test('add/addAll append layers in insertion order', () {
      final scene = Scene(width: 100, height: 100);
      final a = RectangleLayer(size: const Size2D(10, 10));
      final b = RectangleLayer(size: const Size2D(10, 10));
      final c = RectangleLayer(size: const Size2D(10, 10));

      scene.add(a);
      scene.addAll([b, c]);

      expect(scene.layers, [a, b, c]);
    });

    test('layers getter is unmodifiable', () {
      final scene = Scene(width: 100, height: 100)
        ..add(RectangleLayer(size: const Size2D(10, 10)));

      expect(
        () => scene.layers.add(RectangleLayer(size: const Size2D(1, 1))),
        throwsUnsupportedError,
      );
    });

    test('remove deletes by id and reports whether it found one', () {
      final scene = Scene(width: 100, height: 100);
      final layer = RectangleLayer(size: const Size2D(10, 10), id: 'target');
      scene.add(layer);

      expect(scene.remove('missing'), isFalse);
      expect(scene.remove('target'), isTrue);
      expect(scene.layers, isEmpty);
    });

    test('clear empties the layer list', () {
      final scene = Scene(width: 100, height: 100)
        ..add(RectangleLayer(size: const Size2D(10, 10)))
        ..add(RectangleLayer(size: const Size2D(10, 10)));

      scene.clear();

      expect(scene.layers, isEmpty);
    });

    test('background is mutable after construction', () {
      final scene = Scene(width: 100, height: 100);
      scene.background = const LayerImageSource.file('/tmp/bg.png');

      expect(scene.background, isA<FileImageSource>());
      expect((scene.background as FileImageSource).path, '/tmp/bg.png');
    });

    test('rejects non-positive dimensions', () {
      expect(
        () => Scene(width: 0, height: 100),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Scene(width: 100, height: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Layer', () {
    test('auto-generates a unique id when none is given', () {
      final a = RectangleLayer(size: const Size2D(1, 1));
      final b = RectangleLayer(size: const Size2D(1, 1));
      expect(a.id, isNot(equals(b.id)));
    });

    test('honors an explicit id', () {
      final layer = RectangleLayer(size: const Size2D(1, 1), id: 'my-id');
      expect(layer.id, 'my-id');
    });

    test('defaults: fully opaque, visible, zIndex 0, identity transform', () {
      final layer = RectangleLayer(size: const Size2D(1, 1));
      expect(layer.opacity, 1.0);
      expect(layer.visible, isTrue);
      expect(layer.zIndex, 0);
      expect(layer.transform.position, Point2D.zero);
      expect(layer.transform.rotation, 0);
      expect(layer.transform.scale, Point2D.one);
    });

    test('rejects opacity outside [0, 1]', () {
      expect(
        () => RectangleLayer(size: const Size2D(1, 1), opacity: 1.5),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RectangleLayer(size: const Size2D(1, 1), opacity: -0.1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('RectangleLayer', () {
    test('exposes its own properties through type/properties', () {
      final layer = RectangleLayer(
        size: const Size2D(200, 100),
        paint: const LayerPaint(
          color: Color32.white,
          style: LayerPaintStyle.fill,
        ),
        cornerRadius: 12,
      );

      expect(layer.type, 'rectangle');
      expect(layer.properties['cornerRadius'], 12);
      expect((layer.properties['paint'] as LayerPaint).color, Color32.white);
    });

    test('.filled builds the same size/paint/cornerRadius as the main '
        'constructor', () {
      final filled = RectangleLayer.filled(
        width: 200,
        height: 100,
        color: Color32.white,
        cornerRadius: 12,
      );

      expect(filled.size, const Size2D(200, 100));
      expect(filled.paint.color, Color32.white);
      expect(filled.paint.style, LayerPaintStyle.fill);
      expect(filled.cornerRadius, 12);
    });

    test('.filled forwards transform/opacity/zIndex/visible/id', () {
      final filled = RectangleLayer.filled(
        width: 10,
        height: 10,
        color: Color32.black,
        id: 'my-rect',
        transform: const LayerTransform(position: Point2D(5, 5)),
        opacity: 0.5,
        zIndex: 2,
        visible: false,
      );

      expect(filled.id, 'my-rect');
      expect(filled.transform.position, const Point2D(5, 5));
      expect(filled.opacity, 0.5);
      expect(filled.zIndex, 2);
      expect(filled.visible, isFalse);
    });
  });

  group('ImageLayer', () {
    test('carries its source and fit through properties', () {
      final layer = ImageLayer(
        source: LayerImageSource.memory(Uint8List.fromList([1, 2, 3])),
        fit: ImageFit.cover,
        size: const Size2D(64, 64),
      );

      expect(layer.type, 'image');
      expect(layer.properties['fit'], 'cover');
      expect(layer.properties['source'], isA<MemoryImageSource>());
    });

    test('size is null (intrinsic) unless given explicitly', () {
      final layer = ImageLayer(source: const LayerImageSource.file('a.png'));
      expect(layer.size, isNull);
    });
  });

  group('TextLayer', () {
    test('carries text styling through properties', () {
      final layer = TextLayer(
        text: 'Hello',
        fontSize: 24,
        color: Color32.white,
        align: TextAlignment.center,
        fontWeight: TextWeight.bold,
      );

      expect(layer.type, 'text');
      expect(layer.properties['text'], 'Hello');
      expect(layer.properties['fontSize'], 24);
      expect(layer.properties['align'], 'center');
      expect(layer.properties['fontWeight'], 700);
    });
  });

  group('Group', () {
    test('nests children and reports them through properties', () {
      final child1 = RectangleLayer(size: const Size2D(1, 1));
      final child2 = RectangleLayer(size: const Size2D(1, 1));
      final group = Group(children: [child1, child2]);

      expect(group.type, 'group');
      expect(group.children, [child1, child2]);
      expect(group.properties['children'], [child1, child2]);
    });

    test('groups can nest inside groups', () {
      final inner = Group(children: [RectangleLayer(size: const Size2D(1, 1))]);
      final outer = Group(children: [inner]);

      expect(outer.children.single, isA<Group>());
    });
  });

  group('Color32', () {
    test('fromRGB assumes full alpha', () {
      const color = Color32.fromRGB(10, 20, 30);
      expect(color.alpha, 0xff);
      expect(color.red, 10);
      expect(color.green, 20);
      expect(color.blue, 30);
    });

    test('withOpacity scales alpha', () {
      const color = Color32.white;
      final half = color.withOpacity(0.5);
      expect(half.alpha, 128);
      expect(half.red, 0xff);
    });
  });

  group('LayerTransform', () {
    test('copyWith overrides only the given fields', () {
      const original = LayerTransform(position: Point2D(1, 2), rotation: 0.5);
      final copy = original.copyWith(rotation: 1.0);

      expect(copy.position, original.position);
      expect(copy.rotation, 1.0);
      expect(copy.scale, original.scale);
    });
  });
}
