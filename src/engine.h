#ifndef LAYER_CANVAS_ENGINE_H_
#define LAYER_CANVAS_ENGINE_H_

#include <stddef.h>
#include <stdint.h>

#include "scene_desc.h"

#if _WIN32
#define LC_EXPORT __declspec(dllexport)
#else
#define LC_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle to a single canvas. Every handle returned by lc_image_create
// must be released with lc_image_destroy.
typedef struct LcImage LcImage;

// Creates a blank, fully transparent canvas of `width` x `height` pixels.
// Returns NULL if `width`/`height` are not positive or on allocation failure.
LC_EXPORT LcImage* lc_image_create(int32_t width, int32_t height);

// Releases a canvas created by lc_image_create. Passing NULL is a no-op.
LC_EXPORT void lc_image_destroy(LcImage* image);

// Fills the whole canvas with a solid ARGB color (0xAARRGGBB).
LC_EXPORT void lc_image_clear(LcImage* image, uint32_t argb);

// Encodes the canvas as PNG into a newly allocated buffer, written to
// `*out_data`/`*out_len`. Returns 0 on success, non-zero on failure. On
// success, the caller must release the buffer with lc_buffer_free.
LC_EXPORT int32_t lc_image_encode_png(LcImage* image, uint8_t** out_data,
                                      size_t* out_len);

// Releases a buffer produced by lc_image_encode_png. Passing NULL is a
// no-op.
LC_EXPORT void lc_buffer_free(uint8_t* data);

// Composes a whole scene in one call: creates a `width` x `height` canvas,
// paints `layers` onto it in array order, and encodes the result as PNG
// into `*out_data`/`*out_len`. Returns 0 on success. On success, the
// caller must release the buffer with lc_buffer_free.
//
// The caller (the Dart side) is responsible for resolving stacking order
// (Layer.zIndex) into `layers`' array order and dropping invisible layers
// before calling this - see scene_desc.h. `layers` may be NULL only if
// `layer_count` is 0.
LC_EXPORT int32_t lc_render_scene(int32_t width, int32_t height,
                                  const LcLayerDesc* layers,
                                  int32_t layer_count, uint8_t** out_data,
                                  size_t* out_len);

#ifdef __cplusplus
}
#endif

#endif  // LAYER_CANVAS_ENGINE_H_
