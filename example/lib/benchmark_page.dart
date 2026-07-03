import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:layer_canvas/layer_canvas.dart';

// ---------------------------------------------------------------------------
// Tuning
// ---------------------------------------------------------------------------

const _kWarmup = 5;
const _kRuns = 20;

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _ScenarioDef {
  final String name;
  final int canvasW;
  final int canvasH;
  final Scene Function() buildBlend2D;
  final void Function(ui.Canvas c, int w, int h) drawDartUi;

  const _ScenarioDef({
    required this.name,
    required this.canvasW,
    required this.canvasH,
    required this.buildBlend2D,
    required this.drawDartUi,
  });
}

class _ScenarioResult {
  final _ScenarioDef def;
  final Uint8List blend2dPng;
  final double blend2dMs;
  final Uint8List dartUiPng;
  final double dartUiMs;

  const _ScenarioResult({
    required this.def,
    required this.blend2dPng,
    required this.blend2dMs,
    required this.dartUiPng,
    required this.dartUiMs,
  });

  double get ratio => dartUiMs / blend2dMs;
  bool get blend2dWins => ratio > 1.05;
  bool get dartUiWins => ratio < 0.95;

  String get winnerLabel {
    if (blend2dWins) return 'Blend2D  ${ratio.toStringAsFixed(1)}× faster';
    if (dartUiWins) return 'dart:ui  ${(1 / ratio).toStringAsFixed(1)}× faster';
    return 'Tie';
  }

  Color get winnerColor {
    if (blend2dWins) return const Color(0xFF2E7D32); // green
    if (dartUiWins) return const Color(0xFF1565C0); // blue
    return Colors.grey;
  }
}

// ---------------------------------------------------------------------------
// Scenario definitions
// ---------------------------------------------------------------------------

ui.Paint _uiFill(int argb) =>
    ui.Paint()..color = ui.Color(argb)..style = ui.PaintingStyle.fill;

final _scenarios = <_ScenarioDef>[
  _ScenarioDef(
    name: 'Watermark — 3 rects',
    canvasW: 400,
    canvasH: 300,
    buildBlend2D: () => Scene(width: 400, height: 300)
      ..add(RectangleLayer(
        size: const Size2D(400, 300),
        paint: const LayerPaint(color: Color32(0xFF1A1A2E)),
      ))
      ..add(RectangleLayer(
        transform: const LayerTransform(position: Point2D(0, 240)),
        size: const Size2D(400, 60),
        paint: const LayerPaint(color: Color32(0xCC000000)),
      ))
      ..add(RectangleLayer(
        transform:
            LayerTransform(position: const Point2D(120, 130), rotation: -0.4),
        size: const Size2D(160, 40),
        paint: const LayerPaint(color: Color32(0x44FFFFFF)),
        cornerRadius: 6,
      )),
    drawDartUi: (c, w, h) {
      c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          _uiFill(0xFF1A1A2E));
      c.drawRect(
          ui.Rect.fromLTWH(0, 240, 400, 60), _uiFill(0xCC000000));
      c.save();
      c.translate(120 + 80, 130 + 20);
      c.rotate(-0.4);
      c.translate(-80, -20);
      c.drawRRect(
          ui.RRect.fromLTRBR(0, 0, 160, 40, const ui.Radius.circular(6)),
          _uiFill(0x44FFFFFF));
      c.restore();
    },
  ),
  _ScenarioDef(
    name: '50 colored rects',
    canvasW: 800,
    canvasH: 600,
    buildBlend2D: () {
      final s = Scene(width: 800, height: 600);
      for (var i = 0; i < 50; i++) {
        s.add(RectangleLayer(
          transform: LayerTransform(
              position: Point2D((i % 20) * 40.0, (i ~/ 20) * 40.0)),
          size: const Size2D(36, 36),
          paint: LayerPaint(
              color: Color32.fromRGB(
                  (i * 5) % 256, (i * 13) % 256, (i * 7) % 256)),
          cornerRadius: 4,
        ));
      }
      return s;
    },
    drawDartUi: (c, w, h) {
      for (var i = 0; i < 50; i++) {
        c.drawRRect(
          ui.RRect.fromLTRBR(
              (i % 20) * 40.0,
              (i ~/ 20) * 40.0,
              (i % 20) * 40.0 + 36,
              (i ~/ 20) * 40.0 + 36,
              const ui.Radius.circular(4)),
          _uiFill(ui.Color.fromARGB(
                  255, (i * 5) % 256, (i * 13) % 256, (i * 7) % 256)
              .toARGB32()),
        );
      }
    },
  ),
  _ScenarioDef(
    name: '10 rects — 1920×1080',
    canvasW: 1920,
    canvasH: 1080,
    buildBlend2D: () {
      final s = Scene(width: 1920, height: 1080);
      for (var i = 0; i < 10; i++) {
        s.add(RectangleLayer(
          transform:
              LayerTransform(position: Point2D(i * 192.0, i * 108.0)),
          size: const Size2D(400, 200),
          paint: LayerPaint(
              color: Color32.fromRGB(i * 25, 40, 255 - i * 25)),
          cornerRadius: 12,
        ));
      }
      return s;
    },
    drawDartUi: (c, w, h) {
      for (var i = 0; i < 10; i++) {
        c.drawRRect(
          ui.RRect.fromLTRBR(
              i * 192.0,
              i * 108.0,
              i * 192.0 + 400,
              i * 108.0 + 200,
              const ui.Radius.circular(12)),
          _uiFill(
              ui.Color.fromARGB(255, i * 25, 40, 255 - i * 25).toARGB32()),
        );
      }
    },
  ),
];

