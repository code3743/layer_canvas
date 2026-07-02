#include "blend2d_backend.h"

#include <blend2d/blend2d.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <map>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
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
// the name TextLayer.fontFamily is matched against, then by weight
// (100..900, CSS/OpenType scale) - a single family name can have several
// weights registered at once (see ResolveFontFace's closest-weight lookup
// below). The inner map is a std::map (ordered by weight) rather than an
// unordered_map so that lookup can use lower_bound to find the nearest
// registered weight. This is the only piece of state in this backend that
// outlives a single render call, so it's guarded by a mutex —
// render_layers() itself never mutates it, only reads under lock (see
// ResolveFontFace), but registration can race against a concurrent render
// from another isolate sharing this native library.
std::mutex& FontRegistryMutex() {
  static std::mutex mutex;
  return mutex;
}

std::unordered_map<std::string, std::map<int32_t, BLFontFace>>&
FontRegistry() {
  static std::unordered_map<std::string, std::map<int32_t, BLFontFace>>
      registry;
  return registry;
}

// Returns the face in `weights` whose key is numerically closest to
// `target`, favoring the lighter of the two candidates on an exact tie.
// `weights` must not be empty.
const BLFontFace& FindClosestWeightFace(
    const std::map<int32_t, BLFontFace>& weights, int32_t target) {
  const auto at_or_above = weights.lower_bound(target);
  if (at_or_above == weights.begin()) return at_or_above->second;
  if (at_or_above == weights.end()) return std::prev(at_or_above)->second;

  const auto below = std::prev(at_or_above);
  const int32_t above_diff = at_or_above->first - target;
  const int32_t below_diff = target - below->first;
  return below_diff <= above_diff ? below->second : at_or_above->second;
}

int32_t RegisterFont(const char* name, int32_t weight, const uint8_t* data,
                      size_t size) {
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
  FontRegistry()[name][weight] = face;
  return 0;
}

