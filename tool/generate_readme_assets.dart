// Regenerates the README's hero banner (doc/hero.png). Run with:
//
//   dart run tool/generate_readme_assets.dart
//
// The banner is generated with layer_canvas itself — deliberately using the
// ergonomic .filled/.colors constructors so it doubles as a live example of
// the simplified API, not just branding art.
//
// The README's other image, doc/watermark_demo.png, is a copy of
// example/output/gps_watermark.png (gitignored, since example/output/ is
// scratch output) — refresh it by running `dart run main.dart` inside
// example/, then copying the result over doc/watermark_demo.png.
import 'dart:io';

import 'package:layer_canvas/layer_canvas.dart';

Future<void> main() async {
  const width = 960.0;
  const height = 400.0;
  final scene = Scene(width: width.toInt(), height: height.toInt());

  // Background: dark navy -> purple diagonal gradient.
  scene.add(
    RectangleLayer(
      size: const Size2D(width, height),
      paint: LayerPaint(
        gradient: LinearGradient.colors(
          start: const Point2D(0, 0),
          end: const Point2D(1, 1),
          colors: [Color32.fromRGB(13, 17, 38), Color32.fromRGB(52, 18, 84)],
        ),
      ),
    ),
  );

  // Soft decorative circles on the right, built with the new .filled/.circle
  // convenience factories — no Size2D/LayerPaint/arc-flag arithmetic needed.
  scene.add(
    PathLayer.filled(
      path: LayerPath.circle(const Point2D(770, 90), 150),
      color: const Color32.fromARGB(60, 58, 123, 213),
    ),
  );
  scene.add(
    PathLayer.filled(
      path: LayerPath.circle(const Point2D(880, 280), 120),
      color: const Color32.fromARGB(55, 210, 90, 210),
    ),
  );
  scene.add(
    PathLayer.filled(
      path: LayerPath.circle(const Point2D(660, 320), 90),
      color: const Color32.fromARGB(45, 0, 210, 255),
    ),
  );

  // Title + tagline.
  scene.add(
    TextLayer(
      text: 'layer_canvas',
      transform: const LayerTransform(position: Point2D(60, 120)),
      size: const Size2D(700, 80),
      fontSize: 64,
      fontWeight: TextWeight.bold,
      color: Color32.white,
    ),
  );
  scene.add(
    TextLayer(
      text: 'Native 2D rendering for Dart & Flutter',
      transform: const LayerTransform(position: Point2D(64, 210)),
      size: const Size2D(700, 32),
      fontSize: 22,
      color: const Color32.fromRGB(216, 216, 236),
    ),
  );
  scene.add(
    TextLayer(
      text: 'Blend2D via FFI · typed layers · no dart:ui required',
      transform: const LayerTransform(position: Point2D(64, 250)),
      size: const Size2D(700, 26),
      fontSize: 16,
      color: const Color32.fromRGB(160, 160, 190),
    ),
  );

  final scriptDir = File.fromUri(Platform.script).parent;
  final outputPath = scriptDir.uri.resolve('../doc/hero.png').toFilePath();
  await const Renderer().renderToFile(scene, outputPath);
  stdout.writeln('Wrote $outputPath');
}