// ---------------------------------------------------------------------------
// Measurement helpers
// ---------------------------------------------------------------------------

Future<(Uint8List, double)> _runBlend2D(_ScenarioDef def) async {
  const renderer = Renderer();
  for (var i = 0; i < _kWarmup; i++) {
    await renderer.render(def.buildBlend2D());
  }
  final sw = Stopwatch()..start();
  late Uint8List last;
  for (var i = 0; i < _kRuns; i++) {
    last = await renderer.render(def.buildBlend2D());
  }
  return (last, sw.elapsedMicroseconds / _kRuns / 1000);
}

Future<(Uint8List, double)> _runDartUi(_ScenarioDef def) async {
  Future<Uint8List> once() async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    def.drawDartUi(canvas, def.canvasW, def.canvasH);
    final pic = rec.endRecording();
    final img = await pic.toImage(def.canvasW, def.canvasH);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd!.buffer.asUint8List();
  }

  for (var i = 0; i < _kWarmup; i++) {
    await once();
  }
  final sw = Stopwatch()..start();
  late Uint8List last;
  for (var i = 0; i < _kRuns; i++) {
    last = await once();
  }
  return (last, sw.elapsedMicroseconds / _kRuns / 1000);
}

Future<_ScenarioResult> _runScenario(_ScenarioDef def) async {
  final (b2dPng, b2dMs) = await _runBlend2D(def);
  final (duiPng, duiMs) = await _runDartUi(def);
  return _ScenarioResult(
    def: def,
    blend2dPng: b2dPng,
    blend2dMs: b2dMs,
    dartUiPng: duiPng,
    dartUiMs: duiMs,
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  List<_ScenarioResult>? _results;
  bool _running = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = null;
      _progress = 0;
    });

    final results = <_ScenarioResult>[];
    for (final def in _scenarios) {
      final r = await _runScenario(def);
      results.add(r);
      setState(() => _progress = results.length);
    }

    setState(() {
      _results = results;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Render benchmark'),
        actions: [
          if (!_running)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Run again',
              onPressed: _run,
            ),
        ],
      ),
      body: _running ? _buildLoading() : _buildResults(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF64FFDA)),
          const SizedBox(height: 24),
          Text(
            'Running scenario $_progress / ${_scenarios.length}…',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '$_kWarmup warmup + $_kRuns measured iterations each',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final results = _results;
    if (results == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryBanner(results: results),
        const SizedBox(height: 16),
        for (final r in results) ...[
          _ScenarioCard(result: r),
          const SizedBox(height: 16),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '$_kWarmup warmup + $_kRuns measured iterations · avg ms/frame\n'
            'dart:ui: headless Skia/Impeller (CPU path)\n'
            'Blend2D: CPU software rasterizer via native FFI',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary banner
// ---------------------------------------------------------------------------

class _SummaryBanner extends StatelessWidget {
  final List<_ScenarioResult> results;

  const _SummaryBanner({required this.results});

  @override
  Widget build(BuildContext context) {
    final b2dWins = results.where((r) => r.blend2dWins).length;
    final duiWins = results.where((r) => r.dartUiWins).length;
    final ties = results.length - b2dWins - duiWins;

    final avgRatio =
        results.fold(0.0, (s, r) => s + r.ratio) / results.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A4E)),
      ),
      child: Column(
        children: [
          const Text(
            'OVERALL',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatPill(
                  label: 'Blend2D wins',
                  value: '$b2dWins',
                  color: const Color(0xFF2E7D32)),
              _StatPill(
                  label: 'dart:ui wins',
                  value: '$duiWins',
                  color: const Color(0xFF1565C0)),
              if (ties > 0)
                _StatPill(label: 'Ties', value: '$ties', color: Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            avgRatio >= 1
                ? 'Blend2D is on average ${avgRatio.toStringAsFixed(1)}× faster'
                : 'dart:ui is on average ${(1 / avgRatio).toStringAsFixed(1)}× faster',
            style: TextStyle(
              color: avgRatio >= 1
                  ? const Color(0xFF69F0AE)
                  : const Color(0xFF82B1FF),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scenario card
// ---------------------------------------------------------------------------

class _ScenarioCard extends StatelessWidget {
  final _ScenarioResult result;

  const _ScenarioCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A4E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    result.def.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: result.winnerColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: result.winnerColor.withAlpha(120)),
                  ),
                  child: Text(
                    result.winnerLabel,
                    style: TextStyle(
                        color: result.winnerColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Image comparison
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: _RendererPanel(
                    label: 'Blend2D',
                    sublabel: 'native FFI',
                    png: result.blend2dPng,
                    ms: result.blend2dMs,
                    isWinner: result.blend2dWins,
                    accentColor: const Color(0xFF69F0AE),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RendererPanel(
                    label: 'dart:ui',
                    sublabel: 'Skia / Impeller',
                    png: result.dartUiPng,
                    ms: result.dartUiMs,
                    isWinner: result.dartUiWins,
                    accentColor: const Color(0xFF82B1FF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RendererPanel extends StatelessWidget {
  final String label;
  final String sublabel;
  final Uint8List png;
  final double ms;
  final bool isWinner;
  final Color accentColor;

  const _RendererPanel({
    required this.label,
    required this.sublabel,
    required this.png,
    required this.ms,
    required this.isWinner,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Label row
        Row(
          children: [
            Text(label,
                style: TextStyle(
                    color: accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Text(sublabel,
                style:
                    const TextStyle(color: Colors.white38, fontSize: 11)),
            if (isWinner) ...[
              const SizedBox(width: 4),
              const Text('★',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 12)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Image
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            png,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
        const SizedBox(height: 6),
        // Timing chip
        Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isWinner
                      ? accentColor.withAlpha(180)
                      : const Color(0xFF2A2A4E)),
            ),
            child: Text(
              '${ms.toStringAsFixed(2)} ms',
              style: TextStyle(
                color: isWinner ? accentColor : Colors.white54,
                fontSize: 13,
                fontWeight:
                    isWinner ? FontWeight.w700 : FontWeight.normal,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
