// ignore_for_file: avoid_print
//
// Render comparison: Blend2D (native FFI) vs dart:ui (Skia/Impeller).
//
// Run from the example/ directory:
//   flutter test benchmark/render_comparison.dart --reporter expanded
//
// Both renderers produce the same logical output (PNG bytes for a given scene).
// Blend2D is a CPU software rasterizer with no GPU path.
// dart:ui uses Skia or Impeller; in `flutter test` it runs headless (CPU path).
// The comparison is therefore fair: both are measured offscreen, CPU-only.

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_canvas/layer_canvas.dart';

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

const _kWarmup = 8;
const _kRuns = 40;

Future<double> _time(Future<void> Function() fn) async {
  for (var i = 0; i < _kWarmup; i++) {
    await fn();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < _kRuns; i++) {
    await fn();
  }
  return sw.elapsedMicroseconds / _kRuns;
}

// ---------------------------------------------------------------------------
// dart:ui helpers — mirror the Blend2D scenes exactly
// ---------------------------------------------------------------------------

ui.Paint _fillPaint(int argb) =>
    ui.Paint()..color = ui.Color(argb)..style = ui.PaintingStyle.fill;

Future<void> _dartUiEmpty(int w, int h) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec);
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
}

Future<void> _dartUiSingleRect(int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      _fillPaint(0xFF1E1E1E));
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
}

Future<void> _dartUiWatermark() async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, 400, 300), _fillPaint(0xFF141414));
  c.drawRect(ui.Rect.fromLTWH(0, 240, 400, 60), _fillPaint(0xCC000000));
  // Rotated stamp — same anchor math as LayerTransform (center of rect)
  c.save();
  c.translate(120 + 80, 130 + 20);
  c.rotate(-0.4);
  c.translate(-80, -20);
  c.drawRRect(
      ui.RRect.fromLTRBR(0, 0, 160, 40, const ui.Radius.circular(6)),
      _fillPaint(0x44FFFFFF));
  c.restore();
  final pic = rec.endRecording();
  final img = await pic.toImage(400, 300);
  await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
}

Future<void> _dartUiNRects(int n, int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  for (var i = 0; i < n; i++) {
    c.drawRect(
      ui.Rect.fromLTWH((i % 20) * 40.0, (i ~/ 20) * 40.0, 38, 38),
      _fillPaint(ui.Color.fromARGB(
              255, (i * 5) % 256, (i * 13) % 256, (i * 7) % 256)
          .toARGB32()),
    );
  }
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
}

Future<void> _dartUiLarge() async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  for (var i = 0; i < 10; i++) {
    c.drawRRect(
      ui.RRect.fromLTRBR(
          i * 192.0, i * 108.0, i * 192.0 + 400, i * 108.0 + 200,
          const ui.Radius.circular(8)),
      _fillPaint(ui.Color.fromARGB(255, i * 25, 0, 255 - i * 25).toARGB32()),
    );
  }
  final pic = rec.endRecording();
  final img = await pic.toImage(1920, 1080);
  await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
}

// ---------------------------------------------------------------------------
// Blend2D scene builders — match the dart:ui scenes above
// ---------------------------------------------------------------------------

Scene _b2dWatermark() => Scene(width: 400, height: 300)
  ..add(RectangleLayer(
      size: const Size2D(400, 300),
      paint: const LayerPaint(color: Color32(0xFF141414))))
  ..add(RectangleLayer(
      transform: const LayerTransform(position: Point2D(0, 240)),
      size: const Size2D(400, 60),
      paint: const LayerPaint(color: Color32(0xCC000000))))
  ..add(RectangleLayer(
      transform:
          LayerTransform(position: const Point2D(120, 130), rotation: -0.4),
      size: const Size2D(160, 40),
      paint: const LayerPaint(color: Color32(0x44FFFFFF)),
      cornerRadius: 6));

Scene _b2dNRects(int n, int w, int h) {
  final s = Scene(width: w, height: h);
  for (var i = 0; i < n; i++) {
    s.add(RectangleLayer(
      transform: LayerTransform(
          position: Point2D((i % 20) * 40.0, (i ~/ 20) * 40.0)),
      size: const Size2D(38, 38),
      paint: LayerPaint(
          color: Color32.fromRGB((i * 5) % 256, (i * 13) % 256, (i * 7) % 256)),
    ));
  }
  return s;
}

