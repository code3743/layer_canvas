#include "blend2d_backend.h"

#include <blend2d/blend2d.h>

#include <cstdlib>
#include <cstring>

#include <cstdio>
#include <dlfcn.h>
typedef int (*LcAndroidLogPrintFunc)(int, const char*, const char*, ...);
static LcAndroidLogPrintFunc lc_get_android_log_print() {
  static LcAndroidLogPrintFunc fn = reinterpret_cast<LcAndroidLogPrintFunc>(
      dlsym(RTLD_DEFAULT, "__android_log_print"));
  return fn;
}
#define LC_LOG(msg) \
  do {              \
    LcAndroidLogPrintFunc log_fn = lc_get_android_log_print(); \
    if (log_fn) log_fn(6, "LC_TRACE", "%s", msg); \
    fprintf(stderr, "LC_TRACE: %s\n", msg); \
    fflush(stderr); \
  } while (0)

namespace {

// Owns the one piece of Blend2D state a canvas needs. Kept separate from
// the engine-facing LcImage (engine.cpp) so the backend interface never
// leaks a Blend2D type across the vtable boundary.
struct Blend2DImage {
  BLImage image;
};

LcBackendImage* Create(int32_t width, int32_t height) {
  LC_LOG("Create: entered");
  LC_LOG("Create: calling bl_runtime_init manually");
  bl_runtime_init();
  LC_LOG("Create: bl_runtime_init returned");
  auto* wrapper = new Blend2DImage();
  LC_LOG("Create: allocated wrapper, calling BLImage::create");
  BLResult result = wrapper->image.create(width, height, BL_FORMAT_PRGB32);
  LC_LOG("Create: BLImage::create returned");
  if (result != BL_SUCCESS) {
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

// Rectangle, stroke or fill styles a Paint can request (mirrors
// lib/src/model/paint.dart's PaintStyle).
constexpr int32_t kPaintStyleFill = 0;
constexpr int32_t kPaintStyleStroke = 1;
constexpr int32_t kPaintStyleFillAndStroke = 2;

void RenderRectangle(BLContext& ctx, const LcLayerDesc& layer) {
  // Pivot (rotate/scale) around the layer's anchor point, expressed as a
  // fraction of its own size - same semantics as LayerTransform.anchor in
  // lib/src/model/transform.dart.
  ctx.save();
  ctx.translate(layer.pos_x, layer.pos_y);
  ctx.translate(layer.anchor_x * layer.width, layer.anchor_y * layer.height);
  ctx.rotate(layer.rotation);
  ctx.scale(layer.scale_x, layer.scale_y);
  ctx.translate(-layer.anchor_x * layer.width, -layer.anchor_y * layer.height);
  ctx.set_global_alpha(layer.opacity);

  BLRoundRect shape(0, 0, layer.width, layer.height,
                     layer.rect_corner_radius);
  BLRgba32 color(layer.rect_color_argb);

  if (layer.rect_paint_style == kPaintStyleFill ||
      layer.rect_paint_style == kPaintStyleFillAndStroke) {
    ctx.fill_round_rect(shape, color);
  }
  if (layer.rect_paint_style == kPaintStyleStroke ||
      layer.rect_paint_style == kPaintStyleFillAndStroke) {
    ctx.set_stroke_width(layer.rect_stroke_width);
    ctx.stroke_round_rect(shape, color);
  }

  ctx.restore();
}

int32_t RenderLayers(LcBackendImage* image, const LcLayerDesc* layers,
                      int32_t layer_count) {
  auto* wrapper = reinterpret_cast<Blend2DImage*>(image);
  BLContext ctx(wrapper->image);

  // A freshly created BLImage's pixel buffer is not zero-initialized, so
  // without this the canvas starts out as whatever garbage its backing
  // memory happened to hold.
  ctx.clear_all();

  for (int32_t i = 0; i < layer_count; ++i) {
    const LcLayerDesc& layer = layers[i];
    switch (layer.kind) {
      case LC_LAYER_KIND_RECTANGLE:
        RenderRectangle(ctx, layer);
        break;
      default:
        // Unknown/unsupported kinds are skipped rather than failing the
        // whole render - this is what lets new layer kinds be added later
        // without breaking scenes that already render fine today.
        break;
    }
  }

  ctx.end();
  return 0;
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
      RenderLayers,
      EncodePng,
  };
  return &backend;
}
