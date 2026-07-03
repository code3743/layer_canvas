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
} LcLayerKind;

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
} LcLayerDesc;

#endif  // LAYER_CANVAS_SCENE_DESC_H_
