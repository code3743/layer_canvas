#include "blend2d_backend.h"

#include <blend2d/blend2d.h>

#include <cstdlib>
#include <cstring>

namespace {

// Owns the one piece of Blend2D state a canvas needs. Kept separate from
// the engine-facing LcImage (engine.cpp) so the backend interface never
// leaks a Blend2D type across the vtable boundary.
struct Blend2DImage {
  BLImage image;
};

LcBackendImage* Create(int32_t width, int32_t height) {
  auto* wrapper = new Blend2DImage();
  if (wrapper->image.create(width, height, BL_FORMAT_PRGB32) != BL_SUCCESS) {
    delete wrapper;
    return nullptr;
  }
  return reinterpret_cast<LcBackendImage*>(wrapper);
}

void Destroy(LcBackendImage* image) {
  delete reinterpret_cast<Blend2DImage*>(image);
}

void Clear(LcBackendImage* image, uint32_t argb) {
  auto* wrapper = reinterpret_cast<Blend2DImage*>(image);
  BLContext ctx(wrapper->image);
  ctx.clear_all();
  ctx.fill_all(BLRgba32(argb));
  ctx.end();
}

int32_t EncodePng(LcBackendImage* image, uint8_t** out_data, size_t* out_len) {
  auto* wrapper = reinterpret_cast<Blend2DImage*>(image);

  BLImageCodec codec;
  if (codec.find_by_name("PNG") != BL_SUCCESS) return 1;

  BLArray<uint8_t> encoded;
  if (wrapper->image.write_to_data(encoded, codec) != BL_SUCCESS) return 2;

  uint8_t* copy = static_cast<uint8_t*>(std::malloc(encoded.size()));
  if (copy == nullptr) return 3;
  std::memcpy(copy, encoded.data(), encoded.size());

  *out_data = copy;
  *out_len = encoded.size();
  return 0;
}

}  // namespace

extern "C" const LcGraphicsBackend* lc_backend_blend2d(void) {
  static const LcGraphicsBackend backend = {
      "blend2d",
      Create,
      Destroy,
      Clear,
      EncodePng,
  };
  return &backend;
}
