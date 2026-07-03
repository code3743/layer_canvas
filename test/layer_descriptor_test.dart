import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:layer_canvas/layer_canvas.dart';
import 'package:layer_canvas/layer_canvas_bindings_generated.dart' as bindings;
import 'package:layer_canvas/src/ffi/layer_descriptor.dart';
import 'package:test/test.dart';

void main() {
  group('fillNativeLayerDesc (TextLayer)', () {
    late Pointer<bindings.LcLayerDesc> descPtr;
    late bindings.LcLayerDesc desc;

    setUp(() {
      descPtr = calloc<bindings.LcLayerDesc>();
      desc = descPtr.ref;
    });

    tearDown(() => calloc.free(descPtr));

    test('marshals text, style and layout fields into the native struct', () {
      final handled = fillNativeLayerDesc(
        desc,
        TextLayer(
          text: 'gatito',
          fontSize: 22,
          color: Color32.white,
          align: TextAlignment.center,
          fontWeight: TextWeight.bold,
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: [],
      );

      expect(handled, isTrue);
      expect(desc.kind, bindings.LcLayerKind.LC_LAYER_KIND_TEXT.value);
      expect(desc.text_length, 6);
      expect(_readText(desc), utf8.encode('gatito'));
      expect(desc.text_font_size, 22);
      expect(desc.text_color_argb, Color32.white.value);
      expect(desc.text_align, TextAlignment.center.index);
      expect(desc.text_weight, TextWeight.bold.value);
    });

    test('truncates text longer than LC_TEXT_MAX_BYTES', () {
      final text = 'a' * (bindings.LC_TEXT_MAX_BYTES + 50);

      fillNativeLayerDesc(
        desc,
        TextLayer(text: text),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: [],
      );

      expect(desc.text_length, bindings.LC_TEXT_MAX_BYTES);
      expect(
        _readText(desc),
        utf8.encode(text.substring(0, bindings.LC_TEXT_MAX_BYTES)),
      );
    });

    test('truncation never splits a multi-byte code point', () {
      // '°' is 2 UTF-8 bytes, so a naive cut at LC_TEXT_MAX_BYTES (even)
      // would land cleanly here only by coincidence; pad with one ASCII
      // byte so the boundary falls in the middle of a '°' character.
      final text = 'x${'°' * 200}'; // 1 + 400 = 401 bytes.

      fillNativeLayerDesc(
        desc,
        TextLayer(text: text),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: [],
      );

      final bytes = _readText(desc);
      expect(bytes.length, lessThanOrEqualTo(bindings.LC_TEXT_MAX_BYTES));
      expect(() => utf8.decode(bytes), returnsNormally);
    });
  });

  group('fillNativeLayerDesc (RectangleLayer paint)', () {
    late Pointer<bindings.LcLayerDesc> descPtr;
    late bindings.LcLayerDesc desc;
    late List<Pointer> ownedBuffers;

    setUp(() {
      descPtr = calloc<bindings.LcLayerDesc>();
      desc = descPtr.ref;
      ownedBuffers = [];
    });

    tearDown(() {
      for (final buffer in ownedBuffers) {
        calloc.free(buffer);
      }
      calloc.free(descPtr);
    });

    test('a solid color paint marshals as LC_PAINT_KIND_SOLID', () {
      final handled = fillNativeLayerDesc(
        desc,
        RectangleLayer(
          size: const Size2D(10, 10),
          paint: const LayerPaint(color: Color32.fromRGB(10, 20, 30)),
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(handled, isTrue);
      expect(
        desc.rect_paint.kind,
        bindings.LcPaintKind.LC_PAINT_KIND_SOLID.value,
      );
      expect(
        desc.rect_paint.solid_color_argb,
        const Color32.fromRGB(10, 20, 30).value,
      );
      expect(desc.rect_paint.stop_count, 0);
      expect(ownedBuffers, isEmpty);
    });

    test('a LinearGradient marshals kind, values and stops', () {
      final handled = fillNativeLayerDesc(
        desc,
        RectangleLayer(
          size: const Size2D(10, 10),
          paint: const LayerPaint(
            gradient: LinearGradient(
              start: Point2D(0, 0),
              end: Point2D(1, 1),
              stops: [
                GradientStop(0, Color32.black),
                GradientStop(0.5, Color32.white),
                GradientStop(1, Color32.transparent),
              ],
              extendMode: GradientExtendMode.repeat,
            ),
          ),
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(handled, isTrue);
      expect(
        desc.rect_paint.kind,
        bindings.LcPaintKind.LC_PAINT_KIND_LINEAR_GRADIENT.value,
      );
      expect(
        desc.rect_paint.extend_mode,
        bindings.LcExtendMode.LC_EXTEND_MODE_REPEAT.value,
      );
      expect(
        [for (var i = 0; i < 4; i++) desc.rect_paint.values[i]],
        [0.0, 0.0, 1.0, 1.0],
      );
      expect(desc.rect_paint.stop_count, 3);
      expect(ownedBuffers, hasLength(1));

      final stops = desc.rect_paint.stops;
      expect(stops[0].offset, 0);
      expect(stops[0].color_argb, Color32.black.value);
      expect(stops[1].offset, 0.5);
      expect(stops[1].color_argb, Color32.white.value);
      expect(stops[2].offset, 1);
      expect(stops[2].color_argb, Color32.transparent.value);
    });

    test('a RadialGradient marshals center and radius into values', () {
      fillNativeLayerDesc(
        desc,
        RectangleLayer(
          size: const Size2D(10, 10),
          paint: const LayerPaint(
            gradient: RadialGradient(
              center: Point2D(0.5, 0.5),
              radius: 0.25,
              stops: [GradientStop(0, Color32.white)],
            ),
          ),
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(
        desc.rect_paint.kind,
        bindings.LcPaintKind.LC_PAINT_KIND_RADIAL_GRADIENT.value,
      );
      expect(
        [for (var i = 0; i < 3; i++) desc.rect_paint.values[i]],
        [0.5, 0.5, 0.25],
      );
    });

    test('a ConicGradient marshals center and angle into values', () {
      fillNativeLayerDesc(
        desc,
        RectangleLayer(
          size: const Size2D(10, 10),
          paint: const LayerPaint(
            gradient: ConicGradient(
              center: Point2D(0.5, 0.5),
              angle: 1.25,
              stops: [GradientStop(0, Color32.white)],
            ),
          ),
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(
        desc.rect_paint.kind,
        bindings.LcPaintKind.LC_PAINT_KIND_CONIC_GRADIENT.value,
      );
      expect(
        [for (var i = 0; i < 3; i++) desc.rect_paint.values[i]],
        [0.5, 0.5, 1.25],
      );
    });
  });

  group('fillNativeLayerDesc (PathLayer)', () {
    late Pointer<bindings.LcLayerDesc> descPtr;
    late bindings.LcLayerDesc desc;
    late List<Pointer> ownedBuffers;

    setUp(() {
      descPtr = calloc<bindings.LcLayerDesc>();
      desc = descPtr.ref;
      ownedBuffers = [];
    });

    tearDown(() {
      for (final buffer in ownedBuffers) {
        calloc.free(buffer);
      }
      calloc.free(descPtr);
    });

    List<int> readCommands() => [
      for (var i = 0; i < desc.path_command_count; i++) desc.path_commands[i],
    ];

    List<double> readCoords() => [
      for (var i = 0; i < desc.path_coord_count; i++) desc.path_coords[i],
    ];

    test('a polygon marshals its commands and coordinates', () {
      final handled = fillNativeLayerDesc(
        desc,
        PathLayer(
          path: LayerPath.polygon(const [
            Point2D(0, 0),
            Point2D(10, 0),
            Point2D(5, 10),
          ]),
          paint: const LayerPaint(color: Color32.fromRGB(0, 180, 90)),
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(handled, isTrue);
      expect(desc.kind, bindings.LcLayerKind.LC_LAYER_KIND_PATH.value);
      expect(readCommands(), [
        bindings.LcPathCommand.LC_PATH_COMMAND_MOVE_TO.value,
        bindings.LcPathCommand.LC_PATH_COMMAND_LINE_TO.value,
        bindings.LcPathCommand.LC_PATH_COMMAND_LINE_TO.value,
        bindings.LcPathCommand.LC_PATH_COMMAND_CLOSE.value,
      ]);
      expect(readCoords(), [0.0, 0.0, 10.0, 0.0, 5.0, 10.0]);
      // ownedBuffers holds both the commands buffer and the coords buffer.
      expect(ownedBuffers, hasLength(2));
    });

    test(
      'quadratic and cubic Bézier commands marshal their control points',
      () {
        fillNativeLayerDesc(
          desc,
          PathLayer(
            path: LayerPath([
              MoveTo(Point2D(0, 0)),
              QuadraticBezierTo(Point2D(5, 5), Point2D(10, 0)),
              CubicBezierTo(Point2D(12, 5), Point2D(8, 10), Point2D(0, 10)),
              ClosePath(),
            ]),
          ),
          transform: const LayerTransform(),
          opacity: 1.0,
          ownedBuffers: ownedBuffers,
        );

        expect(readCommands(), [
          bindings.LcPathCommand.LC_PATH_COMMAND_MOVE_TO.value,
          bindings.LcPathCommand.LC_PATH_COMMAND_QUAD_TO.value,
          bindings.LcPathCommand.LC_PATH_COMMAND_CUBIC_TO.value,
          bindings.LcPathCommand.LC_PATH_COMMAND_CLOSE.value,
        ]);
        expect(readCoords(), [
          0.0,
          0.0,
          5.0,
          5.0,
          10.0,
          0.0,
          12.0,
          5.0,
          8.0,
          10.0,
          0.0,
          10.0,
        ]);
      },
    );

    test('ArcTo marshals radii, rotation, flags and endpoint', () {
      fillNativeLayerDesc(
        desc,
        PathLayer(
          path: LayerPath([
            MoveTo(const Point2D(200, 100)),
            const ArcTo(
              radiusX: 100,
              radiusY: 60,
              xAxisRotation: 0.5,
              largeArc: true,
              sweep: true,
              point: Point2D(0, 100),
            ),
          ]),
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(readCommands(), [
        bindings.LcPathCommand.LC_PATH_COMMAND_MOVE_TO.value,
        bindings.LcPathCommand.LC_PATH_COMMAND_ARC_TO.value,
      ]);
      expect(readCoords(), [
        200.0,
        100.0,
        100.0,
        60.0,
        0.5,
        1.0,
        1.0,
        0.0,
        100.0,
      ]);
    });

    test('fillRule marshals to LC_FILL_RULE_EVEN_ODD', () {
      fillNativeLayerDesc(
        desc,
        PathLayer(
          path: LayerPath.polygon(const [
            Point2D(0, 0),
            Point2D(10, 0),
            Point2D(5, 10),
          ]),
          fillRule: FillRule.evenOdd,
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(
        desc.path_fill_rule,
        bindings.LcFillRule.LC_FILL_RULE_EVEN_ODD.value,
      );
    });

    test('reuses paint marshaling — a gradient paint marshals through '
        'path_paint', () {
      fillNativeLayerDesc(
        desc,
        PathLayer(
          path: LayerPath.polygon(const [
            Point2D(0, 0),
            Point2D(10, 0),
            Point2D(5, 10),
          ]),
          paint: const LayerPaint(
            gradient: LinearGradient(
              start: Point2D(0, 0),
              end: Point2D(1, 1),
              stops: [
                GradientStop(0, Color32.black),
                GradientStop(1, Color32.white),
              ],
            ),
          ),
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(
        desc.path_paint.kind,
        bindings.LcPaintKind.LC_PAINT_KIND_LINEAR_GRADIENT.value,
      );
      expect(desc.path_paint.stop_count, 2);
      // commands buffer + coords buffer + gradient stops buffer.
      expect(ownedBuffers, hasLength(3));
    });
  });

  group('fillNativeLayerDesc (ImageLayer)', () {
    late Pointer<bindings.LcLayerDesc> descPtr;
    late bindings.LcLayerDesc desc;
    late List<Pointer<Uint8>> ownedBuffers;
    late Uint8List pngBytes;

    setUpAll(() async {
      // A real, tiny PNG produced by the renderer itself - no fixture file
      // needed, and it's guaranteed to be valid, decodable image data.
      final scene = Scene(width: 4, height: 4)
        ..add(
          RectangleLayer(
            size: const Size2D(4, 4),
            paint: const LayerPaint(color: Color32.fromRGB(10, 20, 30)),
          ),
        );
      pngBytes = await const Renderer().render(scene);
    });

    setUp(() {
      descPtr = calloc<bindings.LcLayerDesc>();
      desc = descPtr.ref;
      ownedBuffers = [];
    });

    tearDown(() {
      for (final buffer in ownedBuffers) {
        calloc.free(buffer);
      }
      calloc.free(descPtr);
    });

    test('marshals a MemoryImageSource\'s bytes and fit into the native '
        'struct', () {
      final handled = fillNativeLayerDesc(
        desc,
        ImageLayer(
          source: LayerImageSource.memory(pngBytes),
          fit: ImageFit.cover,
        ),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(handled, isTrue);
      expect(desc.kind, bindings.LcLayerKind.LC_LAYER_KIND_IMAGE.value);
      expect(desc.image_data_size, pngBytes.length);
      expect(desc.image_fit, ImageFit.cover.index);
      expect(ownedBuffers, hasLength(1));
      expect(desc.image_data.asTypedList(desc.image_data_size), pngBytes);
    });

    test('reads a FileImageSource from disk', () async {
      final tempFile = await File(
        '${Directory.systemTemp.path}/layer_canvas_image_layer_test.png',
      ).create();
      await tempFile.writeAsBytes(pngBytes);
      addTearDown(() => tempFile.delete());

      final handled = fillNativeLayerDesc(
        desc,
        ImageLayer(source: LayerImageSource.file(tempFile.path)),
        transform: const LayerTransform(),
        opacity: 1.0,
        ownedBuffers: ownedBuffers,
      );

      expect(handled, isTrue);
      expect(desc.image_data_size, pngBytes.length);
      expect(desc.image_data.asTypedList(desc.image_data_size), pngBytes);
    });
  });
}

List<int> _readText(bindings.LcLayerDesc desc) => [
  for (var i = 0; i < desc.text_length; i++) desc.text[i],
];
