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

// Extend modes a gradient LcPaintDesc can request (mirrors
// lib/src/model/gradient.dart's GradientExtendMode, in the same declared
// order).
constexpr BLExtendMode kGradientExtendModes[] = {
    BL_EXTEND_MODE_PAD, BL_EXTEND_MODE_REPEAT, BL_EXTEND_MODE_REFLECT};

// Stroke caps an LcPaintDesc can request (mirrors lib/src/model/paint.dart's
// StrokeCap, in the same declared order) - Blend2D's own BLStrokeCap values
// don't line up with this order (BL_STROKE_CAP_SQUARE is 1, not 2), so this
// can't be a straight cast.
constexpr BLStrokeCap kStrokeCaps[] = {
    BL_STROKE_CAP_BUTT, BL_STROKE_CAP_ROUND, BL_STROKE_CAP_SQUARE};

// Stroke joins an LcPaintDesc can request (mirrors lib/src/model/paint.dart's
// StrokeJoin, in the same declared order). StrokeJoin.miter maps to
// MITER_BEVEL - Blend2D's "clamp to bevel past the miter limit" variant,
// matching the SVG/CSS `miter` default.
constexpr BLStrokeJoin kStrokeJoins[] = {
    BL_STROKE_JOIN_MITER_BEVEL, BL_STROKE_JOIN_ROUND, BL_STROKE_JOIN_BEVEL};

// Applies `paint`'s stroke styling (cap/join/miter limit/dash pattern) onto
// `ctx`. Called right before a stroke_* call, alongside the existing
// set_stroke_width - geometric stroke properties only, independent of the
// fill/stroke source BuildPaintStyle resolves separately. Pure BLPath
// geometry (see core/pathstroke.cpp), so - unlike compositing operators -
// this works identically with or without the JIT pipeline.
void ApplyStrokeStyle(BLContext& ctx, const LcPaintDesc& paint) {
  const BLStrokeCap cap =
      (paint.stroke_cap >= 0 &&
       static_cast<size_t>(paint.stroke_cap) <
           (sizeof(kStrokeCaps) / sizeof(kStrokeCaps[0])))
          ? kStrokeCaps[paint.stroke_cap]
          : BL_STROKE_CAP_BUTT;
  ctx.set_stroke_caps(cap);

  const BLStrokeJoin join =
      (paint.stroke_join >= 0 &&
       static_cast<size_t>(paint.stroke_join) <
           (sizeof(kStrokeJoins) / sizeof(kStrokeJoins[0])))
          ? kStrokeJoins[paint.stroke_join]
          : BL_STROKE_JOIN_MITER_BEVEL;
  ctx.set_stroke_join(join);
  ctx.set_stroke_miter_limit(paint.stroke_miter_limit);
}

// Builds the fill/stroke style described by `paint` - a solid color or a
// gradient - as a BLVar so callers can pass it straight to
// fill_round_rect/stroke_round_rect regardless of which kind it is.
//
// Gradient geometry in `paint.values` is fractional (0..1), relative to the
// painted shape's own local box - denormalized here against `width`/
// `height`. Because this runs after RenderRectangle has already translated/
// rotated/scaled `ctx` into that same 0,0..width,height local space (see its
// pivot transform comment), the gradient inherits the shape's rotation and
// scale for free, with no extra transform math needed here.
BLVar BuildPaintStyle(const LcPaintDesc& paint, double width, double height) {
  if (paint.kind != LC_PAINT_KIND_LINEAR_GRADIENT &&
      paint.kind != LC_PAINT_KIND_RADIAL_GRADIENT &&
      paint.kind != LC_PAINT_KIND_CONIC_GRADIENT) {
    // Unknown kinds fall back to solid, same philosophy as an unrecognized
    // layer kind elsewhere in this backend - never fail the render.
    return BLVar(BLRgba32(paint.solid_color_argb));
  }

  const BLExtendMode extend_mode =
        (paint.extend_mode >= 0 &&
         static_cast<size_t>(paint.extend_mode) <
           (sizeof(kGradientExtendModes) / sizeof(kGradientExtendModes[0])))
          ? kGradientExtendModes[paint.extend_mode]
          : BL_EXTEND_MODE_PAD;

  BLGradient gradient;
  switch (paint.kind) {
    case LC_PAINT_KIND_LINEAR_GRADIENT: {
      const BLLinearGradientValues values(
          paint.values[0] * width, paint.values[1] * height,
          paint.values[2] * width, paint.values[3] * height);
      gradient = BLGradient(values, extend_mode);
      break;
    }
    case LC_PAINT_KIND_RADIAL_GRADIENT: {
      // No focal point support yet - focal defaults to the gradient center.
      const double cx = paint.values[0] * width;
      const double cy = paint.values[1] * height;
      const double r = paint.values[2] * width;
      const BLRadialGradientValues values(cx, cy, cx, cy, r);
      gradient = BLGradient(values, extend_mode);
      break;
    }
    default: {  // LC_PAINT_KIND_CONIC_GRADIENT
      const BLConicGradientValues values(
          paint.values[0] * width, paint.values[1] * height,
          paint.values[2]);
      gradient = BLGradient(values, extend_mode);
      break;
    }
  }

  // LcGradientStop isn't binary-compatible with BLGradientStop (argb32 vs.
  // rgba64), so stops are copied one at a time rather than assigned in bulk.
  // A null `stops` with a positive count means a malformed descriptor - treat
  // it as "no stops" rather than dereferencing null, same never-fail-the-
  // render philosophy as an unrecognized layer kind.
  if (paint.stops != nullptr) {
    for (int32_t i = 0; i < paint.stop_count; ++i) {
      gradient.add_stop(paint.stops[i].offset,
                         BLRgba32(paint.stops[i].color_argb));
    }
  }

  return BLVar(std::move(gradient));
}

