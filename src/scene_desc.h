#ifndef LAYER_CANVAS_SCENE_DESC_H_
#define LAYER_CANVAS_SCENE_DESC_H_

#include <stdint.h>

// Wire format for a single layer, shared between the public FFI surface
// (engine.h) and every backend implementation (backend.h). This is *our*
// generic scene description, not tied to any graphics library.
//
// The Dart side is responsible for:
//  - resolving stacking order (Layer.zIndex) into plain array order,
//  - dropping invisible layers,
//  - flattening the common Layer.transform/size/opacity into these fields.
// A backend only ever sees a flat array of these and never needs to know
// about Scene, Layer, or Dart at all.
//
// Adding a new renderable layer kind means adding a value to LcLayerKind,
// adding its dedicated fields below, and teaching a backend's render_layers
// to handle the new kind - engine.h's function signature never changes.
typedef enum {
  LC_LAYER_KIND_UNKNOWN = 0,
  LC_LAYER_KIND_RECTANGLE = 1,
  LC_LAYER_KIND_TEXT = 2,
  LC_LAYER_KIND_IMAGE = 3,
  LC_LAYER_KIND_PATH = 4,
} LcLayerKind;

// Encoded output formats a rendered canvas can be requested as (mirrors
// lib/src/renderer/renderer.dart's OutputFormat, same declared order).
// Deliberately no JPEG: this vendored Blend2D's JPEG codec only implements
// decoding - encode_create_encoder returns BL_ERROR_IMAGE_ENCODER_NOT_PROVIDED
// (see codec/jpegcodec.cpp), so it's not a usable output format today.
typedef enum {
  LC_OUTPUT_FORMAT_PNG = 0,
  LC_OUTPUT_FORMAT_BMP = 1,
  LC_OUTPUT_FORMAT_QOI = 2,
} LcOutputFormat;

// Paint (fill/stroke source) kinds a shape can request. Kept as its own
// type - decoupled from any specific shape's fields below - so future
// geometry kinds (circles, paths...) can reuse LcPaintDesc verbatim instead
// of growing per-shape color fields, and so this enum can later grow e.g.
// LC_PAINT_KIND_PATTERN without touching existing call sites.
typedef enum {
  LC_PAINT_KIND_SOLID = 0,
  LC_PAINT_KIND_LINEAR_GRADIENT = 1,
  LC_PAINT_KIND_RADIAL_GRADIENT = 2,
  LC_PAINT_KIND_CONIC_GRADIENT = 3,
} LcPaintKind;

// How a gradient behaves outside its defined 0..1 offset range. Only
// meaningful when LcPaintDesc.kind is one of the *_GRADIENT kinds above.
typedef enum {
  LC_EXTEND_MODE_PAD = 0,
  LC_EXTEND_MODE_REPEAT = 1,
  LC_EXTEND_MODE_REFLECT = 2,
} LcExtendMode;

// Shape of a stroke's open ends (mirrors lib/src/model/paint.dart's
// StrokeCap, same declared order). Only meaningful for a stroked paint.
typedef enum {
  LC_STROKE_CAP_BUTT = 0,
  LC_STROKE_CAP_ROUND = 1,
  LC_STROKE_CAP_SQUARE = 2,
} LcStrokeCap;

// Shape drawn where two stroked segments meet (mirrors
// lib/src/model/paint.dart's StrokeJoin, same declared order). Only
// meaningful for a stroked paint.
typedef enum {
  LC_STROKE_JOIN_MITER = 0,
  LC_STROKE_JOIN_ROUND = 1,
  LC_STROKE_JOIN_BEVEL = 2,
} LcStrokeJoin;

// A single color stop within a gradient's ramp. `offset` is 0..1 along the
// gradient (mirrors lib/src/model/gradient.dart's GradientStop).
typedef struct {
  double offset;
  uint32_t color_argb;
} LcGradientStop;

