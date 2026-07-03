import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../model/geometry.dart';
import '../model/layer.dart';
import '../model/layers/rectangle_layer.dart';

/// Fills a native [bindings.LcLayerDesc] slot from a Dart [Layer].
///
/// Returns `true` if the native engine has a renderer for this layer's
/// runtime type, `false` otherwise. Callers should not count a `false`
/// layer towards the layer count passed to `lc_render_scene` - this is
/// what lets the Dart model support layer kinds (ImageLayer, TextLayer,
/// Group, any future CustomLayer...) before the native side implements
/// them, without the render call failing.
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

  desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_UNKNOWN.value;
  return false;
}