int32_t UnregisterFont(const char* name, int32_t weight) {
  if (name == nullptr) return -1;
  std::lock_guard<std::mutex> lock(FontRegistryMutex());

  const auto it = FontRegistry().find(name);
  if (it == FontRegistry().end() || it->second.erase(weight) == 0) return 1;
  if (it->second.empty()) FontRegistry().erase(it);
  return 0;
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

// Horizontal text alignment values a TextLayer can request (mirrors
// lib/src/model/layers/text_layer.dart's TextAlignment).
constexpr int32_t kTextAlignLeft = 0;
constexpr int32_t kTextAlignCenter = 1;
constexpr int32_t kTextAlignRight = 2;

// Weights at or above this threshold render with the embedded bold face;
// everything else uses regular (mirrors lib/src/model/layers/text_layer.dart's
// TextWeight, which uses the same 100-900 CSS/OpenType scale).
constexpr int32_t kBoldWeightThreshold = 600;

// Looks up layer.font_family in the user font registry first - if that
// family has one or more weights registered, picks whichever is numerically
// closest to layer.text_weight (see FindClosestWeightFace). When
// LC_EMBED_DEFAULT_FONT is defined, falls back to one of the two embedded
// Roboto weights if no font_family is set, or if it doesn't match any
// registered family (e.g. a typo — rendering with the default is friendlier
// than dropping the layer's text entirely). Builds without the embedded
// font return an empty BLFontFace in that fallback case; RenderText treats
// an empty face as "nothing to draw" rather than failing the render.
// Returned by value: BLFontFace is a ref-counted handle, so copying it
// while holding the lock (rather than returning a reference into the map)
// is cheap and avoids racing a concurrent lc_font_register/unregister.
BLFontFace ResolveFontFace(const LcLayerDesc& layer) {
  if (layer.font_family_length > 0) {
    const std::string name(reinterpret_cast<const char*>(layer.font_family),
                            static_cast<size_t>(layer.font_family_length));
    std::lock_guard<std::mutex> lock(FontRegistryMutex());
    const auto it = FontRegistry().find(name);
    if (it != FontRegistry().end() && !it->second.empty()) {
      return FindClosestWeightFace(it->second, layer.text_weight);
    }
  }
#ifdef LC_EMBED_DEFAULT_FONT
  return layer.text_weight >= kBoldWeightThreshold ? BoldFace() : RegularFace();
#else
  return BLFontFace();
#endif
}

void RenderText(BLContext& ctx, const LcLayerDesc& layer) {
  // Same pivot transform as RenderRectangle - see the comment there.
  ctx.save();
  ctx.translate(layer.pos_x, layer.pos_y);
  ctx.translate(layer.anchor_x * layer.width, layer.anchor_y * layer.height);
  ctx.rotate(layer.rotation);
  ctx.scale(layer.scale_x, layer.scale_y);
  ctx.translate(-layer.anchor_x * layer.width, -layer.anchor_y * layer.height);
  ctx.set_global_alpha(layer.opacity);

  const BLFontFace face = ResolveFontFace(layer);
  BLFont font;
  if (font.create_from_face(face, static_cast<float>(layer.text_font_size)) !=
      BL_SUCCESS) {
    // No usable font - no embedded default in this build (see
    // LC_EMBED_DEFAULT_FONT) and font_family didn't match anything
    // registered via lc_font_register. Skip this layer's text rather than
    // fail the whole render.
    ctx.restore();
    return;
  }

  const char* text = reinterpret_cast<const char*>(layer.text);
  const size_t text_size = static_cast<size_t>(layer.text_length);

  // Shape once up front to measure the laid-out width for alignment, then
  // draw that same shaped buffer with fill_glyph_run below - fill_utf8_text
  // would reshape identical work internally.
  BLGlyphBuffer glyph_buffer;
  glyph_buffer.set_utf8_text(text, text_size);
  font.shape(glyph_buffer);

  BLTextMetrics text_metrics;
  font.get_text_metrics(glyph_buffer, text_metrics);

  double x = 0.0;
  if (layer.width > 0.0) {
    const double text_width = text_metrics.advance.x;
    if (layer.text_align == kTextAlignCenter) {
      x = (layer.width - text_width) / 2.0;
    } else if (layer.text_align == kTextAlignRight) {
      x = layer.width - text_width;
    }
  }

  // Vertically centered within the box when a height is given; otherwise
  // the text's top sits at the layer's position.
  const BLFontMetrics& font_metrics = font.metrics();
  const double y =
      layer.height > 0.0
          ? (layer.height - (font_metrics.ascent + font_metrics.descent)) /
                    2.0 +
                font_metrics.ascent
          : font_metrics.ascent;

  ctx.fill_glyph_run(BLPoint(x, y), font, glyph_buffer.glyph_run(),
                      BLRgba32(layer.text_color_argb));

  ctx.restore();
}

// ImageLayer.fit values (mirrors lib/src/model/layers/image_layer.dart's
// ImageFit, in the same declared order).
constexpr int32_t kImageFitFill = 0;
constexpr int32_t kImageFitContain = 1;
constexpr int32_t kImageFitCover = 2;
constexpr int32_t kImageFitNone = 3;

void RenderImage(BLContext& ctx, const LcLayerDesc& layer) {
  if (layer.image_data == nullptr || layer.image_data_size <= 0) return;

  BLImage image;
  if (image.read_from_data(layer.image_data,
                            static_cast<size_t>(layer.image_data_size)) !=
      BL_SUCCESS) {
    // Malformed/unsupported image bytes - skip this layer rather than fail
    // the whole render, same philosophy as an unrecognized layer kind.
    return;
  }

  // Same pivot transform as RenderRectangle/RenderText - see the comment
  // on RenderRectangle.
  ctx.save();
  ctx.translate(layer.pos_x, layer.pos_y);
  ctx.translate(layer.anchor_x * layer.width, layer.anchor_y * layer.height);
  ctx.rotate(layer.rotation);
  ctx.scale(layer.scale_x, layer.scale_y);
  ctx.translate(-layer.anchor_x * layer.width, -layer.anchor_y * layer.height);
  ctx.set_global_alpha(layer.opacity);

  // No explicit size means "intrinsic": draw at the decoded image's own
  // pixel dimensions (mirrors Layer.size's doc comment in layer.dart).
  const double dest_w = layer.width > 0.0 ? layer.width : image.width();
  const double dest_h = layer.height > 0.0 ? layer.height : image.height();
  const double img_w = image.width();
  const double img_h = image.height();

  switch (layer.image_fit) {
    case kImageFitContain: {
      const double scale = std::min(dest_w / img_w, dest_h / img_h);
      const double w = img_w * scale;
      const double h = img_h * scale;
      ctx.blit_image(
          BLRect((dest_w - w) / 2.0, (dest_h - h) / 2.0, w, h), image);
      break;
    }
    case kImageFitCover: {
      const double scale = std::max(dest_w / img_w, dest_h / img_h);
      const double crop_w = dest_w / scale;
      const double crop_h = dest_h / scale;
      // Round rather than truncate: truncation could drop up to a full pixel
      // of the source crop, nudging the cover framing off-center.
      const BLRectI src_area(
          static_cast<int>(std::lround((img_w - crop_w) / 2.0)),
          static_cast<int>(std::lround((img_h - crop_h) / 2.0)),
          static_cast<int>(std::lround(crop_w)),
          static_cast<int>(std::lround(crop_h)));
      ctx.blit_image(BLRect(0, 0, dest_w, dest_h), image, src_area);
      break;
    }
    case kImageFitNone: {
      if (layer.width > 0.0 && layer.height > 0.0) {
        ctx.clip_to_rect(BLRect(0, 0, dest_w, dest_h));
        ctx.blit_image(BLPoint(0, 0), image);
        ctx.restore_clipping();
      } else {
        ctx.blit_image(BLPoint(0, 0), image);
      }
      break;
    }
    default: {  // kImageFitFill
      ctx.blit_image(BLRect(0, 0, dest_w, dest_h), image);
      break;
    }
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
      case LC_LAYER_KIND_TEXT:
        RenderText(ctx, layer);
        break;
      case LC_LAYER_KIND_IMAGE:
        RenderImage(ctx, layer);
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
