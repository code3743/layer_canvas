# layer_canvas_example

Generates a GPS-style photo watermark with `layer_canvas` — a bundled photo
(`assets/images/watermark_sample.jpg`) with a translucent info card
(location, coordinates, timestamp) composited natively on top, in a single
render pass. Pure Dart: no Flutter engine, no widget tree, no platform
folders.

## Run it

```sh
dart pub get
dart run main.dart
```

This writes `output/gps_watermark.png` next to this file. Open it to see
the result.

## What it shows

- `Scene(background: ...)` — the photo, scaled to cover the whole canvas.
- `RectangleLayer` — the translucent card behind the text.
- `TextLayer` — the location name, coordinates, and timestamp, all
  rendered natively (no `dart:ui`, no `TextPainter`).
- `Renderer.renderToFile` — one call from bytes to a PNG on disk.

See [`scene/watermark_scene.dart`](scene/watermark_scene.dart) for how the
layers are composed, and [`data/mock_location.dart`](data/mock_location.dart)
for the mock GPS reading and its formatting.

To use this same package from a Flutter app instead, see the root
[`README.md`](../README.md) — the `Scene`/`Renderer`/layer API is identical
either way; only how you get the resulting PNG onto the screen differs
(`Image.memory` in Flutter vs. writing it to disk here).