// Describes what to paint a shape's fill/stroke with - a solid color or a
// gradient - independent of the shape's own geometry (mirrors
// lib/src/model/paint.dart's LayerPaint/Gradient split). Embedded by value
// inside a shape's fields below (e.g. LcLayerDesc.rect_paint).
typedef struct {
  int32_t kind;  // LcPaintKind

  uint32_t solid_color_argb;  // meaningful when kind == LC_PAINT_KIND_SOLID.

  int32_t extend_mode;  // LcExtendMode; meaningful for gradient kinds only.

  // Gradient geometry, fractional (0..1) relative to the painted shape's
  // own width/height - meaning depends on `kind`:
  //   LINEAR_GRADIENT: x0, y0, x1, y1   (start point, end point)
  //   RADIAL_GRADIENT: cx, cy, radius   (center point, radius; values[3]
  //                                      unused)
  //   CONIC_GRADIENT:  cx, cy, angle    (center point, start angle in
  //                                      radians; values[3] unused)
  double values[4];

  // Gradient stops - option (b): pointer + count, same ownership pattern as
  // LcLayerDesc.image_data/image_data_size below. Owned by the caller for
  // the duration of a single lc_render_scene call only; meaningful for
  // gradient kinds only (NULL/0 when kind == LC_PAINT_KIND_SOLID).
  const LcGradientStop* stops;
  int32_t stop_count;

  // Stroke styling - meaningful only when the shape's paint style is
  // stroke or fillAndStroke (mirrors lib/src/model/paint.dart's LayerPaint
  // stroke fields). Kept on LcPaintDesc rather than duplicated per shape
  // kind, same rationale as this struct's own doc comment above.
  //
  // Deliberately no dash_array/dash_offset here: Blend2D's stroker accepts
  // a dash pattern but never actually applies it when generating stroke
  // geometry (https://github.com/blend2d/blend2d/issues/48, open since
  // 2019 - confirmed against this vendored copy by grepping
  // core/pathstroke.cpp for "dash": zero matches). Dashing is instead
  // resolved into plain MoveTo/LineTo geometry on the Dart side before it
  // ever crosses the FFI boundary - see
  // lib/src/renderer/path_dasher.dart - so a dashed PathLayer arrives here
  // as an already-dashed path with a perfectly ordinary solid stroke.
  int32_t stroke_cap;   // LcStrokeCap
  int32_t stroke_join;  // LcStrokeJoin
  double stroke_miter_limit;
} LcPaintDesc;

// A single step of a PathLayer's geometry (mirrors lib/src/model/path.dart's
// PathCommand). Each command consumes a fixed number of doubles from the
// parallel LcLayerDesc.path_coords array below:
//   MOVE_TO/LINE_TO: 1 point (2 doubles: x, y)
//   QUAD_TO:         2 points (4 doubles: control, end)
//   CUBIC_TO:        3 points (6 doubles: control1, control2, end)
//   ARC_TO:          7 doubles: rx, ry, x_axis_rotation (radians),
//                    large_arc (0.0/1.0), sweep (0.0/1.0), end x, end y -
//                    same endpoint parameterization as SVG's `A`/`a` path
//                    command. The flags are packed as doubles (rather than
//                    giving ARC_TO a different stride/type in path_coords)
//                    so every command can be walked the same way: read N
//                    doubles, where N depends only on the command byte.
//   CLOSE:           0 doubles.
typedef enum {
  LC_PATH_COMMAND_MOVE_TO = 0,
  LC_PATH_COMMAND_LINE_TO = 1,
  LC_PATH_COMMAND_QUAD_TO = 2,
  LC_PATH_COMMAND_CUBIC_TO = 3,
  LC_PATH_COMMAND_CLOSE = 4,
  LC_PATH_COMMAND_ARC_TO = 5,
} LcPathCommand;

// How overlapping/self-intersecting regions of a PathLayer are filled
// (mirrors lib/src/model/path.dart's FillRule). Only meaningful for fills;
// ignored for a stroke-only paint.
typedef enum {
  LC_FILL_RULE_NON_ZERO = 0,
  LC_FILL_RULE_EVEN_ODD = 1,
} LcFillRule;

// Maximum size, in UTF-8 bytes, of a TextLayer's `text` field below. Text
// longer than this is truncated on the Dart side before it ever crosses the
// FFI boundary — see lib/src/ffi/layer_descriptor.dart. 1024 (rather than a
// smaller cap) leaves enough room for a wrapped multi-line paragraph, not
// just a short label.
#define LC_TEXT_MAX_BYTES 1024

// Maximum size, in UTF-8 bytes, of the `font_family` field below. Font
// family names are short identifiers (not display text), so this cap is
// much smaller than LC_TEXT_MAX_BYTES.
#define LC_FONT_FAMILY_MAX_BYTES 64

