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

    test('a registered font renders identically to the embedded default when '
        'given the exact same underlying font bytes', () async {
      final robotoRegularBytes = File(
        'third_party/fonts/roboto/Roboto-Regular.ttf',
      ).readAsBytesSync();
      FontRegistry.register('TestRoboto', robotoRegularBytes);
      addTearDown(() => FontRegistry.unregister('TestRoboto'));

      final customFontBytes = await renderer.render(buildScene('TestRoboto'));
      final defaultFontBytes = await renderer.render(buildScene(null));

      expect(customFontBytes, equals(defaultFontBytes));
    });

    test(
      'falls back to the embedded default for an unregistered fontFamily',
      () async {
        final bytes = await renderer.render(buildScene('NoSuchFont'));

        expect(bytes, equals(await renderer.render(buildScene(null))));
      },
    );

    test('register throws for data that is not a valid font', () {
      expect(
        () => FontRegistry.register('Bogus', Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FontRegistrationException>()),
      );
    });

    test('unregister is a no-op for a name that was never registered', () {
      expect(() => FontRegistry.unregister('NeverRegistered'), returnsNormally);
    });
  });

  group('FontRegistry (weights)', () {
    const renderer = Renderer();
    late Uint8List regularBytes;
    late Uint8List boldBytes;

    Scene buildScene({String? fontFamily, TextWeight? fontWeight}) =>
        Scene(width: 200, height: 60)..add(
          TextLayer(
            text: 'Hello 123',
            transform: const LayerTransform(position: Point2D(5, 5)),
            size: const Size2D(190, 40),
            fontSize: 20,
            fontFamily: fontFamily,
            fontWeight: fontWeight ?? TextWeight.normal,
          ),
        );

    setUpAll(() {
      regularBytes = File(
        'third_party/fonts/roboto/Roboto-Regular.ttf',
      ).readAsBytesSync();
      boldBytes = File(
        'third_party/fonts/roboto/Roboto-Bold.ttf',
      ).readAsBytesSync();
    });

    test(
      'resolves each registered weight to its own face, not the other one',
      () async {
        FontRegistry.register('TestFamily', regularBytes);
        FontRegistry.register('TestFamily', boldBytes, weight: TextWeight.bold);
        addTearDown(() {
          FontRegistry.unregister('TestFamily');
          FontRegistry.unregister('TestFamily', weight: TextWeight.bold);
        });

        final normalBytes = await renderer.render(
          buildScene(fontFamily: 'TestFamily', fontWeight: TextWeight.normal),
        );
        final boldFamilyBytes = await renderer.render(
          buildScene(fontFamily: 'TestFamily', fontWeight: TextWeight.bold),
        );

        expect(
          normalBytes,
          equals(
            await renderer.render(buildScene(fontWeight: TextWeight.normal)),
          ),
        );
        expect(
          boldFamilyBytes,
          equals(
            await renderer.render(buildScene(fontWeight: TextWeight.bold)),
          ),
        );
        expect(normalBytes, isNot(equals(boldFamilyBytes)));
      },
    );

    test('falls back to the numerically closest registered weight', () async {
      // Only 400 and 700 registered; a request for 600 is closer to 700
      // (distance 100) than to 400 (distance 200), so it should resolve
      // to the bold face.
      FontRegistry.register('TestFamily', regularBytes);
      FontRegistry.register('TestFamily', boldBytes, weight: TextWeight.bold);
      addTearDown(() {
        FontRegistry.unregister('TestFamily');
        FontRegistry.unregister('TestFamily', weight: TextWeight.bold);
      });

      final semiBoldBytes = await renderer.render(
        buildScene(
          fontFamily: 'TestFamily',
          fontWeight: TextWeight.semiBold, // 600
        ),
      );

      expect(
        semiBoldBytes,
        equals(await renderer.render(buildScene(fontWeight: TextWeight.bold))),
      );
    });

    test('unregistering one weight leaves the other weight of the same family '
        'resolvable, and requests for the removed weight fall back to '
        "whatever's left in that family rather than another family", () async {
      FontRegistry.register('TestFamily', regularBytes);
      FontRegistry.register('TestFamily', boldBytes, weight: TextWeight.bold);
      addTearDown(() => FontRegistry.unregister('TestFamily'));

      FontRegistry.unregister('TestFamily', weight: TextWeight.bold);

      final normalStillWorks = await renderer.render(
        buildScene(fontFamily: 'TestFamily', fontWeight: TextWeight.normal),
      );
      // Bold was removed, but 'TestFamily' still has a normal (400) face
      // registered, so it resolves to that rather than falling all the
      // way through to the embedded default.
      final boldNowResolvesToRemainingWeight = await renderer.render(
        buildScene(fontFamily: 'TestFamily', fontWeight: TextWeight.bold),
      );

      expect(
        normalStillWorks,
        equals(
          await renderer.render(buildScene(fontWeight: TextWeight.normal)),
        ),
      );
      expect(boldNowResolvesToRemainingWeight, equals(normalStillWorks));
    });

    test('unregistering every weight of a family falls back to the embedded '
        'default, same as a never-registered family', () async {
      FontRegistry.register('TestFamily', regularBytes);
      FontRegistry.register('TestFamily', boldBytes, weight: TextWeight.bold);

      FontRegistry.unregister('TestFamily');
      FontRegistry.unregister('TestFamily', weight: TextWeight.bold);

      final bytes = await renderer.render(
        buildScene(fontFamily: 'TestFamily', fontWeight: TextWeight.bold),
      );

      expect(
        bytes,
        equals(await renderer.render(buildScene(fontWeight: TextWeight.bold))),
      );
    });
  });
}
