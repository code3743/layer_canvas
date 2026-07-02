import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart' hide Size;

import 'package:layer_canvas/layer_canvas.dart';
import 'package:layer_canvas/layer_canvas_bindings_generated.dart'
    as bindings;

// TEMPORARY diagnostic: bypasses Renderer/lc_render_scene entirely to test
// whether the simpler Stage-4 path (create/clear/encode_png, no per-layer
// transform loop) also hangs on this device.
Future<Uint8List> _diagnosticClearOnly() async {
  // ignore: avoid_print
  print('DEBUG: diagnostic - creating image');
  final image = bindings.lc_image_create(64, 64);
  // ignore: avoid_print
  print('DEBUG: diagnostic - clearing image');
  bindings.lc_image_clear(image, 0xFF3366CC);
  // ignore: avoid_print
  print('DEBUG: diagnostic - encoding png');
  final outData = calloc<Pointer<Uint8>>();
  final outLen = calloc<Size>();
  final status = bindings.lc_image_encode_png(image, outData, outLen);
  // ignore: avoid_print
  print('DEBUG: diagnostic - encode status=$status');
  final bytes = Uint8List.fromList(outData.value.asTypedList(outLen.value));
  bindings.lc_buffer_free(outData.value);
  bindings.lc_image_destroy(image);
  calloc.free(outData);
  calloc.free(outLen);
  return bytes;
}

void main() {
  runApp(const MyApp());
}

/// Builds a [Scene] exercising every RectangleLayer feature the native
/// engine currently supports: position, rotation, anchor-based pivoting,
/// scale, opacity, corner radius and fill/stroke paint styles.
///
/// ImageLayer/TextLayer/Group are later stages - the model already allows
/// constructing them, but the native renderer skips kinds it doesn't know
/// yet rather than failing, so they're left out of this sample scene for
/// now to keep it an honest preview of what actually renders today.
Scene _buildSampleScene() {
  final scene = Scene(width: 300, height: 200);

  scene.add(
    RectangleLayer(
      transform: const LayerTransform(position: Point2D(20, 20)),
      size: const Size2D(100, 60),
      paint: const LayerPaint(color: Color32.fromRGB(0, 90, 220)),
      cornerRadius: 16,
    ),
  );

  scene.add(
    RectangleLayer(
      transform: LayerTransform(
        position: const Point2D(200, 60),
        rotation: 30 * 3.1415926535 / 180,
      ),
      size: const Size2D(80, 50),
      paint: const LayerPaint(color: Color32.fromRGB(220, 30, 30)),
      opacity: 0.6,
    ),
  );

  scene.add(
    RectangleLayer(
      transform: const LayerTransform(
        position: Point2D(30, 120),
        scale: Point2D(1.5, 1.5),
        anchor: Point2D(0, 0),
      ),
      size: const Size2D(60, 40),
      paint: const LayerPaint(
        color: Color32.fromRGB(20, 160, 60),
        style: LayerPaintStyle.stroke,
        strokeWidth: 4,
      ),
    ),
  );

  return scene;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Scene scene;
  late Future<Uint8List> renderedPng;

  @override
  void initState() {
    super.initState();
    scene = _buildSampleScene();
    renderedPng = _diagnosticClearOnly();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 16);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('layer_canvas')),
        body: Center(
          child: Column(
            mainAxisAlignment: .center,
            children: [
              Text('$scene', style: textStyle, textAlign: .center),
              const SizedBox(height: 16),
              FutureBuilder<Uint8List>(
                future: renderedPng,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  return Image.memory(snapshot.data!);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
