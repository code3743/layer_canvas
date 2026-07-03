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
} LcLayerKind;

// Maximum size, in UTF-8 bytes, of a TextLayer's `text` field below. Text
// longer than this is truncated on the Dart side before it ever crosses the
// FFI boundary — see lib/src/ffi/layer_descriptor.dart.
#define LC_TEXT_MAX_BYTES 256

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

  int32_t kind;  // LcLayerKind. Backends must ignore kinds they don't
                 // recognize instead of failing the whole render.

  // RectangleLayer-specific fields (meaningful only when
  // kind == LC_LAYER_KIND_RECTANGLE).
  uint32_t rect_color_argb;
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
} LcLayerDesc;

#endif  // LAYER_CANVAS_SCENE_DESC_H_
