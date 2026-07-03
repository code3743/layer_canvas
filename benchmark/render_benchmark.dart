// ignore_for_file: avoid_print
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:layer_canvas/layer_canvas.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Scene _emptyScene() => Scene(width: 400, height: 300);

Scene _singleRect() => Scene(width: 400, height: 300)
  ..add(RectangleLayer(
    size: const Size2D(400, 300),
    paint: const LayerPaint(color: Color32.fromRGB(30, 30, 30)),
  ));

Scene _watermarkScene() {
  final scene = Scene(width: 400, height: 300);
  scene.add(RectangleLayer(
    size: const Size2D(400, 300),
    paint: const LayerPaint(color: Color32.fromRGB(20, 20, 20)),
  ));
  // Bottom band
  scene.add(RectangleLayer(
    transform: const LayerTransform(position: Point2D(0, 240)),
    size: const Size2D(400, 60),
    paint: const LayerPaint(color: Color32(0xCC000000)),
  ));
  // Rotated stamp
  scene.add(RectangleLayer(
    transform: LayerTransform(
      position: const Point2D(120, 130),
      rotation: -0.4,
    ),
    size: const Size2D(160, 40),
    paint: const LayerPaint(color: Color32(0x44FFFFFF)),
    cornerRadius: 6,
  ));
  return scene;
}

Scene _nRects(int n) {
  final scene = Scene(width: 800, height: 600);
  for (var i = 0; i < n; i++) {
    scene.add(RectangleLayer(
      transform: LayerTransform(position: Point2D((i % 20) * 40.0, (i ~/ 20) * 40.0)),
      size: const Size2D(38, 38),
      paint: LayerPaint(
        color: Color32.fromRGB(i * 5 % 256, (i * 13) % 256, (i * 7) % 256),
      ),
      cornerRadius: (i % 5).toDouble(),
    ));
  }
  return scene;
}

// ---------------------------------------------------------------------------
// Benchmark classes
// ---------------------------------------------------------------------------

class EmptySceneBenchmark extends BenchmarkBase {
  EmptySceneBenchmark() : super('Render.emptyScene (400×300)');
  final _renderer = const Renderer();
  late Scene _scene;

  @override
  void setup() => _scene = _emptyScene();

  @override
  void run() => _renderer.render(_scene);
}

class SingleRectBenchmark extends BenchmarkBase {
  SingleRectBenchmark() : super('Render.singleRect (400×300)');
  final _renderer = const Renderer();
  late Scene _scene;

  @override
  void setup() => _scene = _singleRect();

  @override
  void run() => _renderer.render(_scene);
}

class WatermarkBenchmark extends BenchmarkBase {
  WatermarkBenchmark() : super('Render.watermark 3 rects (400×300)');
  final _renderer = const Renderer();
  late Scene _scene;

  @override
  void setup() => _scene = _watermarkScene();

  @override
  void run() => _renderer.render(_scene);
}

class TenRectsBenchmark extends BenchmarkBase {
  TenRectsBenchmark() : super('Render.10 rects (800×600)');
  final _renderer = const Renderer();
  late Scene _scene;

  @override
  void setup() => _scene = _nRects(10);

  @override
  void run() => _renderer.render(_scene);
}

class FiftyRectsBenchmark extends BenchmarkBase {
  FiftyRectsBenchmark() : super('Render.50 rects (800×600)');
  final _renderer = const Renderer();
  late Scene _scene;

  @override
  void setup() => _scene = _nRects(50);

  @override
  void run() => _renderer.render(_scene);
}

class LargeCanvasBenchmark extends BenchmarkBase {
  LargeCanvasBenchmark() : super('Render.10 rects 1920×1080');
  final _renderer = const Renderer();
  late Scene _scene;

  @override
  void setup() {
    _scene = Scene(width: 1920, height: 1080);
    for (var i = 0; i < 10; i++) {
      _scene.add(RectangleLayer(
        transform: LayerTransform(position: Point2D(i * 192.0, i * 108.0)),
        size: const Size2D(400, 200),
        paint: LayerPaint(color: Color32.fromRGB(i * 25, 0, 255 - i * 25)),
        cornerRadius: 8,
      ));
    }
  }

  @override
  void run() => _renderer.render(_scene);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  print('layer_canvas render benchmarks');
  print('Blend2D native backend via Dart FFI');
  print('');

  EmptySceneBenchmark().report();
  SingleRectBenchmark().report();
  WatermarkBenchmark().report();
  TenRectsBenchmark().report();
  FiftyRectsBenchmark().report();
  LargeCanvasBenchmark().report();
}
