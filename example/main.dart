// Generates a GPS-style photo watermark with layer_canvas — pure Dart, no
// Flutter engine involved anywhere. Run with:
//
//   dart run main.dart
//
// (from this directory; `dart pub get` first if you haven't already).
import 'dart:io';

import 'package:layer_canvas/layer_canvas.dart';

import 'data/mock_location.dart';
import 'scene/watermark_scene.dart';

Future<void> main() async {
  // Resolve the bundled photo relative to this script, so `dart run
  // main.dart` works regardless of the shell's current directory.
  final scriptDir = File.fromUri(Platform.script).parent;
  final photoPath = scriptDir.uri
      .resolve('assets/images/watermark_sample.jpg')
      .toFilePath();

  final scene = buildWatermarkScene(
    sampleLocation,
    width: 480,
    height: 640,
    background: LayerImageSource.file(photoPath),
  );

  final outputDir = await Directory(
    scriptDir.uri.resolve('output/').toFilePath(),
  ).create(recursive: true);
  final outputPath = outputDir.uri.resolve('gps_watermark.png').toFilePath();

  await const Renderer().renderToFile(scene, outputPath);

  stdout.writeln('Wrote $outputPath (${scene.width}x${scene.height})');
}
