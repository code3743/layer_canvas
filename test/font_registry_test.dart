import 'dart:io';
import 'dart:typed_data';

import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

void main() {
  group('FontRegistry', () {
    const renderer = Renderer();

    Scene buildScene(String? fontFamily) => Scene(width: 200, height: 60)
      ..add(
        TextLayer(
          text: 'Hello 123',
          transform: const LayerTransform(position: Point2D(5, 5)),
          size: const Size2D(190, 40),
          fontSize: 20,
          fontFamily: fontFamily,
        ),
      );

    test(
      'a registered font renders identically to the embedded default when '
      'given the exact same underlying font bytes',
      () async {
        final robotoRegularBytes = File(
          'third_party/fonts/roboto/Roboto-Regular.ttf',
        ).readAsBytesSync();
        FontRegistry.register('TestRoboto', robotoRegularBytes);
        addTearDown(() => FontRegistry.unregister('TestRoboto'));

        final customFontBytes = await renderer.render(
          buildScene('TestRoboto'),
        );
        final defaultFontBytes = await renderer.render(buildScene(null));

        expect(customFontBytes, equals(defaultFontBytes));
      },
    );

    test(
      'falls back to the embedded default for an unregistered fontFamily',
      () async {
        final bytes = await renderer.render(buildScene('NoSuchFont'));

        expect(bytes, equals(await renderer.render(buildScene(null))));
      },
    );

    test('register throws for data that is not a valid font', () {
      expect(
        () => FontRegistry.register(
          'Bogus',
          Uint8List.fromList([1, 2, 3, 4]),
        ),
        throwsA(isA<FontRegistrationException>()),
      );
    });

    test('unregister is a no-op for a name that was never registered', () {
      expect(() => FontRegistry.unregister('NeverRegistered'), returnsNormally);
    });
  });
}
