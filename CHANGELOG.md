## Unreleased

* `RectangleLayer` — fill/stroke/fill-and-stroke, corner radius, full 2D
  transform (position, rotation, scale, anchor).
* `TextLayer` — native text rendering with an embedded Roboto (regular and
  bold); custom fonts can be registered globally via `FontRegistry` and
  referenced by `fontFamily`. The embedded font (~1.4 MB) can be dropped
  from the compiled library with `hooks.user_defines.layer_canvas.embed_default_font: false`.
* Fixed an Android `dlopen` deadlock caused by a `thread_local` segment in
  a vendored dependency, and hardened the x86/x86_64 SIMD build to match
  the Android NDK's baseline compiler defines.

## 0.0.1

Initial package scaffold (from the `package:ffi` native-assets template)
with `RectangleLayer` rendering end to end through Blend2D.
