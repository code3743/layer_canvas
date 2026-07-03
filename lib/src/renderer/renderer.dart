import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../ffi/layer_descriptor.dart';
import '../model/scene.dart';

/// Renders a [Scene] to PNG bytes using the native Blend2D compositing engine.
///
/// ```dart
/// final scene = Scene(width: 800, height: 600)
///   ..add(RectangleLayer(
///     size: const Size2D(800, 600),
///     paint: const LayerPaint(color: Color32.fromRGB(30, 30, 30)),
///   ));
/// final bytes = await Renderer().render(scene);
/// ```
///
/// `render` is `async` so future versions can move the native call off the
/// UI isolate without a breaking API change.
class Renderer {
  const Renderer();

  /// Renders [scene] and returns the encoded PNG bytes.
  ///
  /// Throws a [RenderException] if the native engine returns a non-zero status.
  Future<Uint8List> render(Scene scene) async => _renderSync(scene);

  /// Renders [scene] and writes the encoded bytes to [outputPath].
  Future<void> renderToFile(Scene scene, String outputPath) async {
    final bytes = await render(scene);
    await File(outputPath).writeAsBytes(bytes);
  }

  Uint8List _renderSync(Scene scene) {
    final renderable = scene.layers.where((layer) => layer.visible).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    final nativeLayers = calloc<bindings.LcLayerDesc>(renderable.length);
    // Native buffers allocated for ImageLayer bytes (see
    // fillNativeLayerDesc) — these live only for the duration of the
    // lc_render_scene call below, unlike text/font_family which are copied
    // inline into the struct itself.
    final ownedBuffers = <Pointer<Uint8>>[];
    try {
      var nativeCount = 0;
      for (final layer in renderable) {
        final slot = (nativeLayers + nativeCount).ref;
        if (fillNativeLayerDesc(slot, layer, ownedBuffers: ownedBuffers)) {
          nativeCount++;
        }
      }

      final outData = calloc<Pointer<Uint8>>();
      final outLen = calloc<Size>();
      try {
        final status = bindings.lc_render_scene(
          scene.width,
          scene.height,
          nativeCount == 0 ? nullptr : nativeLayers,
          nativeCount,
          outData,
          outLen,
        );
        if (status != 0) {
          throw RenderException(
            'Native render failed with status $status',
          );
        }

        final bytes = Uint8List.fromList(
          outData.value.asTypedList(outLen.value),
        );
        bindings.lc_buffer_free(outData.value);
        return bytes;
      } finally {
        calloc.free(outData);
        calloc.free(outLen);
      }
    } finally {
      for (final buffer in ownedBuffers) {
        calloc.free(buffer);
      }
      calloc.free(nativeLayers);
    }
  }
}

/// Thrown when the native engine fails to render a [Scene].
class RenderException implements Exception {
  final String message;

  RenderException(this.message);

  @override
  String toString() => 'RenderException: $message';
}
