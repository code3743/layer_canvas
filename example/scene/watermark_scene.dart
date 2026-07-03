import 'package:layer_canvas/layer_canvas.dart';

import '../data/mock_location.dart';

/// Builds a complete watermarked photo as a single [Scene] sized
/// [width]x[height]: [background] (the photo) painted first, then the
/// translucent card and its three lines of text on top.
///
/// Everything here — the photo, the card, and all the text — renders in one
/// native Blend2D pass. There is no Flutter involved anywhere in this file,
/// or anywhere in this example: `Scene`, `Renderer`, and every layer type
/// run in plain Dart.
Scene buildWatermarkScene(
  MockLocation location, {
  required int width,
  required int height,
  required LayerImageSource background,
}) {
  final scene = Scene(width: width, height: height, background: background);

  const panelMargin = 16.0;
  const panelHeight = 132.0;
  final panelTop = height - panelMargin - panelHeight;
  final panelWidth = width - panelMargin * 2;

  // A gradient scrim rather than a flat translucent fill - fades from
  // lighter at the top edge to darker at the bottom, keeping the text
  // readable over busy photo backgrounds without hiding as much of the
  // photo through the panel's upper half.
  scene.add(
    RectangleLayer(
      transform: LayerTransform(position: Point2D(panelMargin, panelTop)),
      size: Size2D(panelWidth, panelHeight),
      paint: const LayerPaint(
        gradient: LinearGradient(
          start: Point2D(0, 0),
          end: Point2D(0, 1),
          stops: [
            GradientStop(0, Color32(0x552B2B2B)),
            GradientStop(1, Color32(0xE62B2B2B)),
          ],
        ),
      ),
      cornerRadius: 18,
    ),
  );

  final textLeft = panelMargin + 16;
  final textWidth = panelWidth - 32;

  scene.add(
    TextLayer(
      text: location.placeName,
      transform: LayerTransform(position: Point2D(textLeft, panelTop + 16)),
      size: Size2D(textWidth, 26),
      fontSize: 19,
      color: Color32.white,
      fontWeight: TextWeight.bold,
    ),
  );

  scene.add(
    TextLayer(
      text: location.coordinatesLabel,
      transform: LayerTransform(position: Point2D(textLeft, panelTop + 50)),
      size: Size2D(textWidth, 22),
      fontSize: 15,
      color: const Color32.fromRGB(245, 245, 245),
    ),
  );

  scene.add(
    TextLayer(
      text: location.timestampLabel,
      transform: LayerTransform(position: Point2D(textLeft, panelTop + 78)),
      size: Size2D(textWidth, 20),
      fontSize: 13,
      color: const Color32.fromRGB(220, 220, 220),
    ),
  );

  // Corner tag — a visible reminder that the card above is a native render,
  // not a stack of Flutter Positioned/Text widgets (there is no Flutter
  // here at all).
  scene.add(
    TextLayer(
      text: 'layer_canvas',
      transform: LayerTransform(position: Point2D(width - 116, 14)),
      size: const Size2D(100, 18),
      fontSize: 12,
      color: const Color32.fromARGB(160, 255, 255, 255),
      align: TextAlignment.right,
    ),
  );

  return scene;
}
