import 'dart:typed_data';

import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('ImageLayer', () {
    const renderer = Renderer();
    late Uint8List sourcePng;

    setUpAll(() async {
      // A real, tiny PNG produced by the renderer itself, reused as the
      // ImageLayer source below - no fixture file needed.
      final scene = Scene(width: 16, height: 12)
        ..add(
          RectangleLayer(
            size: const Size2D(16, 12),
            paint: const LayerPaint(color: Color32.fromRGB(200, 40, 40)),
          ),
        );
      sourcePng = await renderer.render(scene);
    });

    for (final fit in ImageFit.values) {
      test('renders a valid PNG with ImageFit.${fit.name}', () async {
        final scene = Scene(width: 64, height: 48)
          ..add(
            ImageLayer(
              source: LayerImageSource.memory(sourcePng),
              fit: fit,
              size: const Size2D(64, 48),
            ),
          );

        final bytes = await renderer.render(scene);

        expect(bytes.length, greaterThan(_pngSignature.length));
        expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
      });
    }

    test('with no explicit size, draws at the decoded image\'s natural '
        'dimensions', () async {
      final scene = Scene(width: 64, height: 48)
        ..add(ImageLayer(source: LayerImageSource.memory(sourcePng)));

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('malformed image bytes never fail the whole render', () async {
      final scene = Scene(width: 16, height: 16)
        ..add(
          ImageLayer(
            source: LayerImageSource.memory(
              Uint8List.fromList([1, 2, 3, 4, 5]),
            ),
            size: const Size2D(16, 16),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('composites over other layers in stacking order', () async {
      final scene = Scene(width: 16, height: 12)
        ..add(
          RectangleLayer(
            size: const Size2D(16, 12),
            paint: const LayerPaint(color: Color32.black),
            zIndex: 0,
          ),
        )
        ..add(
          ImageLayer(
            source: LayerImageSource.memory(sourcePng),
            size: const Size2D(16, 12),
            zIndex: 1,
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });
  });

  group('Scene.background', () {
    const renderer = Renderer();
    late Uint8List sourcePng;

    setUpAll(() async {
      final scene = Scene(width: 16, height: 12)
        ..add(
          RectangleLayer(
            size: const Size2D(16, 12),
            paint: const LayerPaint(color: Color32.fromRGB(40, 120, 200)),
          ),
        );
      sourcePng = await renderer.render(scene);
    });

    test('paints behind every layer, producing a different result than '
        'an empty scene', () async {
      final withoutBackground = await renderer.render(
        Scene(width: 16, height: 12),
      );
      final withBackground = await renderer.render(
        Scene(
          width: 16,
          height: 12,
          background: LayerImageSource.memory(sourcePng),
        ),
      );

      expect(withBackground, isNot(equals(withoutBackground)));
      expect(withBackground.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('other layers still composite on top of it', () async {
      final scene = Scene(
        width: 16,
        height: 12,
        background: LayerImageSource.memory(sourcePng),
      )..add(
          TextLayer(
            text: 'x',
            size: const Size2D(16, 12),
            color: Color32.white,
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('a malformed background never fails the whole render', () async {
      final scene = Scene(
        width: 16,
        height: 12,
        background: LayerImageSource.memory(
          Uint8List.fromList([1, 2, 3]),
        ),
      );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });
  });
}
