import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:layer_canvas/layer_canvas.dart';

void main() {
  runApp(const MyApp());
}

// ── Mock watermark definitions ────────────────────────────────────────────────
//
// These constants represent where watermark elements would be placed on a
// 400×300 canvas. In a real pipeline the native engine would composite them
// directly onto the image pixels; here Flutter widgets reproduce the visual.

const _imageUrl =
    'https://purina.com.co/sites/default/files/2022-10/Que_debes_saber_antes_de_adoptar_un_gatito.jpg';

// Rectangle watermark band (semi-transparent overlay at the bottom)
const _bandLeft = 0.0;
const _bandTop = 240.0;
const _bandWidth = 400.0;
const _bandHeight = 60.0;

// Text watermark "gatito"
const _textLeft = 12.0;
const _textTop = 256.0;

// Diagonal stamp "gatito" at the center
const _stampCenterX = 200.0;
const _stampCenterY = 150.0;
const _stampRotation = -0.4; // radians ≈ -23°

// ── Scene (native render — rectangles only for now) ───────────────────────────

Scene _buildScene() {
  // Native engine renders the rectangle band; text is overlaid by Flutter.
  final scene = Scene(width: 400, height: 300);

  scene.add(
    RectangleLayer(
      transform: const LayerTransform(position: Point2D(_bandLeft, _bandTop)),
      size: const Size2D(_bandWidth, _bandHeight),
      paint: const LayerPaint(color: Color32(0xCC000000)), // 80% black
    ),
  );

  scene.add(
    RectangleLayer(
      transform: LayerTransform(
        position: Point2D(_stampCenterX - 80, _stampCenterY - 20),
        rotation: _stampRotation,
      ),
      size: const Size2D(160, 40),
      paint: const LayerPaint(color: Color32(0x44FFFFFF)),
      cornerRadius: 6,
    ),
  );

  return scene;
}

// ── App ───────────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Marca de agua – gatito',
      debugShowCheckedModeBanner: false,
      home: WatermarkPage(),
    );
  }
}

class WatermarkPage extends StatefulWidget {
  const WatermarkPage({super.key});

  @override
  State<WatermarkPage> createState() => _WatermarkPageState();
}

class _WatermarkPageState extends State<WatermarkPage> {
  late final Future<Uint8List> _overlay;

  @override
  void initState() {
    super.initState();
    _overlay = Renderer().render(_buildScene());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marca de agua – gatito')),
      body: Center(
        child: FutureBuilder<Uint8List>(
          future: _overlay,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              );
            }
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }

            // Stack: base image + native overlay PNG + Flutter text labels
            return SizedBox(
              width: 400,
              height: 300,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Base image ──────────────────────────────────────────
                  Image.network(
                    _imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xFF222222),
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),

                  // ── Native overlay (rectangles rendered by Blend2D) ─────
                  Image.memory(snapshot.data!, fit: BoxFit.cover),

                  // ── Text watermarks (Flutter, coords match mock above) ──

                  // Bottom-band label
                  Positioned(
                    left: _textLeft,
                    top: _textTop,
                    child: const Text(
                      'gatito',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                  // Diagonal stamp
                  Positioned(
                    left: _stampCenterX - 60,
                    top: _stampCenterY - 14,
                    child: Transform.rotate(
                      angle: _stampRotation,
                      child: const Text(
                        'gatito',
                        style: TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),

                  // Corner micro-stamp
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: Text(
                      '© gatito',
                      style: TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
