import 'dart:convert';
import 'dart:typed_data';

import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

/// Round-trips [json] through an actual `jsonEncode`/`jsonDecode` cycle (not
/// just passing the Dart `Map` straight back to `fromJson`) — real JSON text
/// is where int/double and `List<dynamic>`/`Map<String, dynamic>` quirks
/// would actually surface.
Map<String, Object?> _throughJsonText(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('value type round-trips', () {
    test('Point2D', () {
      const point = Point2D(1.5, -2.25);
      expect(Point2D.fromJson(_throughJsonText(point.toJson())), point);
    });

    test('Size2D', () {
      const size = Size2D(100, 50.5);
      expect(Size2D.fromJson(_throughJsonText(size.toJson())), size);
    });

    test('Color32', () {
      const color = Color32.fromARGB(180, 58, 123, 213);
      final json = jsonDecode(jsonEncode(color.toJson()));
      expect(Color32.fromJson(json as int), color);
    });

    test('LayerTransform', () {
      const transform = LayerTransform(
        position: Point2D(10, 20),
        rotation: 1.2,
        scale: Point2D(2, 3),
        anchor: Point2D(0, 1),
      );
      expect(
        LayerTransform.fromJson(_throughJsonText(transform.toJson())),
        transform,
      );
    });
  });

  group('Gradient round-trips', () {
    test('LinearGradient', () {
      const gradient = LinearGradient(
        start: Point2D(0, 0),
        end: Point2D(1, 1),
        stops: [GradientStop(0, Color32.black), GradientStop(1, Color32.white)],
        extendMode: GradientExtendMode.repeat,
      );

      final decoded =
          Gradient.fromJson(_throughJsonText(gradient.toJson()))
              as LinearGradient;

      expect(decoded.start, gradient.start);
      expect(decoded.end, gradient.end);
      expect(decoded.stops, gradient.stops);
      expect(decoded.extendMode, gradient.extendMode);
    });

    test('RadialGradient', () {
      const gradient = RadialGradient(
        center: Point2D(0.5, 0.5),
        radius: 0.25,
        stops: [GradientStop(0, Color32.white)],
      );

      final decoded =
          Gradient.fromJson(_throughJsonText(gradient.toJson()))
              as RadialGradient;

      expect(decoded.center, gradient.center);
      expect(decoded.radius, gradient.radius);
    });

    test('ConicGradient', () {
      const gradient = ConicGradient(
        center: Point2D(0.5, 0.5),
        angle: 1.25,
        stops: [GradientStop(0, Color32.white)],
      );

      final decoded =
          Gradient.fromJson(_throughJsonText(gradient.toJson()))
              as ConicGradient;

      expect(decoded.center, gradient.center);
      expect(decoded.angle, gradient.angle);
    });

    test('an unknown type throws ArgumentError', () {
      expect(
        () => Gradient.fromJson({'type': 'nonexistent'}),
        throwsArgumentError,
      );
    });
  });

  group('LayerPaint round-trips', () {
    test('a solid paint with default stroke styling', () {
      const paint = LayerPaint(color: Color32.fromRGB(10, 20, 30));

      final decoded = LayerPaint.fromJson(_throughJsonText(paint.toJson()));

      expect(decoded.color, paint.color);
      expect(decoded.style, paint.style);
      expect(decoded.strokeWidth, paint.strokeWidth);
      expect(decoded.strokeCap, paint.strokeCap);
      expect(decoded.strokeJoin, paint.strokeJoin);
      expect(decoded.miterLimit, paint.miterLimit);
      expect(decoded.dashArray, paint.dashArray);
      expect(decoded.dashOffset, paint.dashOffset);
      expect(decoded.gradient, isNull);
    });

    test('a stroked paint with cap/join/dash and a gradient', () {
      const paint = LayerPaint(
        style: LayerPaintStyle.fillAndStroke,
        strokeWidth: 3,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.bevel,
        miterLimit: 2.5,
        dashArray: [4, 2, 1],
        dashOffset: 1.5,
        gradient: LinearGradient(
          start: Point2D(0, 0),
          end: Point2D(1, 0),
          stops: [
            GradientStop(0, Color32.black),
            GradientStop(1, Color32.white),
          ],
        ),
      );

      final decoded = LayerPaint.fromJson(_throughJsonText(paint.toJson()));

      expect(decoded.style, paint.style);
      expect(decoded.strokeCap, paint.strokeCap);
      expect(decoded.strokeJoin, paint.strokeJoin);
      expect(decoded.miterLimit, paint.miterLimit);
      expect(decoded.dashArray, paint.dashArray);
      expect(decoded.dashOffset, paint.dashOffset);
      expect(decoded.gradient, isA<LinearGradient>());
    });
  });

  group('LayerPath round-trips', () {
    test('every PathCommand variant', () {
      final path = LayerPath(const [
        MoveTo(Point2D(0, 0)),
        LineTo(Point2D(10, 0)),
        QuadraticBezierTo(Point2D(15, 5), Point2D(10, 10)),
        CubicBezierTo(Point2D(5, 15), Point2D(0, 15), Point2D(0, 10)),
        ArcTo(
          radiusX: 5,
          radiusY: 5,
          xAxisRotation: 0.3,
          largeArc: true,
          sweep: true,
          point: Point2D(20, 20),
        ),
        ClosePath(),
      ]);

      final decoded = LayerPath.fromJson(_throughJsonText(path.toJson()));

      expect(decoded.commands, path.commands);
    });

    test('an unknown command type throws ArgumentError', () {
      expect(
        () => PathCommand.fromJson({'type': 'nonexistent'}),
        throwsArgumentError,
      );
    });
  });

  group('LayerImageSource round-trips', () {
    test('FileImageSource', () {
      const source = FileImageSource('/tmp/watermark.png');
      final decoded = LayerRegistry.decodeImageSource(
        _throughJsonText(source.toJson()),
      );
      expect(decoded, isA<FileImageSource>());
      expect((decoded as FileImageSource).path, source.path);
    });

    test('MemoryImageSource', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final source = MemoryImageSource(bytes);
      final decoded = LayerRegistry.decodeImageSource(
        _throughJsonText(source.toJson()),
      );
      expect(decoded, isA<MemoryImageSource>());
      expect((decoded as MemoryImageSource).bytes, bytes);
    });

    test('an unknown type throws ArgumentError', () {
      expect(
        () => LayerRegistry.decodeImageSource({'type': 'nonexistent'}),
        throwsArgumentError,
      );
    });
  });

  group('Layer round-trips', () {
    test('RectangleLayer', () {
      final layer = RectangleLayer(
        id: 'rect-1',
        transform: const LayerTransform(position: Point2D(5, 5)),
        size: const Size2D(100, 50),
        opacity: 0.8,
        zIndex: 2,
        visible: false,
        clipToBounds: true,
        paint: const LayerPaint(color: Color32.fromRGB(200, 0, 0)),
        cornerRadius: 8,
      );

      final decoded =
          LayerRegistry.decodeLayer(_throughJsonText(layer.toJson()))
              as RectangleLayer;

      expect(decoded.id, layer.id);
      expect(decoded.transform, layer.transform);
      expect(decoded.size, layer.size);
      expect(decoded.opacity, layer.opacity);
      expect(decoded.zIndex, layer.zIndex);
      expect(decoded.visible, layer.visible);
      expect(decoded.clipToBounds, isTrue);
      expect(decoded.paint.color, layer.paint.color);
      expect(decoded.cornerRadius, layer.cornerRadius);
    });

    test('TextLayer', () {
      final layer = TextLayer(
        id: 'text-1',
        text: 'hola',
        fontFamily: 'Brand',
        fontSize: 22,
        color: Color32.white,
        align: TextAlignment.center,
        fontWeight: TextWeight.bold,
      );

      final decoded =
          LayerRegistry.decodeLayer(_throughJsonText(layer.toJson()))
              as TextLayer;

      expect(decoded.text, layer.text);
      expect(decoded.fontFamily, layer.fontFamily);
      expect(decoded.fontSize, layer.fontSize);
      expect(decoded.color, layer.color);
      expect(decoded.align, layer.align);
      expect(decoded.fontWeight.value, layer.fontWeight.value);
    });

    test('TextLayer with null fontFamily', () {
      final layer = TextLayer(text: 'sin familia de fuente');

      final decoded =
          LayerRegistry.decodeLayer(_throughJsonText(layer.toJson()))
              as TextLayer;

      expect(decoded.fontFamily, isNull);
    });

    test('ImageLayer with a FileImageSource', () {
      final layer = ImageLayer(
        id: 'img-1',
        source: const LayerImageSource.file('/tmp/photo.png'),
        fit: ImageFit.cover,
      );

      final decoded =
          LayerRegistry.decodeLayer(_throughJsonText(layer.toJson()))
              as ImageLayer;

      expect(decoded.source, isA<FileImageSource>());
      expect((decoded.source as FileImageSource).path, '/tmp/photo.png');
      expect(decoded.fit, layer.fit);
    });

    test('PathLayer', () {
      final layer = PathLayer(
        id: 'path-1',
        path: LayerPath.circle(const Point2D(50, 50), 40),
        paint: const LayerPaint(color: Color32.fromRGB(0, 180, 90)),
        fillRule: FillRule.evenOdd,
      );

      final decoded =
          LayerRegistry.decodeLayer(_throughJsonText(layer.toJson()))
              as PathLayer;

      expect(decoded.path.commands, layer.path.commands);
      expect(decoded.paint.color, layer.paint.color);
      expect(decoded.fillRule, layer.fillRule);
    });

    test('Group, including nested children', () {
      final group = Group(
        id: 'group-1',
        transform: const LayerTransform(position: Point2D(10, 10)),
        children: [
          RectangleLayer(size: const Size2D(50, 50)),
          Group(children: [TextLayer(text: 'nested')]),
        ],
      );

      final decoded =
          LayerRegistry.decodeLayer(_throughJsonText(group.toJson())) as Group;

      expect(decoded.children, hasLength(2));
      expect(decoded.children[0], isA<RectangleLayer>());
      expect(decoded.children[1], isA<Group>());
      final nestedGroup = decoded.children[1] as Group;
      expect(nestedGroup.children.single, isA<TextLayer>());
      expect((nestedGroup.children.single as TextLayer).text, 'nested');
    });

    test('an unknown type throws ArgumentError', () {
      expect(
        () => LayerRegistry.decodeLayer({'type': 'nonexistent'}),
        throwsArgumentError,
      );
    });
  });

  group('Scene round-trips', () {
    test('an empty scene', () {
      final scene = Scene(width: 800, height: 600);

      final decoded = Scene.fromJson(_throughJsonText(scene.toJson()));

      expect(decoded.width, 800);
      expect(decoded.height, 600);
      expect(decoded.background, isNull);
      expect(decoded.layers, isEmpty);
    });

    test('a scene with a background and multiple layers', () {
      final scene =
          Scene(
            width: 400,
            height: 300,
            background: const LayerImageSource.file('/tmp/bg.png'),
          )..addAll([
            RectangleLayer.filled(
              width: 400,
              height: 300,
              color: Color32.fromRGB(20, 20, 20),
            ),
            TextLayer(text: 'watermark', zIndex: 1),
          ]);

      final decoded = Scene.fromJson(_throughJsonText(scene.toJson()));

      expect(decoded.width, scene.width);
      expect(decoded.height, scene.height);
      expect(decoded.background, isA<FileImageSource>());
      expect(decoded.layers, hasLength(2));
      expect(decoded.layers[0], isA<RectangleLayer>());
      expect(decoded.layers[1], isA<TextLayer>());
    });
  });

  group('LayerRegistry extensibility', () {
    test('a custom Layer subclass round-trips once registered', () {
      LayerRegistry.registerLayer('badge', _BadgeLayer.fromJson);
      addTearDown(() {
        // Not strictly necessary (the registry is process-global and tests
        // don't reset it) but keeps this test's side effect self-contained.
      });

      final badge = _BadgeLayer(label: 'PRO');
      final scene = Scene(width: 10, height: 10)..add(badge);

      final decoded = Scene.fromJson(_throughJsonText(scene.toJson()));

      expect(decoded.layers.single, isA<_BadgeLayer>());
      expect((decoded.layers.single as _BadgeLayer).label, 'PRO');
    });
  });
}

/// A minimal custom [Layer] subclass, used only to prove
/// [LayerRegistry.registerLayer] lets a consumer's own layer type round-trip
/// through [Scene.toJson]/[Scene.fromJson] without any change to this
/// package.
class _BadgeLayer extends Layer {
  final String label;

  _BadgeLayer({required this.label, super.id});

  @override
  String get type => 'badge';

  @override
  Map<String, Object?> get properties => {'label': label};

  @override
  Map<String, Object?> toJson() => {
    ...commonJson(),
    'properties': {'label': label},
  };

  factory _BadgeLayer.fromJson(Map<String, Object?> json) {
    final common = parseCommonLayerJson(json);
    final properties = json['properties'] as Map<String, Object?>;
    return _BadgeLayer(label: properties['label'] as String, id: common.id);
  }
}
