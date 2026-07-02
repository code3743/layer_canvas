#include "engine.h"

#include <cstdlib>

#include "backend/backend.h"
#include "backend/blend2d/blend2d_backend.h"

namespace {

// The single place that selects which graphics backend is active. Swapping
// to a different backend (Skia, Cairo, libvips...) later means
// implementing LcGraphicsBackend and changing this one line — nothing else
// here, in Dart, or in engine.h changes.
const LcGraphicsBackend* ActiveBackend() { return lc_backend_blend2d(); }

}  // namespace

struct LcImage {
  LcBackendImage* backend_image;
};

extern "C" LcImage* lc_image_create(int32_t width, int32_t height) {
  if (width <= 0 || height <= 0) return nullptr;

  LcBackendImage* backend_image = ActiveBackend()->create(width, height);
  if (backend_image == nullptr) return nullptr;

  return new LcImage{backend_image};
}

extern "C" void lc_image_destroy(LcImage* image) {
  if (image == nullptr) return;
  ActiveBackend()->destroy(image->backend_image);
  delete image;
}

extern "C" void lc_image_clear(LcImage* image, uint32_t argb) {
  if (image == nullptr) return;
  ActiveBackend()->clear(image->backend_image, argb);
}

extern "C" int32_t lc_image_encode_png(LcImage* image, uint8_t** out_data,
                                        size_t* out_len) {
  if (image == nullptr) return -1;
  return ActiveBackend()->encode_png(image->backend_image, out_data, out_len);
}

extern "C" void lc_buffer_free(uint8_t* data) { std::free(data); }
