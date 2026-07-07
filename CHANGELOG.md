## 1.0.0

First stable release.

* **`Layer.clipToBounds`** — clips a layer's own painted content to its own
  `size` box, in its own local (post-transform) space, so the clip moves
  and rotates with the layer exactly like its paint geometry. Requires an
  explicit `size`; no effect on `Group`, which is expanded into its
  concrete descendants before reaching the native renderer, leaving no
  single composited surface to clip.
* **`TextLayer` word-wrap** — text always breaks on an explicit `\n`, and
  additionally word-wraps to fit `size`'s width when one is given, greedily
  and only at spaces (a single word wider than the box overflows on its
  own line rather than being split mid-word). The wrapped block is
  vertically centered within `size`'s height, same as a single line always
  was.

## 0.1.0-beta.6

* **JSON serialization** — every model type (`Scene`, all `Layer` subtypes,
  `LayerPaint`, `Gradient`, `LayerPath`, `LayerImageSource`, etc.) gains a
  `toJson()` and a matching `fromJson`/`Gradient.fromJson`-style
  constructor. `LayerRegistry.registerLayer`/`registerImageSource` let a
  custom `Layer`/`LayerImageSource` subclass round-trip through
  `Scene.toJson`/`Scene.fromJson` too, without changing this package.
* `LayerTransform` now has value equality (`operator ==`/`hashCode`),
  matching `Point2D`/`Size2D`/`Color32`.
* `TextWeight.fromValue(int)` — a new factory for constructing a weight
  outside the 7 named constants (previously impossible, since `TextWeight`'s
  constructor was private).

## 0.1.0-beta.5

* **Stroke cap/join/miter limit** — `LayerPaint.strokeCap` (`butt`/`round`/
  `square`), `strokeJoin` (`miter`/`round`/`bevel`), and `miterLimit` control
  how a stroke's open ends and corners are drawn, on both `RectangleLayer`
  and `PathLayer`.
* **Dash patterns** — `LayerPaint.dashArray`/`dashOffset` on `PathLayer`
  strokes (an odd-length array repeats, matching SVG/CSS). Resolved into
  plain path geometry on the Dart side rather than delegated to Blend2D,
  whose own dash support is a long-standing no-op
  ([blend2d/blend2d#48](https://github.com/blend2d/blend2d/issues/48));
  not currently supported on `RectangleLayer`, which has no path geometry
  of its own to dash.
* **`OutputFormat`** — `Renderer.render`/`renderToFile` take a `format`
  parameter (`png`, the default, `bmp`, or `qoi`) to encode as something
  other than PNG. No JPEG: this build's JPEG codec only decodes, it can't
  encode.

## 0.1.0-beta.4

* **`hitTestScene`** — given a `Scene` and a point (in its own logical
  pixel space), returns the topmost visible `Layer` whose bounding box
  contains it, or `null`. Built on the same `Group`/transform composition
  `flattenScene` already resolves internally for rendering, so a rotated,
  scaled, or nested-in-a-group layer's hit box moves exactly the way its
  paint geometry does. A bounding-box test against `Layer.size` (not the
  exact painted shape), and a layer with no explicit `size` (intrinsic
  sizing) never matches — see the doc comment for the precise contract.
  This is what lets a consumer (e.g. `layer_canvas_flutter`) offer tap
  handling without reimplementing this package's own transform math.

## 0.1.0-beta.3

New layer capabilities and SVG import.

* **Gradients** — `LinearGradient`, `RadialGradient`, `ConicGradient`; any
  `RectangleLayer` or `PathLayer` can be painted with a gradient instead of
  a solid color via `LayerPaint.gradient`.
* **`PathLayer`** — arbitrary vector geometry: lines, quadratic/cubic
  Bézier curves, arcs (SVG-compatible `ArcTo`), and closed subpaths, with
  `FillRule.nonZero`/`evenOdd`. `LayerPath.polygon`, `.polyline`, `.circle`,
  and `.ellipse` cover the common cases; `PathLayer.filled` is a solid-fill
  shortcut.
* **SVG import** — `SvgDocument.parse` reads shapes, gradients, and paths
  from an SVG string; `.toGroup()` turns the result into layers that
  compose into a `Scene` like any other layer.
* **Multi-weight fonts** — `FontRegistry.register`/`unregister` now take a
  `weight`, so a single family can have several weights registered at
  once; `TextLayer` renders with whichever registered weight is
  numerically closest to its own `fontWeight`.
* `RectangleLayer.filled` — a plain width/height/color constructor for the
  common solid-fill case, alongside the existing `PathLayer.filled`.

## 0.1.0-beta.2

Documentation-only release: updated README with Flutter integration
details and an architecture diagram, and excluded unnecessary
Blend2D submodule files from the published package via `.pubignore`.

## 0.1.0-beta.1

First functional beta. `RectangleLayer`, `TextLayer`, `ImageLayer`, and
`Group` all render natively; `Scene.background` composites a full-canvas
image underneath everything else.

* `RectangleLayer` — fill/stroke/fill-and-stroke, corner radius, full 2D
  transform (position, rotation, scale, anchor).
* `TextLayer` — native text rendering with an embedded Roboto (regular and
  bold); custom fonts can be registered globally via `FontRegistry` and
  referenced by `fontFamily`. The embedded font (~1.4 MB) can be dropped
  from the compiled library with `hooks.user_defines.layer_canvas.embed_default_font: false`.
* `ImageLayer` — decodes PNG/JPEG/BMP/QOI automatically; `fit` supports
  `fill`, `contain`, `cover`, and `none`.
* `Group` — nests arbitrarily; flattened into concrete layers by the
  renderer before crossing the FFI boundary, so the native engine has no
  concept of groups.
* `Scene.background` — an optional `LayerImageSource` painted before any
  layer, scaled to cover the whole canvas.
* Fixed an Android `dlopen` deadlock caused by a `thread_local` segment in
  a vendored dependency, and hardened the x86/x86_64 SIMD build to match
  the Android NDK's baseline compiler defines.

## 0.0.1

Initial package scaffold (from the `package:ffi` native-assets template)
with `RectangleLayer` rendering end to end through Blend2D.
