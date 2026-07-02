import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:layer_canvas/layer_canvas_bindings_generated.dart' as bindings;
import 'package:test/test.dart';

/// PNG files always start with this fixed 8-byte signature.
const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('lc_image', () {
    test('create/destroy a canvas does not crash', () {
      final image = bindings.lc_image_create(4, 4);
      expect(image, isNot(equals(nullptr)));
      bindings.lc_image_destroy(image);
    });

    test('create rejects non-positive dimensions', () {
      expect(bindings.lc_image_create(0, 10), equals(nullptr));
      expect(bindings.lc_image_create(10, 0), equals(nullptr));
      expect(bindings.lc_image_create(-1, 10), equals(nullptr));
    });

    test('destroy(nullptr) is a no-op', () {
      bindings.lc_image_destroy(nullptr);
    });

    test('clear + encode_png produces a valid, non-empty PNG', () {
      final image = bindings.lc_image_create(32, 16);
      addTearDown(() => bindings.lc_image_destroy(image));

      bindings.lc_image_clear(image, 0xFFFF0000); // opaque red

      final outData = calloc<Pointer<Uint8>>();
      final outLen = calloc<Size>();
      addTearDown(() {
        calloc.free(outData);
        calloc.free(outLen);
      });

      final status = bindings.lc_image_encode_png(image, outData, outLen);
      expect(status, 0);

      final len = outLen.value;
      expect(len, greaterThan(_pngSignature.length));

      final bytes = outData.value.asTypedList(len);
      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);

      bindings.lc_buffer_free(outData.value);
    });

    test('encode_png fails gracefully for a null image', () {
      final outData = calloc<Pointer<Uint8>>();
      final outLen = calloc<Size>();
      addTearDown(() {
        calloc.free(outData);
        calloc.free(outLen);
      });

      final status = bindings.lc_image_encode_png(nullptr, outData, outLen);
      expect(status, isNot(0));
    });

    test('buffer_free(nullptr) is a no-op', () {
      bindings.lc_buffer_free(nullptr);
    });
  });
}
