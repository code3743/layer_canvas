import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../model/geometry.dart';
import '../model/gradient.dart';
import '../model/image_source.dart';
import '../model/layer.dart';
import '../model/layers/image_layer.dart';
import '../model/layers/path_layer.dart';
import '../model/layers/rectangle_layer.dart';
import '../model/layers/text_layer.dart';
import '../model/paint.dart';
import '../model/path.dart';
import '../model/transform.dart';
import '../renderer/path_dasher.dart';

/// Fills a native [bindings.LcLayerDesc] slot from a Dart [Layer].
///
/// [transform] and [opacity] are the layer's *effective* (world-space)
/// values — already composed with every ancestor [Group] by
/// [flattenScene][flatten], not necessarily `layer.transform`/`layer.opacity`
/// directly. [transform] is always in canonical form (`anchor` is `(0,0)`).
///
/// An [ImageLayer] allocates a native buffer for its encoded bytes, and a
/// [RectangleLayer] painted with a [Gradient] allocates one for its stops;
/// both are appended to [ownedBuffers] — unlike `text`/`font_family`, these
/// aren't copied into a fixed-size inline array, so the caller must
/// `calloc.free` every entry in [ownedBuffers] once the render call that
/// reads them has returned (see `Renderer._renderSync`).
///
/// Returns `true` if the native engine has a renderer for this layer's
/// runtime type, `false` otherwise. Callers should not count a `false`
/// layer towards the layer count passed to `lc_render_scene` - this is
/// what lets the Dart model support layer kinds (any future CustomLayer...)
/// before the native side implements them, without the render call failing.
///
/// [flatten]: package:layer_canvas/src/renderer/scene_flattener.dart
bool fillNativeLayerDesc(
  bindings.LcLayerDesc desc,
  Layer layer, {
  required LayerTransform transform,
  required double opacity,
  required List<Pointer> ownedBuffers,
}) {
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
  desc.opacity = opacity;

  if (layer is RectangleLayer) {
    desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_RECTANGLE.value;
    _fillPaintDesc(desc.rect_paint, layer.paint, ownedBuffers);
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

  if (layer is PathLayer) {
    desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_PATH.value;
    _fillPaintDesc(desc.path_paint, layer.paint, ownedBuffers);
    desc.path_paint_style = layer.paint.style.index;
    desc.path_stroke_width = layer.paint.strokeWidth;
    desc.path_fill_rule = layer.fillRule.index;

    // A non-empty dashArray is resolved into plain on-segment geometry here
    // (see path_dasher.dart) rather than sent to the native side, which
    // can't render it (Blend2D's own dash support is a no-op - see
    // scene_desc.h's LcPaintDesc doc comment).
    final dashArray = layer.paint.dashArray;
    final geometry = dashArray.isEmpty
        ? layer.path
        : dashPath(layer.path, dashArray, layer.paint.dashOffset);
    _fillPathGeometry(desc, geometry, ownedBuffers);
    return true;
  }

  desc.kind = bindings.LcLayerKind.LC_LAYER_KIND_UNKNOWN.value;
  return false;
}

/// Fills a native [bindings.LcPaintDesc] slot from a [LayerPaint] — solid
/// [LayerPaint.color] when [LayerPaint.gradient] is unset, otherwise the
/// gradient's kind, geometry, extend mode and stops; plus stroke cap/join/
/// miter limit, which apply regardless of fill source.
///
/// [LayerPaint.dashArray]/[LayerPaint.dashOffset] are deliberately not
/// marshaled here — see `path_dasher.dart`'s doc comment for why a dash
/// pattern is resolved into plain path geometry on the Dart side instead
/// of being sent to the native side at all.
///
/// Stops are copied into a native buffer appended to [ownedBuffers] (option
/// (b): pointer + count, same ownership pattern as `ImageLayer`'s encoded
/// bytes above) rather than a fixed-size inline array, since a gradient may
/// carry an arbitrary number of stops.
void _fillPaintDesc(
  bindings.LcPaintDesc desc,
  LayerPaint paint,
  List<Pointer> ownedBuffers,
) {
  desc.stroke_cap = switch (paint.strokeCap) {
    StrokeCap.butt => bindings.LcStrokeCap.LC_STROKE_CAP_BUTT.value,
    StrokeCap.round => bindings.LcStrokeCap.LC_STROKE_CAP_ROUND.value,
    StrokeCap.square => bindings.LcStrokeCap.LC_STROKE_CAP_SQUARE.value,
  };
  desc.stroke_join = switch (paint.strokeJoin) {
    StrokeJoin.miter => bindings.LcStrokeJoin.LC_STROKE_JOIN_MITER.value,
    StrokeJoin.round => bindings.LcStrokeJoin.LC_STROKE_JOIN_ROUND.value,
    StrokeJoin.bevel => bindings.LcStrokeJoin.LC_STROKE_JOIN_BEVEL.value,
  };
  desc.stroke_miter_limit = paint.miterLimit;

  final gradient = paint.gradient;
  if (gradient == null) {
    desc.kind = bindings.LcPaintKind.LC_PAINT_KIND_SOLID.value;
    desc.solid_color_argb = paint.color.value;
    desc.stop_count = 0;
    return;
  }

  switch (gradient) {
    case LinearGradient():
      desc.kind = bindings.LcPaintKind.LC_PAINT_KIND_LINEAR_GRADIENT.value;
      desc.values[0] = gradient.start.x;
      desc.values[1] = gradient.start.y;
      desc.values[2] = gradient.end.x;
      desc.values[3] = gradient.end.y;
    case RadialGradient():
      desc.kind = bindings.LcPaintKind.LC_PAINT_KIND_RADIAL_GRADIENT.value;
      desc.values[0] = gradient.center.x;
      desc.values[1] = gradient.center.y;
      desc.values[2] = gradient.radius;
    case ConicGradient():
      desc.kind = bindings.LcPaintKind.LC_PAINT_KIND_CONIC_GRADIENT.value;
      desc.values[0] = gradient.center.x;
      desc.values[1] = gradient.center.y;
      desc.values[2] = gradient.angle;
  }

  desc.extend_mode = switch (gradient.extendMode) {
    GradientExtendMode.pad => bindings.LcExtendMode.LC_EXTEND_MODE_PAD.value,
    GradientExtendMode.repeat =>
      bindings.LcExtendMode.LC_EXTEND_MODE_REPEAT.value,
    GradientExtendMode.reflect =>
      bindings.LcExtendMode.LC_EXTEND_MODE_REFLECT.value,
  };

  final stops = gradient.stops;
  final stopsBuffer = calloc<bindings.LcGradientStop>(stops.length);
  for (var i = 0; i < stops.length; i++) {
    stopsBuffer[i].offset = stops[i].offset;
    stopsBuffer[i].color_argb = stops[i].color.value;
  }
  ownedBuffers.add(stopsBuffer);

  desc.stops = stopsBuffer;
  desc.stop_count = stops.length;
}

/// Fills a native [bindings.LcLayerDesc]'s `path_commands`/`path_coords`
/// slots from a [LayerPath] — one command byte per [PathCommand], and its
/// points flattened into a parallel `x, y` array (see [LcPathCommand] in
/// `scene_desc.h` for how many points each command consumes).
///
/// Both arrays are copied into native buffers appended to [ownedBuffers]
/// (option (b): pointer + count, same ownership pattern as [ImageLayer]'s
/// encoded bytes and a gradient's stops above), since a path may carry an
/// arbitrary number of commands/points.
void _fillPathGeometry(
  bindings.LcLayerDesc desc,
  LayerPath path,
  List<Pointer> ownedBuffers,
) {
  final commandBytes = <int>[];
  final coords = <double>[];

  void addPoint(Point2D point) {
    coords.add(point.x);
    coords.add(point.y);
  }

  for (final command in path.commands) {
    switch (command) {
      case MoveTo(:final point):
        commandBytes.add(bindings.LcPathCommand.LC_PATH_COMMAND_MOVE_TO.value);
        addPoint(point);
      case LineTo(:final point):
        commandBytes.add(bindings.LcPathCommand.LC_PATH_COMMAND_LINE_TO.value);
        addPoint(point);
      case QuadraticBezierTo(:final control, :final point):
        commandBytes.add(bindings.LcPathCommand.LC_PATH_COMMAND_QUAD_TO.value);
        addPoint(control);
        addPoint(point);
      case CubicBezierTo(:final control1, :final control2, :final point):
        commandBytes.add(bindings.LcPathCommand.LC_PATH_COMMAND_CUBIC_TO.value);
        addPoint(control1);
        addPoint(control2);
        addPoint(point);
      case ArcTo(
        :final radiusX,
        :final radiusY,
        :final xAxisRotation,
        :final largeArc,
        :final sweep,
        :final point,
      ):
        commandBytes.add(bindings.LcPathCommand.LC_PATH_COMMAND_ARC_TO.value);
        coords.add(radiusX);
        coords.add(radiusY);
        coords.add(xAxisRotation);
        coords.add(largeArc ? 1.0 : 0.0);
        coords.add(sweep ? 1.0 : 0.0);
        addPoint(point);
      case ClosePath():
        commandBytes.add(bindings.LcPathCommand.LC_PATH_COMMAND_CLOSE.value);
    }
  }

  final commandsBuffer = calloc<Uint8>(commandBytes.length);
  commandsBuffer.asTypedList(commandBytes.length).setAll(0, commandBytes);
  ownedBuffers.add(commandsBuffer);

  final coordsBuffer = calloc<Double>(coords.length);
  coordsBuffer.asTypedList(coords.length).setAll(0, coords);
  ownedBuffers.add(coordsBuffer);

  desc.path_commands = commandsBuffer;
  desc.path_command_count = commandBytes.length;
  desc.path_coords = coordsBuffer;
  desc.path_coord_count = coords.length;
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