typedef struct {
  // Common properties, shared by every layer kind (mirrors lib/src/model/
  // layer.dart and transform.dart).
  double pos_x;
  double pos_y;
  double width;
  double height;
  double rotation;  // radians
  double scale_x;
  double scale_y;
  double anchor_x;  // fractional, 0..1 of width/height
  double anchor_y;
  double opacity;  // 0..1
  int32_t clip_to_bounds;  // 0/1 - mirrors Layer.clipToBounds. Clips this
                           // layer's own painted content to 0,0..width,height
                           // in its own local (post-transform) space.

  int32_t kind;  // LcLayerKind. Backends must ignore kinds they don't
                 // recognize instead of failing the whole render.

  // RectangleLayer-specific fields (meaningful only when
  // kind == LC_LAYER_KIND_RECTANGLE).
  LcPaintDesc rect_paint;    // shared by both fill and stroke below.
  int32_t rect_paint_style;  // 0 = fill, 1 = stroke, 2 = fillAndStroke
  double rect_stroke_width;
  double rect_corner_radius;

  // TextLayer-specific fields (meaningful only when kind ==
  // LC_LAYER_KIND_TEXT). Mirrors lib/src/model/layers/text_layer.dart.
  uint8_t text[LC_TEXT_MAX_BYTES];  // UTF-8, NOT null-terminated.
  int32_t text_length;              // valid bytes in `text`, 0..LC_TEXT_MAX_BYTES.
  double text_font_size;
  uint32_t text_color_argb;
  int32_t text_align;   // 0 = left, 1 = center, 2 = right.
  int32_t text_weight;  // 100..900 (CSS/OpenType scale); backend buckets this
                         // to whichever embedded font face is closest.

  // Custom font lookup (meaningful only when kind == LC_LAYER_KIND_TEXT).
  // Names a font previously registered via lc_font_register (see
  // engine.h). When empty (font_family_length == 0) or not found in the
  // registry, the backend falls back to its built-in embedded font,
  // bucketed by text_weight.
  uint8_t font_family[LC_FONT_FAMILY_MAX_BYTES];  // UTF-8, NOT null-terminated.
  int32_t font_family_length;                      // valid bytes in `font_family`.

  // ImageLayer-specific fields (meaningful only when kind ==
  // LC_LAYER_KIND_IMAGE). Mirrors lib/src/model/layers/image_layer.dart.
  //
  // `image_data` points to `image_data_size` bytes of *encoded* image data
  // (PNG/JPEG/BMP/QOI - detected automatically by Blend2D). Unlike `text`
  // and `font_family` above, this isn't embedded inline: images range from
  // a few KB to several MB, far past a fixed-size buffer. The pointer is
  // owned by the caller for the duration of a single lc_render_scene call
  // only; the backend must not retain it afterward.
  const uint8_t* image_data;
  int32_t image_data_size;
  int32_t image_fit;  // 0 = fill, 1 = contain, 2 = cover, 3 = none.

  // PathLayer-specific fields (meaningful only when kind ==
  // LC_LAYER_KIND_PATH). Mirrors lib/src/model/layers/path_layer.dart.
  //
  // Unlike rect_paint's gradient geometry (fractional, relative to
  // width/height), path_coords below are absolute, in this layer's own
  // local space - the same origin (0,0) RectangleLayer's own geometry
  // uses. path_paint is still reused verbatim from LcPaintDesc: a
  // gradient's own geometry inside it stays fractional relative to
  // width/height regardless of what shape it's painting.
  LcPaintDesc path_paint;
  int32_t path_paint_style;  // 0 = fill, 1 = stroke, 2 = fillAndStroke
  double path_stroke_width;
  int32_t path_fill_rule;  // LcFillRule

  // Path geometry - option (b): pointer + count, same ownership pattern as
  // image_data/image_data_size and LcPaintDesc.stops above. Owned by the
  // caller for the duration of a single lc_render_scene call only.
  const uint8_t* path_commands;  // one LcPathCommand byte per entry.
  int32_t path_command_count;
  const double* path_coords;  // flattened x,y pairs, consumed in order as
                               // path_commands is walked (see LcPathCommand).
  int32_t path_coord_count;   // total doubles in path_coords.
} LcLayerDesc;

#endif  // LAYER_CANVAS_SCENE_DESC_H_
