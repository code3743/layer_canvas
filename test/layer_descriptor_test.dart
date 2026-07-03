import 'dart:convert';
import 'dart:ffi';

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

      fillNativeLayerDesc(desc, TextLayer(text: text));

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

      fillNativeLayerDesc(desc, TextLayer(text: text));

      final bytes = _readText(desc);
      expect(bytes.length, lessThanOrEqualTo(bindings.LC_TEXT_MAX_BYTES));
      expect(() => utf8.decode(bytes), returnsNormally);
    });
  });
}

List<int> _readText(bindings.LcLayerDesc desc) =>
    [for (var i = 0; i < desc.text_length; i++) desc.text[i]];