// Applies the layer's common pivot transform and opacity onto `ctx`: pivot
// (rotate/scale) around the anchor point, expressed as a fraction of the
// layer's own size - same semantics as LayerTransform.anchor in
// lib/src/model/transform.dart. Every Render* function calls this right after
// ctx.save() so its fill/stroke/blit below runs in the layer's local
// 0,0..width,height space (which is also why BuildPaintStyle's fractional
// gradient geometry inherits the shape's rotation and scale for free).
void ApplyLayerTransform(BLContext& ctx, const LcLayerDesc& layer) {
  ctx.translate(layer.pos_x, layer.pos_y);
  ctx.translate(layer.anchor_x * layer.width, layer.anchor_y * layer.height);
  ctx.rotate(layer.rotation);
  ctx.scale(layer.scale_x, layer.scale_y);
  ctx.translate(-layer.anchor_x * layer.width, -layer.anchor_y * layer.height);
  ctx.set_global_alpha(layer.opacity);

  // Clips to this layer's own box, in the same local 0,0..width,height
  // space every Render* function paints in - moves/rotates/scales with the
  // layer exactly like its paint geometry does. Scoped to just this layer's
  // paint calls by the ctx.save()/restore() pair every Render* wraps this
  // function in.
  if (layer.clip_to_bounds != 0) {
    ctx.clip_to_rect(BLRect(0, 0, layer.width, layer.height));
  }
}

