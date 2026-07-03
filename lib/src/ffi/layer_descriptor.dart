import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../model/geometry.dart';
import '../model/image_source.dart';
import '../model/layer.dart';
import '../model/layers/image_layer.dart';
import '../model/layers/rectangle_layer.dart';
import '../model/layers/text_layer.dart';

/// Fills a native [bindings.LcLayerDesc] slot from a Dart [Layer].
///
/// An [ImageLayer] allocates a native buffer for its encoded bytes and
/// appends it to [ownedBuffers] — unlike `text`/`font_family`, image bytes
/// aren't copied into a fixed-size inline array, so the caller must
/// `calloc.free` every entry in [ownedBuffers] once the render call that
/// reads them has returned (see `Renderer._renderSync`).
///
/// Returns `true` if the native engine has a renderer for this layer's
/// runtime type, `false` otherwise. Callers should not count a `false`
/// layer towards the layer count passed to `lc_render_scene` - this is
/// what lets the Dart model support layer kinds (Group, any future
/// CustomLayer...) before the native side implements them, without the
/// render call failing.
bool fillNativeLayerDesc(
  bindings.LcLayerDesc desc,
  Layer layer, {
  required List<Pointer<Uint8>> ownedBuffers,
}) {
  final transform = layer.transform;
  final size = layer.size ?? Size2D.zero;

  desc.pos_x = transform.position.x;
  desc.pos_y = transform.position.y;
  desc.width = size.width;
  desc.height = size.height;
  desc.rotation = transform.rotation;
  desc.scale_x = transform.scale.x;
  desc.scale_y = transform.scale.y;
  desc.anchor_x = transform.anchor.x;
  desc.anchor_y = transform.anchor.y;
  desc.opacity = layer.opacity;

  if (layer is RectangleLayer) {
    desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_RECTANGLE.value;
    desc.rect_color_argb = layer.paint.color.value;
    desc.rect_paint_style = layer.paint.style.index;
    desc.rect_stroke_width = layer.paint.strokeWidth;
    desc.rect_corner_radius = layer.cornerRadius;
    return true;
  }

  if (layer is TextLayer) {
    desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_TEXT.value;

    final bytes = _truncatedUtf8(layer.text, bindings.LC_TEXT_MAX_BYTES);
    for (var i = 0; i < bytes.length; i++) {
      desc.text[i] = bytes[i];
    }
    desc.text_length = bytes.length;

    desc.text_font_size = layer.fontSize;
    desc.text_color_argb = layer.color.value;
    desc.text_align = layer.align.index;
    desc.text_weight = layer.fontWeight.value;

    final fontFamily = layer.fontFamily;
    if (fontFamily != null) {
      final familyBytes = _truncatedUtf8(
        fontFamily,
        bindings.LC_FONT_FAMILY_MAX_BYTES,
      );
      for (var i = 0; i < familyBytes.length; i++) {
        desc.font_family[i] = familyBytes[i];
      }
      desc.font_family_length = familyBytes.length;
    } else {
      desc.font_family_length = 0;
    }
    return true;
  }

  if (layer is ImageLayer) {
    desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_IMAGE.value;

    final bytes = _resolveImageBytes(layer.source);
    final buffer = calloc<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    ownedBuffers.add(buffer);

    desc.image_data = buffer;
    desc.image_data_size = bytes.length;
    desc.image_fit = layer.fit.index;
    return true;
  }

  desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_UNKNOWN.value;
  return false;
}

/// Resolves a [LayerImageSource] to its raw encoded bytes. Done on the Dart
/// side (rather than passing a file path across FFI) so the wire format
/// only ever needs to carry "just bytes", and so the native side never
/// touches the filesystem directly.
Uint8List _resolveImageBytes(LayerImageSource source) {
  if (source is MemoryImageSource) return source.bytes;
  if (source is FileImageSource) return File(source.path).readAsBytesSync();
  throw ArgumentError('Unsupported LayerImageSource: $source');
}

/// Encodes [text] as UTF-8, truncated to at most [maxBytes] bytes without
/// splitting a multi-byte code point in half.
///
/// A naive `bytes.sublist(0, maxBytes)` can cut a multi-byte character (an
/// accented letter, `°`, an emoji...) mid-sequence, leaving dangling
/// continuation bytes for the native side to choke on. UTF-8 continuation
/// bytes always match `10xxxxxx`, so backing up until we land on a
/// non-continuation byte finds the nearest safe boundary.
List<int> _truncatedUtf8(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return bytes;

  var end = maxBytes;
  while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
    end--;
  }
  return bytes.sublist(0, end);
}
