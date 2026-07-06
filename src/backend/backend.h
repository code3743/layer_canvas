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

  // Encodes the canvas as `format` (LcOutputFormat) into a freshly malloc'd
  // buffer. Returns 0 on success, non-zero on failure (including an
  // unsupported/unencodable format). Ownership of `*out_data` transfers to
  // the caller, who must release it with `free()`.
  int32_t (*encode_image)(LcBackendImage* image, int32_t format,
                           uint8_t** out_data, size_t* out_len);

  // Registers `size` bytes of font data (TTF/OTF) under `name`+`weight`
  // (100..900, CSS/OpenType scale) so any TextLayer whose fontFamily
  // matches `name` renders with whichever registered weight under that
  // name is closest to its own fontWeight. A single `name` may have
  // several weights registered at once. Registration is global to the
  // backend (not per-image) and persists until explicitly unregistered.
  // The implementation must copy or otherwise retain `data` itself — the
  // caller may free it as soon as this call returns. Returns 0 on success,
  // non-zero on failure (e.g. malformed font data).
  int32_t (*register_font)(const char* name, int32_t weight,
                            const uint8_t* data, size_t size);

  // Removes the font previously registered under `name`+`weight`. Returns 0
  // if found and removed, 1 if no font was registered under that exact
  // name+weight pair (not treated as an error), and a negative value for
  // invalid input. Other weights registered under the same `name` are
  // unaffected.
  int32_t (*unregister_font)(const char* name, int32_t weight);
} LcGraphicsBackend;

#endif  // LAYER_CANVAS_BACKEND_BACKEND_H_
