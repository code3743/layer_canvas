import 'package:layer_canvas/src/model/color.dart';
import 'package:layer_canvas/src/svg/svg_color.dart';
import 'package:test/test.dart';

void main() {
  group('parseSvgColor — special keywords', () {
    test('none returns null', () {
      expect(parseSvgColor('none'), isNull);
      expect(parseSvgColor('None'), isNull);
    });

    test('transparent returns a real, fully transparent color', () {
      expect(parseSvgColor('transparent'), Color32.transparent);
    });

    test('unrecognized value falls back to opaque black', () {
      expect(parseSvgColor('not-a-color'), Color32.black);
    });
  });

  group('parseSvgColor — hex', () {
    test('#rgb expands each digit', () {
      expect(parseSvgColor('#f00'), const Color32.fromRGB(0xff, 0, 0));
    });

    test('#rgba expands each digit including alpha', () {
      expect(parseSvgColor('#f008'), const Color32.fromARGB(0x88, 0xff, 0, 0));
    });

    test('#rrggbb', () {
      expect(parseSvgColor('#3a7bd5'), const Color32.fromRGB(0x3a, 0x7b, 0xd5));
    });

    test('#rrggbbaa', () {
      expect(
        parseSvgColor('#3a7bd580'),
        const Color32.fromARGB(0x80, 0x3a, 0x7b, 0xd5),
      );
    });
  });

  group('parseSvgColor — rgb()/rgba()', () {
    test('rgb() with integer components', () {
      expect(parseSvgColor('rgb(255, 0, 0)'), const Color32.fromRGB(255, 0, 0));
    });

    test('rgb() with space-separated components', () {
      expect(parseSvgColor('rgb(255 0 0)'), const Color32.fromRGB(255, 0, 0));
    });

    test('rgb() with percentage components', () {
      expect(
        parseSvgColor('rgb(100%, 0%, 0%)'),
        const Color32.fromRGB(255, 0, 0),
      );
    });

    test('rgba() with an alpha component', () {
      expect(
        parseSvgColor('rgba(255, 0, 0, 0.5)'),
        const Color32.fromARGB(128, 255, 0, 0),
      );
    });
  });

  group('parseSvgColor — named colors', () {
    test('resolves a common named color', () {
      expect(parseSvgColor('red'), const Color32.fromRGB(0xff, 0, 0));
      expect(
        parseSvgColor('CornflowerBlue'),
        const Color32.fromRGB(0x64, 0x95, 0xed),
      );
    });

    test('gray and grey spellings resolve to the same color', () {
      expect(parseSvgColor('gray'), parseSvgColor('grey'));
    });
  });
}
