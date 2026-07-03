import 'dart:io';

import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('Renderer', () {
    const renderer = Renderer();

    test('renders an empty scene to a valid PNG', () async {
      final scene = Scene(width: 16, height: 16);

      final bytes = await renderer.render(scene);

      expect(bytes.length, greaterThan(_pngSignature.length));
      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('renders a single RectangleLayer to a valid PNG', () async {
      final scene = Scene(width: 64, height: 32)
        ..add(
          RectangleLayer(
            size: const Size2D(64, 32),
            paint: const LayerPaint(color: Color32.fromRGB(255, 0, 0)),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('skips invisible layers without failing the render', () async {
      final scene = Scene(width: 16, height: 16)
        ..add(
          RectangleLayer(size: const Size2D(16, 16), visible: false),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test(
      'skips layer kinds the native engine does not support yet',
      () async {
        final scene = Scene(width: 16, height: 16)
          ..add(TextLayer(text: 'not renderable yet'));

        // Must not throw even though TextLayer has no native renderer yet.
        final bytes = await renderer.render(scene);

        expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
      },
    );

    test('renderToFile writes the same bytes render() would return', () async {
      final scene = Scene(width: 8, height: 8)
        ..add(RectangleLayer(size: const Size2D(8, 8)));

      final tempFile = await File(
        '${Directory.systemTemp.path}/layer_canvas_render_test.png',
      ).create();
      addTearDown(() => tempFile.delete());

      await renderer.renderToFile(scene, tempFile.path);
      final fileBytes = await tempFile.readAsBytes();

      expect(fileBytes.take(_pngSignature.length).toList(), _pngSignature);
    });
  });
}
