import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:layer_canvas/layer_canvas.dart';
import 'package:layer_canvas/layer_canvas_bindings_generated.dart'
    as bindings;
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
      expect(_readText(desc), utf8.encode(text.substring(
        0,
        bindings.LC_TEXT_MAX_BYTES,
      )));
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
      expect(
        desc.image_data.asTypedList(desc.image_data_size),
        pngBytes,
      );
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

List<int> _readText(bindings.LcLayerDesc desc) =>
    [for (var i = 0; i < desc.text_length; i++) desc.text[i]];
