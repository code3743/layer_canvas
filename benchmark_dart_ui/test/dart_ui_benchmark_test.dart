// Cross-tool comparison benchmark: dart:ui (Flutter's Canvas/Skia,
// rasterized headlessly via TestWidgetsFlutterBinding).
//
// Draws the exact same scenes (same canvas sizes, positions, colors) as
// benchmark/render_benchmark.dart and benchmark/image_package_benchmark.dart,
// so the three reports can be compared side by side. Run with:
//
//   flutter test test/dart_ui_benchmark_test.dart
//
// (from this directory; `flutter pub get` first if you haven't already).
// This can't run with `dart run` - dart:ui needs a Flutter engine to
// rasterize, which `flutter test`'s binding provides headlessly.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<Uint8List> _rasterizeAndEncode(
  ui.PictureRecorder recorder,
  int width,
  int height,
) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

Future<Uint8List> _empty() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder); // Registers with the recorder; nothing drawn.
  return _rasterizeAndEncode(recorder, 400, 300);
}

Future<Uint8List> _singleRect() {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..color = const ui.Color.fromARGB(255, 30, 30, 30);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 400, 300), paint);
  return _rasterizeAndEncode(recorder, 400, 300);
}

Future<Uint8List> _watermark() {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 400, 300),
    ui.Paint()..color = const ui.Color.fromARGB(255, 20, 20, 20),
  );

  // Bottom band.
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 240, 400, 60),
    ui.Paint()..color = const ui.Color.fromARGB(0xCC, 0, 0, 0),
  );

  // Rotated stamp, position (120,130) size 160x40 rotation -0.4 - same
  // parameters as the other two benchmarks' watermark scene, same
  // translate/translate(pivot)/rotate/translate(-pivot) sequence
  // layer_canvas's own backend applies per layer (see RenderRectangle in
  // src/backend/blend2d/blend2d_backend.cpp), so the pivot (the rect's own
  // center) matches layer_canvas's default anchor (0.5, 0.5).
  canvas.save();
  canvas.translate(120, 130);
  canvas.translate(80, 20);
  canvas.rotate(-0.4);
  canvas.translate(-80, -20);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 160, 40),
    ui.Paint()..color = const ui.Color.fromARGB(0x44, 255, 255, 255),
  );
  canvas.restore();

  return _rasterizeAndEncode(recorder, 400, 300);
}

Future<Uint8List> _nRects(int n, int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var i = 0; i < n; i++) {
    final x = (i % 20) * 40.0;
    final y = (i ~/ 20) * 40.0;
    final paint = ui.Paint()
      ..color = ui.Color.fromARGB(
        255,
        i * 5 % 256,
        (i * 13) % 256,
        (i * 7) % 256,
      );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(x, y, 38, 38),
        ui.Radius.circular((i % 5).toDouble()),
      ),
      paint,
    );
  }
  return _rasterizeAndEncode(recorder, width, height);
}

Future<Uint8List> _largeCanvas() {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var i = 0; i < 10; i++) {
    final paint = ui.Paint()
      ..color = ui.Color.fromARGB(255, i * 25, 0, 255 - i * 25);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(i * 192.0, i * 108.0, 400, 200),
        const ui.Radius.circular(8),
      ),
      paint,
    );
  }
  return _rasterizeAndEncode(recorder, 1920, 1080);
}

// ---------------------------------------------------------------------------
// Benchmark classes — AsyncBenchmarkBase, not BenchmarkBase: dart:ui's
// rasterize/encode calls are genuinely async (they hand off to the engine's
// raster pipeline), so run() must be awaited between iterations rather than
// fired off synchronously in a tight loop.
// ---------------------------------------------------------------------------

class EmptyBenchmark extends AsyncBenchmarkBase {
  EmptyBenchmark() : super('empty (400x300)');

  @override
  Future<void> run() => _empty();
}

class SingleRectBenchmark extends AsyncBenchmarkBase {
  SingleRectBenchmark() : super('singleRect (400x300)');

  @override
  Future<void> run() => _singleRect();
}

class WatermarkBenchmark extends AsyncBenchmarkBase {
  WatermarkBenchmark() : super('watermark (400x300)');

  @override
  Future<void> run() => _watermark();
}

class Rects10Benchmark extends AsyncBenchmarkBase {
  Rects10Benchmark() : super('rects10 (800x600)');

  @override
  Future<void> run() => _nRects(10, 800, 600);
}

class Rects50Benchmark extends AsyncBenchmarkBase {
  Rects50Benchmark() : super('rects50 (800x600)');

  @override
  Future<void> run() => _nRects(50, 800, 600);
}

class LargeCanvas10Benchmark extends AsyncBenchmarkBase {
  LargeCanvas10Benchmark() : super('largeCanvas10 (1920x1080)');

  @override
  Future<void> run() => _largeCanvas();
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dart:ui render benchmarks', () async {
    // ignore: avoid_print
    print('dart:ui render benchmarks');
    // ignore: avoid_print
    print(
      'Flutter engine, same scenes as the other two comparison '
      'benchmarks',
    );
    // ignore: avoid_print
    print('');

    await EmptyBenchmark().report();
    await SingleRectBenchmark().report();
    await WatermarkBenchmark().report();
    await Rects10Benchmark().report();
    await Rects50Benchmark().report();
    await LargeCanvas10Benchmark().report();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
