#ifndef LAYER_CANVAS_BACKEND_BACKEND_H_
#define LAYER_CANVAS_BACKEND_BACKEND_H_

#include <stddef.h>
#include <stdint.h>

#include "../scene_desc.h"

// Opaque, backend-owned handle for a single canvas. Only the backend
// implementation that created it knows its real layout.
typedef struct LcBackendImage LcBackendImage;

// A graphics backend is a fixed table of function pointers. This is the
// only seam between the engine core (engine.cpp) and a specific rendering
// library (Blend2D today; Skia/Cairo/libvips could implement this same
// table later). The engine core never links against a backend's real API
// directly, so swapping backends never touches engine.cpp or the public
// FFI surface in engine.h.
typedef struct {
  const char* name;

  LcBackendImage* (*create)(int32_t width, int32_t height);
  void (*destroy)(LcBackendImage* image);

  // Fills the whole canvas with a solid color, packed as 0xAARRGGBB.
  void (*clear)(LcBackendImage* image, uint32_t argb);

  // Composites `layers` onto the canvas, in array order (the caller has
  // already resolved stacking order and dropped invisible layers - see
  // scene_desc.h). Layer kinds the backend doesn't recognize must be
  // skipped, not treated as an error. Returns 0 on success.
  int32_t (*render_layers)(LcBackendImage* image, const LcLayerDesc* layers,
                            int32_t layer_count);

  // Encodes the canvas as PNG into a freshly malloc'd buffer. Returns 0 on
  // success, non-zero on failure. Ownership of `*out_data` transfers to the
  // caller, who must release it with `free()`.
  int32_t (*encode_png)(LcBackendImage* image, uint8_t** out_data,
                         size_t* out_len);
} LcGraphicsBackend;

#endif  // LAYER_CANVAS_BACKEND_BACKEND_H_
