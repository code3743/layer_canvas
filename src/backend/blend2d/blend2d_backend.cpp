#include "blend2d_backend.h"

#include <blend2d/blend2d.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

// LC_EMBED_DEFAULT_FONT is defined by hook/build.dart unless a consumer
// opts out via `hooks.user_defines.layer_canvas.embed_default_font: false`
// in their own pubspec.yaml. The embedded Roboto (regular + bold) adds
// roughly 1.4 MB to the compiled native library - most of it dead weight
// for an app that never uses TextLayer, or that always registers its own
// font via FontRegistry. Everything in this block, the base64 decoder and
// the two embedded faces, compiles away entirely when the define is unset.
#ifdef LC_EMBED_DEFAULT_FONT
#include "fonts/embedded_fonts.h"
#endif

namespace {

#ifdef LC_EMBED_DEFAULT_FONT
// Decodes a single base64 character to its 6-bit value, or -1 for anything
// that isn't part of the alphabet (padding '=' included) — the decoder below
// simply skips those.
int DecodeBase64Char(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

// Decodes a null-terminated base64 string (as produced by
// tool/generate_embedded_fonts.dart) into raw bytes.
std::vector<uint8_t> DecodeBase64(const char* data) {
  std::vector<uint8_t> out;
  out.reserve(std::strlen(data) / 4 * 3);

  uint32_t buffer = 0;
  int bits = 0;
  for (const char* p = data; *p != '\0'; ++p) {
    const int value = DecodeBase64Char(*p);
    if (value < 0) continue;
    buffer = (buffer << 6) | static_cast<uint32_t>(value);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push_back(static_cast<uint8_t>((buffer >> bits) & 0xFF));
    }
  }
  return out;
}

// The two embedded Roboto weights TextLayer renders with — see
// scene_desc.h's `text_weight` field. Each is decoded and turned into a
// BLFontFace exactly once (function-local statics), then reused for every
// TextLayer in every render for the lifetime of the process.
const BLFontFace& RegularFace() {
  static const BLFontFace face = [] {
    static const std::vector<uint8_t> bytes =
        DecodeBase64(kRobotoRegularTtfBase64);
    BLFontData font_data;
    font_data.create_from_data(bytes.data(), bytes.size());
    BLFontFace f;
    f.create_from_data(font_data, 0);
    return f;
  }();
  return face;
}

const BLFontFace& BoldFace() {
  static const BLFontFace face = [] {
    static const std::vector<uint8_t> bytes =
        DecodeBase64(kRobotoBoldTtfBase64);
    BLFontData font_data;
    font_data.create_from_data(bytes.data(), bytes.size());
    BLFontFace f;
    f.create_from_data(font_data, 0);
    return f;
  }();
  return face;
}
#endif  // LC_EMBED_DEFAULT_FONT

// User-registered fonts (lc_font_register / lc_font_unregister), keyed by
// the name TextLayer.fontFamily is matched against. This is the only piece
// of state in this backend that outlives a single render call, so it's
// guarded by a mutex — render_layers() itself never mutates it, only reads
// under lock (see ResolveFontFace), but registration can race against a
// concurrent render from another isolate sharing this native library.
std::mutex& FontRegistryMutex() {
  static std::mutex mutex;
  return mutex;
}

std::unordered_map<std::string, BLFontFace>& FontRegistry() {
  static std::unordered_map<std::string, BLFontFace> registry;
  return registry;
}

int32_t RegisterFont(const char* name, const uint8_t* data, size_t size) {
  if (name == nullptr || name[0] == '\0' || data == nullptr || size == 0) {
    return -1;
  }

  // Blend2D's create_from_data(ptr, size) overload does not copy - it just
  // stores the pointer, which would dangle the moment Dart frees `data`
  // after this call returns. Copying into a BLArray first means Blend2D
  // owns (ref-counted) storage that's independent of `data`.
  BLArray<uint8_t> owned;
  if (owned.append_data(data, size) != BL_SUCCESS) return -2;

  BLFontData font_data;
  if (font_data.create_from_data(owned) != BL_SUCCESS) return -3;

  BLFontFace face;
  if (face.create_from_data(font_data, 0) != BL_SUCCESS) return -4;

  std::lock_guard<std::mutex> lock(FontRegistryMutex());
  FontRegistry()[name] = face;
  return 0;
}

int32_t UnregisterFont(const char* name) {
  if (name == nullptr) return -1;
  std::lock_guard<std::mutex> lock(FontRegistryMutex());
  return FontRegistry().erase(name) > 0 ? 0 : 1;
}

// Owns the one piece of Blend2D state a canvas needs. Kept separate from
// the engine-facing LcImage (engine.cpp) so the backend interface never
// leaks a Blend2D type across the vtable boundary.
struct Blend2DImage {
  BLImage image;
};

LcBackendImage* Create(int32_t width, int32_t height) {
  auto* wrapper = new Blend2DImage();
  BLResult result = wrapper->image.create(width, height, BL_FORMAT_PRGB32);
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
  if (image == nullptr || out_data == nullptr || out_len == nullptr) return -1;
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
      RegisterFont,
      UnregisterFont,
  };
  return &backend;
}
