import 'package:flutter/material.dart' hide Paint;

import 'package:layer_canvas/layer_canvas.dart';

void main() {
  runApp(const MyApp());
}

/// Builds a [Scene] purely from the model API, to prove it is importable
/// and usable from a Flutter app. There is no renderer yet (that's a later
/// stage) — this only exercises construction of the object graph.
Scene _buildSampleScene() {
  final scene = Scene(width: 1080, height: 1920)
    ..background = const ImageSource.file('/tmp/background.png');

  scene.add(
    RectangleLayer(
      size: const Size2D(1080, 200),
      paint: const Paint(color: Color32.black),
      zIndex: 0,
    ),
  );

  scene.add(
    TextLayer(
      text: 'layer_canvas',
      fontSize: 48,
      color: Color32.white,
      align: TextAlignment.center,
      fontWeight: TextWeight.bold,
      transform: const LayerTransform(position: Point2D(0, 60)),
      zIndex: 1,
    ),
  );

  scene.add(
    Group(
      children: [
        ImageLayer(
          source: const ImageSource.file('/tmp/logo.png'),
          fit: ImageFit.contain,
          size: const Size2D(120, 120),
        ),
      ],
      transform: const LayerTransform(position: Point2D(24, 24)),
      zIndex: 2,
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

  @override
  void initState() {
    super.initState();
    scene = _buildSampleScene();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('layer_canvas')),
        body: SingleChildScrollView(
          child: Container(
            padding: const .all(10),
            child: Column(
              children: [
                Text(
                  'Scene model (no renderer yet): $scene',
                  style: textStyle,
                  textAlign: .center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
