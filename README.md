# layer_canvas

A high-performance 2D compositing engine for Flutter and Dart, using
[Blend2D](https://blend2d.com) internally as its rasterization backend via
Dart FFI. Compose typed `Layer`s into a `Scene` and render to PNG at native
speed — on Android, iOS, macOS, Linux, and Windows.

This is an independent project built on top of Blend2D; it is not an
official Blend2D binding, wrapper, or port, and is not affiliated with or
endorsed by the Blend2D project.

## Features

- **Typed layer model** — `RectangleLayer`, `TextLayer`, `ImageLayer`, `Group`
- **Native Blend2D renderer** — compiled as a [Dart Native Asset][native_assets],
  no separate build step, no CMake invocation needed
- **Native text rendering** — `TextLayer` ships with an embedded Roboto
  (regular/bold), and apps can register their own fonts via `FontRegistry`
- **Pure Dart core** — no dependency on Flutter or `dart:ui`; the same
  `Scene`/`Renderer` API runs in a plain `dart run` script, a server, or a
  Flutter app
- **Full 2D transform** — position, rotation, scale, and configurable pivot
  anchor on every layer
- **Compositor semantics** — `zIndex`, `opacity`, `visible` respected on all
  layer types
- **No JIT / no AsmJit** — safe on W^X-constrained platforms (iOS App Store,
  Impeller on Android)
- **Extensible** — add new layer kinds by subclassing `Layer`; the engine core
  and `Scene` never change

## Platform support

| Platform | Architecture    | Status       |
|----------|-----------------|--------------|
| Android  | arm64-v8a       | ✅ Supported |
| Android  | x86\_64 (emulator) | ✅ Supported |
| iOS      | arm64           | ✅ Supported |
| macOS    | arm64 / x86\_64 | ✅ Supported |
| Linux    | x86\_64         | ✅ Supported |
| Windows  | x86\_64         | ✅ Supported |

## Getting started

Add to `pubspec.yaml`:

```yaml
dependencies:
  layer_canvas: ^0.0.1
```

No additional native build setup is required — the Blend2D library is compiled
and bundled automatically via Dart's Native Assets mechanism.

## Usage

### Basic render

```dart
import 'package:layer_canvas/layer_canvas.dart';

final scene = Scene(width: 800, height: 600);

scene.add(RectangleLayer(
  size: const Size2D(800, 600),
  paint: const LayerPaint(color: Color32.fromRGB(30, 30, 30)),
));

scene.add(RectangleLayer(
  transform: const LayerTransform(position: Point2D(100, 200)),
  size: const Size2D(200, 80),
  paint: const LayerPaint(
    color: Color32.fromARGB(200, 255, 255, 255),
    style: LayerPaintStyle.fillAndStroke,
    strokeWidth: 2,
  ),
  cornerRadius: 12,
));

final Uint8List png = await Renderer().render(scene);
// Use png as Image.memory(png) in Flutter, File.writeAsBytes(png), etc.
```

### Watermark overlay

```dart
final scene = Scene(width: 400, height: 300);

// Semi-transparent band at the bottom
scene.add(RectangleLayer(
  transform: const LayerTransform(position: Point2D(0, 240)),
  size: const Size2D(400, 60),
  paint: const LayerPaint(color: Color32(0xCC000000)), // 80 % black
));

// Rotated stamp at the center
scene.add(RectangleLayer(
  transform: LayerTransform(
    position: const Point2D(120, 130),
    rotation: -0.4, // ≈ -23°
  ),
  size: const Size2D(160, 40),
  paint: const LayerPaint(color: Color32(0x44FFFFFF)),
  cornerRadius: 6,
));

final png = await Renderer().render(scene);
```

### Images

```dart
final scene = Scene(width: 400, height: 300);

scene.add(ImageLayer(
  source: LayerImageSource.file('/path/to/photo.jpg'), // or .memory(bytes)
  size: const Size2D(400, 300),
  fit: ImageFit.cover,
));

final png = await Renderer().render(scene);
```

Blend2D decodes PNG/JPEG/BMP/QOI automatically (no format needs to be
specified). `fit` behaves like `BoxFit` in Flutter — `fill` stretches to
the given `size` ignoring aspect ratio, `contain` scales uniformly and
letterboxes, `cover` scales uniformly and crops, `none` draws at the
decoded image's natural pixel size. Without an explicit `size`, `none`'s
natural-size behavior is used regardless of `fit`.

For a full-canvas photo underneath everything else — the common case for a
watermark — `Scene.background` is shorter than an `ImageLayer` and always
covers the whole canvas:

```dart
final scene = Scene(
  width: 400,
  height: 300,
  background: LayerImageSource.file('/path/to/photo.jpg'),
);
```

### Text

```dart
final scene = Scene(width: 400, height: 120);

scene.add(TextLayer(
  text: '6.2442° N, 75.5812° W',
  transform: const LayerTransform(position: Point2D(16, 16)),
  size: const Size2D(368, 30),
  fontSize: 20,
  color: Color32.white,
  align: TextAlignment.left,
));

scene.add(TextLayer(
  text: 'MEDELLÍN, COLOMBIA',
  transform: const LayerTransform(position: Point2D(16, 56)),
  size: const Size2D(368, 30),
  fontSize: 16,
  color: Color32.fromRGB(255, 200, 0),
  align: TextAlignment.center,
  fontWeight: TextWeight.bold,
));

final png = await Renderer().render(scene);
```

`TextLayer` renders natively (no Flutter widgets involved) using an embedded
Roboto — `fontWeight` values `>= 600` pick the bold face, everything else
regular. Alignment is honored within `size`'s width; without an explicit
`size`, text is drawn from `transform.position` with no wrapping.

### Custom fonts

Register your own TTF/OTF bytes once (e.g. at app startup) and reference
them by name from any `TextLayer`:

```dart
final data = await File('assets/fonts/Brand-Regular.ttf').readAsBytes();
FontRegistry.register('Brand', data);

scene.add(TextLayer(
  text: 'On brand',
  fontFamily: 'Brand', // falls back to the embedded Roboto if unregistered
));
```

Registration is global to the process, not scoped to a `Scene` or
`Renderer` — call it once, use the name everywhere.

### Opting out of the embedded default font

`TextLayer` ships with an embedded Roboto (regular and bold) so it works
out of the box, at a cost of roughly 1.4 MB in the compiled native
library. Apps that never use `TextLayer`, or that always register their
own font via `FontRegistry`, can drop it by adding this to their own
`pubspec.yaml` (not this package's):

```yaml
hooks:
  user_defines:
    layer_canvas:
      embed_default_font: false
```

With this set, a `TextLayer` that doesn't match a font registered via
`FontRegistry` renders nothing for that layer — the rest of the scene
still renders normally — instead of falling back to Roboto.

### Groups

```dart
scene.add(Group(
  transform: const LayerTransform(position: Point2D(50, 400), rotation: 0.1),
  opacity: 0.9,
  children: [
    RectangleLayer(size: const Size2D(200, 60), paint: const LayerPaint(color: Color32(0xAA000000))),
    TextLayer(text: 'Grouped', transform: const LayerTransform(position: Point2D(12, 18)), color: Color32.white),
  ],
));
```

A `Group`'s `transform` and `opacity` apply to every child as one unit —
move, rotate, or fade the whole cluster without touching each child's own
values. Groups can nest arbitrarily and never reach the native engine: the
renderer flattens them into concrete layers first.

### Write to file

```dart
await Renderer().renderToFile(scene, '/tmp/output.png');
```

## API overview

### `Scene`

The root of a composition. Holds canvas dimensions and an ordered list of
layers.

| Member | Description |
|---|---|
| `Scene({width, height, background})` | Creates a canvas. Both dimensions must be positive. |
| `add(Layer)` / `addAll(Iterable<Layer>)` | Appends layers in insertion order. |
| `remove(String id)` | Removes the layer with the given id. Returns `false` if not found. |
| `clear()` | Removes all layers. |
| `layers` | Unmodifiable view of the current layers. |
| `background` | Optional `LayerImageSource` painted before any layer, scaled to cover the whole canvas (like an implicit full-size `ImageLayer` with `fit: ImageFit.cover`, regardless of any layer's `zIndex`). |

### `Layer` (base class)

Every element on a scene inherits these properties:

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | `String` | auto | Stable identifier for this layer instance. |
| `transform` | `LayerTransform` | identity | Position, rotation, scale, anchor. |
| `size` | `Size2D?` | `null` | Explicit size; `null` means intrinsic (content-derived). |
| `opacity` | `double` | `1.0` | Compositing alpha, `0.0`–`1.0`. |
| `zIndex` | `int` | `0` | Stacking order (higher = on top). |
| `visible` | `bool` | `true` | Invisible layers are not sent to the native engine. |

### `LayerTransform`

```dart
const LayerTransform(
  position: Point2D(x, y),   // translation in logical pixels
  rotation: radians,          // clockwise rotation in radians
  scale: Point2D(sx, sy),    // per-axis scale factor
  anchor: Point2D(0.5, 0.5), // pivot as fraction of layer size (default: center)
)
```

### Concrete layer types

| Type | Status | Key properties |
|---|---|---|
| `RectangleLayer` | ✅ Native render | `paint`, `cornerRadius` |
| `TextLayer` | ✅ Native render | `text`, `fontSize`, `color`, `fontFamily`, `fontWeight`, `align` |
| `Group` | ✅ Flattened before render | `children` |
| `ImageLayer` | ✅ Native render | `source`, `fit` |

> **Note:** `Group` never reaches the native engine — the renderer expands
> it into its concrete descendants first, composing the group's
> transform/opacity into each one (see `scene_flattener.dart`), so
> `scene_desc.h` and the Blend2D backend need no changes to support it.

### `Renderer`

```dart
const renderer = Renderer();

// Returns PNG bytes
final Uint8List bytes = await renderer.render(scene);

// Writes PNG to path
await renderer.renderToFile(scene, outputPath);
```

Throws `RenderException` (a subtype of `Exception`) if the native engine
returns a non-zero status code.

### `FontRegistry`

```dart
FontRegistry.register('Brand', ttfBytes); // Uint8List of raw TTF/OTF data
FontRegistry.unregister('Brand');
```

Global to the process — registered fonts are available to every `Scene`
rendered afterward, by any `Renderer`. `register` throws a
`FontRegistrationException` if `ttfBytes` isn't valid font data.

### `Color32`

An immutable 32-bit ARGB color. Packed as `0xAARRGGBB`.

```dart
const Color32(0xFF3A7BD5)          // hex literal
Color32.fromRGB(58, 123, 213)      // fully opaque
Color32.fromARGB(180, 58, 123, 213) // with alpha
Color32.white.withOpacity(0.5)     // derived color
```

### `LayerPaint`

```dart
const LayerPaint(
  color: Color32.fromRGB(255, 0, 0),
  style: LayerPaintStyle.fillAndStroke, // fill | stroke | fillAndStroke
  strokeWidth: 2.0,
)
```

### `LayerImageSource`

Describes where image data comes from without decoding it:

```dart
LayerImageSource.file('/path/to/image.png')
LayerImageSource.memory(bytes) // Uint8List of encoded image data
```

## Architecture

```mermaid
flowchart TD
    A["<b>Dart public API</b> · lib/\nScene · Layer · Renderer"]
    B["<b>C++ engine</b> · src/\nengine.h / engine.cpp\nLcLayerDesc wire format"]
    C["<b>Blend2D backend</b> · src/backend/blend2d/\nRaster pipeline · PNG encode"]

    A -->|"Dart FFI — lc_render_scene()"| B
    B -->|"LcGraphicsBackend vtable"| C
```

The engine core (`engine.cpp`) is decoupled from Blend2D through the
`LcGraphicsBackend` function-pointer table defined in `src/backend/backend.h`.
Swapping to a different graphics library means implementing that table and
changing one line in `engine.cpp` — nothing in the public API or `Scene` model
changes.

## Building from source

The native library is compiled automatically by `hook/build.dart` using
`package:native_toolchain_c`. No manual invocation is needed; `flutter run`,
`dart test`, and `dart build` all trigger it.

To regenerate the Dart FFI bindings after modifying `src/engine.h`:

```sh
dart run ffigen --config ffigen.yaml
```

## Running tests

```sh
dart test
```

## Running benchmarks

```sh
dart run benchmark/render_benchmark.dart
```

[native_assets]: https://dart.dev/interop/c-interop#native-assets
