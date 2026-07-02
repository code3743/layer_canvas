import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../ffi/layer_descriptor.dart';
import '../model/scene.dart';

/// Renders a [Scene] to image bytes using the native compositing engine.
///
/// The native call itself is currently made synchronously on the calling
/// isolate. A later stage moves it onto a background `Isolate` so it never
/// blocks the caller's event loop - `render`/`renderToFile` are already
/// `async` so that change won't be a breaking one.
class Renderer {
  const Renderer();

  /// Renders [scene] and returns the encoded image bytes (PNG).
  ///
  /// Throws a [RenderException] if the native engine fails to produce an
  /// image.
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
    try {
      var nativeCount = 0;
      for (final layer in renderable) {
        final slot = (nativeLayers + nativeCount).ref;
        if (fillNativeLayerDesc(slot, layer)) {
          nativeCount++;
        }
      }

      final outData = calloc<Pointer<Uint8>>();
      final outLen = calloc<Size>();
      try {
        // ignore: avoid_print
        print('DEBUG: calling lc_render_scene, nativeCount=$nativeCount');
        final status = bindings.lc_render_scene(
          scene.width,
          scene.height,
          nativeCount == 0 ? nullptr : nativeLayers,
          nativeCount,
          outData,
          outLen,
        );
        // ignore: avoid_print
        print('DEBUG: lc_render_scene returned status=$status');
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