Scene _b2dLarge() {
  final s = Scene(width: 1920, height: 1080);
  for (var i = 0; i < 10; i++) {
    s.add(RectangleLayer(
      transform: LayerTransform(position: Point2D(i * 192.0, i * 108.0)),
      size: const Size2D(400, 200),
      paint: LayerPaint(
          color: Color32.fromRGB(i * 25, 0, 255 - i * 25)),
      cornerRadius: 8,
    ));
  }
  return s;
}

// ---------------------------------------------------------------------------
// Report helpers
// ---------------------------------------------------------------------------

void _header() {
  print('');
  print('╔══════════════════════════════════════════════════════════════════════╗');
  print('║     Render comparison: Blend2D (FFI) vs dart:ui (Skia/Impeller)    ║');
  print('║     Warmup: $_kWarmup runs  |  Measured: $_kRuns runs per scenario'
      '${' ' * (21 - '$_kWarmup'.length - '$_kRuns'.length)}║');
  print('╠══════════════════════════════════════════╦══════════════╦═══════════╣');
  print('║ Scenario                                 ║  Blend2D     ║  dart:ui  ║');
  print('╠══════════════════════════════════════════╬══════════════╬═══════════╣');
}

void _footer() {
  print('╚══════════════════════════════════════════╩══════════════╩═══════════╝');
  print('');
  print('Note: dart:ui runs headless (CPU path) in flutter test.');
  print('Blend2D: CPU-only software rasterizer, no JIT, no GPU.');
  print('');
}

void _row(String name, double b2dUs, double dartUiUs) {
  final bMs = (b2dUs / 1000).toStringAsFixed(2).padLeft(7);
  final dMs = (dartUiUs / 1000).toStringAsFixed(2).padLeft(7);
  final ratio = dartUiUs / b2dUs;
  final winner = ratio > 1.05
      ? '🟢 B2D ${ratio.toStringAsFixed(1)}×'
      : ratio < 0.95
          ? '🔴 dui ${(1 / ratio).toStringAsFixed(1)}×'
          : '≈ tie';
  print('║ ${name.padRight(40)} ║ $bMs ms     ║ $dMs ms  ║  $winner');
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Blend2D vs dart:ui render comparison',
    () async {
      const renderer = Renderer();

      // --- empty canvas ---
      final b1 = await _time(() => renderer.render(Scene(width: 400, height: 300)));
      final d1 = await _time(() => _dartUiEmpty(400, 300));

      // --- single full rect ---
      final b2 = await _time(() => renderer.render(
            Scene(width: 400, height: 300)
              ..add(RectangleLayer(
                size: const Size2D(400, 300),
                paint: const LayerPaint(color: Color32(0xFF1E1E1E)),
              )),
          ));
      final d2 = await _time(() => _dartUiSingleRect(400, 300));

      // --- watermark (3 rects, transform + alpha) ---
      final b3 = await _time(() => renderer.render(_b2dWatermark()));
      final d3 = await _time(_dartUiWatermark);

      // --- 10 rects 800×600 ---
      final b4 = await _time(() => renderer.render(_b2dNRects(10, 800, 600)));
      final d4 = await _time(() => _dartUiNRects(10, 800, 600));

      // --- 50 rects 800×600 ---
      final b5 = await _time(() => renderer.render(_b2dNRects(50, 800, 600)));
      final d5 = await _time(() => _dartUiNRects(50, 800, 600));

      // --- 10 rects 1920×1080 ---
      final b6 = await _time(() => renderer.render(_b2dLarge()));
      final d6 = await _time(_dartUiLarge);

      _header();
      _row('empty canvas 400×300', b1, d1);
      _row('single rect 400×300', b2, d2);
      _row('watermark — 3 rects + transform 400×300', b3, d3);
      _row('10 colored rects 800×600', b4, d4);
      _row('50 colored rects 800×600', b5, d5);
      _row('10 rects 1920×1080 (large canvas)', b6, d6);
      _footer();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
