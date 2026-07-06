import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../ffi/layer_descriptor.dart';
import '../model/geometry.dart';
import '../model/layers/image_layer.dart';
import '../model/scene.dart';
import '../model/transform.dart';
import 'scene_flattener.dart';

/// An encoded image format a [Renderer] can produce.
///
/// JPEG is deliberately not offered: the native engine's Blend2D backend
/// only implements JPEG *decoding* (used by [ImageLayer] sources), not
/// encoding — its JPEG encoder is an upstream stub that always fails
/// (`BL_ERROR_IMAGE_ENCODER_NOT_PROVIDED`).
enum OutputFormat {
  /// Lossless, widely supported, the default. Larger files than [qoi] for
  /// most rendered UI content (flat colors, text, gradients).
  png,

  /// Uncompressed. Larger files than [png]/[qoi]; mainly useful when
  /// encoding speed matters more than size, or a consumer specifically
  /// needs a BMP.
  bmp,

  /// Lossless, simpler and typically faster to encode/decode than PNG, at
  /// the cost of being a far less widely supported format outside
  /// image-processing tooling.
  qoi,
}

/// Renders a [Scene] to encoded image bytes using the native Blend2D
/// compositing engine.
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
  /// Creates a renderer. Stateless — safe to construct once and reuse, or
  /// construct fresh per render.
  const Renderer();

  /// Renders [scene] and returns the encoded bytes, as [format] (defaults to
  /// PNG).
  ///
  /// Throws a [RenderException] if the native engine returns a non-zero status.
  Future<Uint8List> render(
    Scene scene, {
    OutputFormat format = OutputFormat.png,
  }) async => _renderSync(scene, format);

  /// Renders [scene] and writes the encoded bytes to [outputPath], as
  /// [format] (defaults to PNG). [outputPath]'s extension is not inspected —
  /// pass a matching one yourself if that matters to you.
  Future<void> renderToFile(
    Scene scene,
    String outputPath, {
    OutputFormat format = OutputFormat.png,
  }) async {
    final bytes = await render(scene, format: format);
    await File(outputPath).writeAsBytes(bytes);
  }

  Uint8List _renderSync(Scene scene, OutputFormat format) {
    final background = scene.background;
    final renderable = <ResolvedLayer>[
      // Painted first (bottom of the stack), covering the whole canvas,
      // regardless of any layer's zIndex - matches Scene.background's doc
      // comment ("painted before any layer").
      if (background != null)
        ResolvedLayer(
          ImageLayer(
            source: background,
            size: Size2D(scene.width.toDouble(), scene.height.toDouble()),
            fit: ImageFit.cover,
          ),
          const LayerTransform(),
          1.0,
        ),
      ...flattenScene(scene.layers),
    ];

    final nativeLayers = calloc<bindings.LcLayerDesc>(renderable.length);
    // Native buffers allocated for ImageLayer bytes and gradient stops (see
    // fillNativeLayerDesc) — these live only for the duration of the
    // lc_render_scene call below, unlike text/font_family which are copied
    // inline into the struct itself.
    final ownedBuffers = <Pointer>[];
    try {
      var nativeCount = 0;
      for (final resolved in renderable) {
        final slot = (nativeLayers + nativeCount).ref;
        if (fillNativeLayerDesc(
          slot,
          resolved.source,
          transform: resolved.transform,
          opacity: resolved.opacity,
          ownedBuffers: ownedBuffers,
        )) {
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
          format.index,
          outData,
          outLen,
        );
        if (status != 0) {
          throw RenderException('Native render failed with status $status');
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
  /// Description of what went wrong.
  final String message;

  /// Creates an exception with the given [message].
  RenderException(this.message);

  @override
  String toString() => 'RenderException: $message';
}
