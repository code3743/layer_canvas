// ignore_for_file: avoid_print
//
// Cross-tool comparison benchmark: package:image (pure Dart, no Flutter).
//
// Draws the exact same scenes (same canvas sizes, positions, colors) as
// benchmark/render_benchmark.dart and
// benchmark_dart_ui/test/dart_ui_benchmark_test.dart, so the three reports
// can be compared side by side. See the README's "Running benchmarks"
// section.
import 'dart:math' as math;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

img.Image _empty() => img.Image(width: 400, height: 300);

img.Image _singleRect() {
  final image = img.Image(width: 400, height: 300);
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 399,
    y2: 299,
    color: img.ColorRgb8(30, 30, 30),
  );
  return image;
}

/// The point `(localX, localY)` of a shape whose own local origin sits at
/// `(pivotX, pivotY)` before rotating by `rotation` (radians) around that
/// pivot and translating by `(posX, posY)` — the same
/// translate/translate(pivot)/rotate/translate(-pivot) sequence
/// `layer_canvas`'s backend applies per layer (see `RenderRectangle` in
/// `src/backend/blend2d/blend2d_backend.cpp`), replicated here since
/// `package:image` has no built-in notion of a rotated fill.
img.Point _rotatedPoint(
  double localX,
  double localY, {
  required double pivotX,
  required double pivotY,
  required double rotation,
  required double posX,
  required double posY,
}) {
  final x = localX - pivotX;
  final y = localY - pivotY;
  final cosT = math.cos(rotation);
  final sinT = math.sin(rotation);
  final rotatedX = x * cosT - y * sinT;
  final rotatedY = x * sinT + y * cosT;
  return img.Point(rotatedX + pivotX + posX, rotatedY + pivotY + posY);
}

img.Image _watermark() {
  final image = img.Image(width: 400, height: 300);

  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 399,
    y2: 299,
    color: img.ColorRgb8(20, 20, 20),
  );

  // Bottom band.
  img.fillRect(
    image,
    x1: 0,
    y1: 240,
    x2: 399,
    y2: 299,
    color: img.ColorRgba8(0, 0, 0, 0xCC),
  );

  // Rotated stamp, position (120,130) size 160x40 rotation -0.4 - same
  // parameters as the other two benchmarks' watermark scene. Pivot is the
  // rect's own center (80, 20), matching layer_canvas's default anchor
  // (0.5, 0.5).
  const pivotX = 80.0,
      pivotY = 20.0,
      rotation = -0.4,
      posX = 120.0,
      posY = 130.0;
  img.Point corner(double x, double y) => _rotatedPoint(
    x,
    y,
    pivotX: pivotX,
    pivotY: pivotY,
    rotation: rotation,
    posX: posX,
    posY: posY,
  );
  img.fillPolygon(
    image,
    vertices: [corner(0, 0), corner(160, 0), corner(160, 40), corner(0, 40)],
    color: img.ColorRgba8(255, 255, 255, 0x44),
  );

  return image;
}

img.Image _nRects(int n) {
  final image = img.Image(width: 800, height: 600);
  for (var i = 0; i < n; i++) {
    final x = (i % 20) * 40;
    final y = (i ~/ 20) * 40;
    img.fillRect(
      image,
      x1: x,
      y1: y,
      x2: x + 37,
      y2: y + 37,
      color: img.ColorRgb8(i * 5 % 256, (i * 13) % 256, (i * 7) % 256),
      radius: i % 5,
    );
  }
  return image;
}

img.Image _largeCanvas() {
  final image = img.Image(width: 1920, height: 1080);
  for (var i = 0; i < 10; i++) {
    final x = i * 192;
    final y = i * 108;
    img.fillRect(
      image,
      x1: x,
      y1: y,
      x2: x + 399,
      y2: y + 199,
      color: img.ColorRgb8(i * 25, 0, 255 - i * 25),
      radius: 8,
    );
  }
  return image;
}

// ---------------------------------------------------------------------------
// Benchmark classes
// ---------------------------------------------------------------------------

class EmptyBenchmark extends BenchmarkBase {
  EmptyBenchmark() : super('empty (400x300)');

  @override
  void run() => img.encodePng(_empty());
}

class SingleRectBenchmark extends BenchmarkBase {
  SingleRectBenchmark() : super('singleRect (400x300)');

  @override
  void run() => img.encodePng(_singleRect());
}

class WatermarkBenchmark extends BenchmarkBase {
  WatermarkBenchmark() : super('watermark (400x300)');

  @override
  void run() => img.encodePng(_watermark());
}

class Rects10Benchmark extends BenchmarkBase {
  Rects10Benchmark() : super('rects10 (800x600)');

  @override
  void run() => img.encodePng(_nRects(10));
}

class Rects50Benchmark extends BenchmarkBase {
  Rects50Benchmark() : super('rects50 (800x600)');

  @override
  void run() => img.encodePng(_nRects(50));
}

class LargeCanvas10Benchmark extends BenchmarkBase {
  LargeCanvas10Benchmark() : super('largeCanvas10 (1920x1080)');

  @override
  void run() => img.encodePng(_largeCanvas());
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  print('package:image render benchmarks');
  print('Pure Dart, no native backend');
  print('');

  EmptyBenchmark().report();
  SingleRectBenchmark().report();
  WatermarkBenchmark().report();
  Rects10Benchmark().report();
  Rects50Benchmark().report();
  LargeCanvas10Benchmark().report();
}