void RenderRectangle(BLContext& ctx, const LcLayerDesc& layer) {
  ctx.save();
  ApplyLayerTransform(ctx, layer);

  BLRoundRect shape(0, 0, layer.width, layer.height,
                     layer.rect_corner_radius);
  const BLVar style =
      BuildPaintStyle(layer.rect_paint, layer.width, layer.height);

  if (layer.rect_paint_style == kPaintStyleFill ||
      layer.rect_paint_style == kPaintStyleFillAndStroke) {
    ctx.fill_round_rect(shape, style);
  }
  if (layer.rect_paint_style == kPaintStyleStroke ||
      layer.rect_paint_style == kPaintStyleFillAndStroke) {
    ctx.set_stroke_width(layer.rect_stroke_width);
    ApplyStrokeStyle(ctx, layer.rect_paint);
    ctx.stroke_round_rect(shape, style);
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

// Splits `text` on ASCII spaces into words (runs of consecutive spaces
// collapse to a single separator, and leading/trailing spaces are dropped -
// same simplification most text renderers make for word-wrap purposes).
std::vector<std::string> SplitWords(const std::string& text) {
  std::vector<std::string> words;
  size_t start = 0;
  for (size_t i = 0; i <= text.size(); ++i) {
    if (i == text.size() || text[i] == ' ') {
      if (i > start) words.push_back(text.substr(start, i - start));
      start = i + 1;
    }
  }
  return words;
}

// Greedily packs `paragraph`'s words into lines no wider than `max_width`
// (measured with `font`), breaking only at word boundaries - a single word
// wider than `max_width` overflows on its own line rather than being force-
// broken mid-word (the same "overflow-wrap: normal" default most browsers
// use). Appends each resulting line to `out_lines`; `paragraph` itself is
// appended unsplit if it has no words (empty/all-spaces) or `max_width`
// doesn't leave room to usefully wrap.
void WrapParagraph(const std::string& paragraph, BLFont& font,
                    double max_width, std::vector<std::string>& out_lines) {
  const std::vector<std::string> words = SplitWords(paragraph);
  if (words.empty()) {
    out_lines.push_back(paragraph);
    return;
  }

  auto measure = [&](const std::string& s) -> double {
    BLGlyphBuffer gb;
    gb.set_utf8_text(s.data(), s.size());
    font.shape(gb);
    BLTextMetrics tm;
    font.get_text_metrics(gb, tm);
    return tm.advance.x;
  };

  std::string current_line;
  for (const std::string& word : words) {
    const std::string candidate =
        current_line.empty() ? word : current_line + " " + word;
    if (!current_line.empty() && measure(candidate) > max_width) {
      out_lines.push_back(current_line);
      current_line = word;
    } else {
      current_line = candidate;
    }
  }
  out_lines.push_back(current_line);
}

void RenderText(BLContext& ctx, const LcLayerDesc& layer) {
  ctx.save();
  ApplyLayerTransform(ctx, layer);

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
  const std::string full_text(text, text_size);

  // Split into paragraphs on explicit '\n' first - always, regardless of
  // whether `layer.width` is set - then word-wrap each paragraph to fit
  // `layer.width`, if given. A layer with no explicit width (intrinsic
  // sizing) has nothing to wrap against, so its paragraphs are each kept as
  // a single line, exactly like before this function supported '\n' at all.
  std::vector<std::string> paragraphs;
  {
    size_t start = 0;
    for (size_t i = 0; i <= full_text.size(); ++i) {
      if (i == full_text.size() || full_text[i] == '\n') {
        paragraphs.push_back(full_text.substr(start, i - start));
        start = i + 1;
      }
    }
  }

  std::vector<std::string> lines;
  for (const std::string& paragraph : paragraphs) {
    if (layer.width > 0.0 && !paragraph.empty()) {
      WrapParagraph(paragraph, font, layer.width, lines);
    } else {
      lines.push_back(paragraph);
    }
  }

  const BLFontMetrics& font_metrics = font.metrics();
  const double line_advance = font_metrics.ascent + font_metrics.descent;
  const double block_height = line_advance * static_cast<double>(lines.size());

  // The whole block is vertically centered within the box when a height is
  // given; otherwise its top sits at the layer's position - same rule the
  // single-line case used before, generalized to the block as a whole.
  const double block_top =
      layer.height > 0.0 ? (layer.height - block_height) / 2.0 : 0.0;

  double y = block_top + font_metrics.ascent;
  for (const std::string& line : lines) {
    BLGlyphBuffer glyph_buffer;
    glyph_buffer.set_utf8_text(line.data(), line.size());
    font.shape(glyph_buffer);

    double x = 0.0;
    if (layer.width > 0.0) {
      BLTextMetrics text_metrics;
      font.get_text_metrics(glyph_buffer, text_metrics);
      const double text_width = text_metrics.advance.x;
      if (layer.text_align == kTextAlignCenter) {
        x = (layer.width - text_width) / 2.0;
      } else if (layer.text_align == kTextAlignRight) {
        x = layer.width - text_width;
      }
    }

    ctx.fill_glyph_run(BLPoint(x, y), font, glyph_buffer.glyph_run(),
                        BLRgba32(layer.text_color_argb));
    y += line_advance;
  }

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

  ctx.save();
  ApplyLayerTransform(ctx, layer);

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

// PathLayer command bytes (mirrors lib/src/model/path.dart's PathCommand,
// scene_desc.h's LcPathCommand).
constexpr uint8_t kPathCommandMoveTo = 0;
constexpr uint8_t kPathCommandLineTo = 1;
constexpr uint8_t kPathCommandQuadTo = 2;
constexpr uint8_t kPathCommandCubicTo = 3;
constexpr uint8_t kPathCommandClose = 4;
constexpr uint8_t kPathCommandArcTo = 5;

// Fill rules a PathLayer can request (mirrors lib/src/model/path.dart's
// FillRule, in the same declared order).
constexpr BLFillRule kFillRules[] = {BL_FILL_RULE_NON_ZERO,
                                      BL_FILL_RULE_EVEN_ODD};

// Walks layer.path_commands/path_coords (see LcPathCommand in scene_desc.h
// for how many coordinates each command consumes) into a BLPath. An
// unrecognized command byte is skipped rather than failing the whole
// render, same philosophy as an unrecognized layer kind.
// Number of doubles each path command consumes from path_coords (see
// LcPathCommand in scene_desc.h). CLOSE and any unrecognized byte consume 0.
int32_t PathCommandCoordCount(uint8_t command) {
  switch (command) {
    case kPathCommandMoveTo:
    case kPathCommandLineTo:
      return 2;
    case kPathCommandQuadTo:
      return 4;
    case kPathCommandCubicTo:
      return 6;
    case kPathCommandArcTo:
      return 7;
    default:  // kPathCommandClose and unrecognized bytes.
      return 0;
  }
}

BLPath BuildPath(const LcLayerDesc& layer) {
  BLPath path;
  if (layer.path_commands == nullptr) return path;

  int32_t c = 0;  // index into layer.path_coords.
  for (int32_t i = 0; i < layer.path_command_count; ++i) {
    const uint8_t command = layer.path_commands[i];

    // Guard the FFI trust boundary: a command that would read past
    // path_coord_count means the descriptor's command/coord arrays are
    // desynchronized (a Dart-side bug or corrupt data). Stop walking rather
    // than read out of bounds - the partial path built so far still renders.
    if (c + PathCommandCoordCount(command) > layer.path_coord_count) break;

    switch (command) {
      case kPathCommandMoveTo:
        path.move_to(layer.path_coords[c], layer.path_coords[c + 1]);
        c += 2;
        break;
      case kPathCommandLineTo:
        path.line_to(layer.path_coords[c], layer.path_coords[c + 1]);
        c += 2;
        break;
      case kPathCommandQuadTo:
        path.quad_to(layer.path_coords[c], layer.path_coords[c + 1],
                      layer.path_coords[c + 2], layer.path_coords[c + 3]);
        c += 4;
        break;
      case kPathCommandCubicTo:
        path.cubic_to(layer.path_coords[c], layer.path_coords[c + 1],
                       layer.path_coords[c + 2], layer.path_coords[c + 3],
                       layer.path_coords[c + 4], layer.path_coords[c + 5]);
        c += 6;
        break;
      case kPathCommandArcTo: {
        // Same endpoint parameterization as SVG's `A`/`a` path command -
        // elliptic_arc_to() implements that exact spec algorithm, so no
        // conversion to Blend2D's own center-parameterized arc_to() is
        // needed here.
        const double rx = layer.path_coords[c];
        const double ry = layer.path_coords[c + 1];
        const double x_axis_rotation = layer.path_coords[c + 2];
        const bool large_arc = layer.path_coords[c + 3] != 0.0;
        const bool sweep = layer.path_coords[c + 4] != 0.0;
        const double x = layer.path_coords[c + 5];
        const double y = layer.path_coords[c + 6];
        path.elliptic_arc_to(rx, ry, x_axis_rotation, large_arc, sweep, x, y);
        c += 7;
        break;
      }
      case kPathCommandClose:
        path.close();
        break;
      default:
        break;
    }
  }
  return path;
}

void RenderPath(BLContext& ctx, const LcLayerDesc& layer) {
  ctx.save();
  ApplyLayerTransform(ctx, layer);

  const BLPath path = BuildPath(layer);
  const BLVar style =
      BuildPaintStyle(layer.path_paint, layer.width, layer.height);

    const BLFillRule fill_rule =
      (layer.path_fill_rule >= 0 &&
       static_cast<size_t>(layer.path_fill_rule) <
         (sizeof(kFillRules) / sizeof(kFillRules[0])))
        ? kFillRules[layer.path_fill_rule]
        : BL_FILL_RULE_NON_ZERO;

  if (layer.path_paint_style == kPaintStyleFill ||
      layer.path_paint_style == kPaintStyleFillAndStroke) {
    ctx.set_fill_rule(fill_rule);
    ctx.fill_path(path, style);
  }
  if (layer.path_paint_style == kPaintStyleStroke ||
      layer.path_paint_style == kPaintStyleFillAndStroke) {
    ctx.set_stroke_width(layer.path_stroke_width);
    ApplyStrokeStyle(ctx, layer.path_paint);
    ctx.stroke_path(path, style);
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
      case LC_LAYER_KIND_PATH:
        RenderPath(ctx, layer);
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

// Codec names Blend2D registers its built-in codecs under (mirrors
// LcOutputFormat's declared order) - see e.g. bmp_codec.impl->name.assign
// ("BMP") / qoi_codec.impl->name.assign("QOI") in the vendored codec
// sources. JPEG is deliberately absent - see LcOutputFormat's doc comment
// in scene_desc.h.
constexpr const char* kOutputFormatCodecNames[] = {"PNG", "BMP", "QOI"};

int32_t EncodeImage(LcBackendImage* image, int32_t format, uint8_t** out_data,
                     size_t* out_len) {
  if (image == nullptr || out_data == nullptr || out_len == nullptr) return -1;
  if (format < 0 ||
      static_cast<size_t>(format) >=
          (sizeof(kOutputFormatCodecNames) / sizeof(kOutputFormatCodecNames[0]))) {
    return 4;
  }
  auto* wrapper = reinterpret_cast<Blend2DImage*>(image);

  BLImageCodec codec;
  if (codec.find_by_name(kOutputFormatCodecNames[format]) != BL_SUCCESS) {
    return 1;
  }

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
      EncodeImage,
      RegisterFont,
      UnregisterFont,
  };
  return &backend;
}
