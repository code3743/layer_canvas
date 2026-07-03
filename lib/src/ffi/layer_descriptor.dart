import 'dart:convert';
import 'dart:ffi';

import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../model/geometry.dart';
import '../model/layer.dart';
import '../model/layers/rectangle_layer.dart';
import '../model/layers/text_layer.dart';

/// Fills a native [bindings.LcLayerDesc] slot from a Dart [Layer].
///
/// Returns `true` if the native engine has a renderer for this layer's
/// runtime type, `false` otherwise. Callers should not count a `false`
/// layer towards the layer count passed to `lc_render_scene` - this is
/// what lets the Dart model support layer kinds (ImageLayer, Group, any
/// future CustomLayer...) before the native side implements them, without
/// the render call failing.
bool fillNativeLayerDesc(bindings.LcLayerDesc desc, Layer layer) {
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

  desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_UNKNOWN.value;
  return false;
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
