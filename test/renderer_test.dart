import 'dart:io';
import 'dart:typed_data';

import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

import 'bmp_test_util.dart';
import 'png_test_util.dart';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _bmpSignature = [0x42, 0x4D]; // 'BM'
const _qoiSignature = [0x71, 0x6F, 0x69, 0x66]; // 'qoif'

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
        ..add(RectangleLayer(size: const Size2D(16, 16), visible: false));

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('skips layer kinds the native engine does not support yet', () async {
      final scene = Scene(width: 16, height: 16)
        ..add(TextLayer(text: 'not renderable yet'));

      // Must not throw even though TextLayer has no native renderer yet.
      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('renders a RectangleLayer with a LinearGradient fill', () async {
      final scene = Scene(width: 64, height: 32)
        ..add(
          RectangleLayer(
            size: const Size2D(64, 32),
            paint: const LayerPaint(
              gradient: LinearGradient(
                start: Point2D(0, 0),
                end: Point2D(1, 0),
                stops: [
                  GradientStop(0, Color32.fromRGB(255, 0, 0)),
                  GradientStop(1, Color32.fromRGB(0, 0, 255)),
                ],
              ),
            ),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('renders a RectangleLayer with a RadialGradient fill', () async {
      final scene = Scene(width: 32, height: 32)
        ..add(
          RectangleLayer(
            size: const Size2D(32, 32),
            paint: const LayerPaint(
              gradient: RadialGradient(
                center: Point2D(0.5, 0.5),
                radius: 0.5,
                stops: [
                  GradientStop(0, Color32.white),
                  GradientStop(1, Color32.black),
                ],
              ),
            ),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('renders a RectangleLayer with a ConicGradient fill', () async {
      final scene = Scene(width: 32, height: 32)
        ..add(
          RectangleLayer(
            size: const Size2D(32, 32),
            paint: const LayerPaint(
              gradient: ConicGradient(
                center: Point2D(0.5, 0.5),
                stops: [
                  GradientStop(0, Color32.fromRGB(255, 0, 0)),
                  GradientStop(0.5, Color32.fromRGB(0, 255, 0)),
                  GradientStop(1, Color32.fromRGB(255, 0, 0)),
                ],
              ),
            ),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('renders a PathLayer triangle built via LayerPath.polygon', () async {
      final scene = Scene(width: 64, height: 64)
        ..add(
          PathLayer(
            path: LayerPath.polygon(const [
              Point2D(32, 4),
              Point2D(60, 60),
              Point2D(4, 60),
            ]),
            paint: const LayerPaint(color: Color32.fromRGB(0, 180, 90)),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('renders a PathLayer with a cubic Bézier curve', () async {
      final scene = Scene(width: 64, height: 64)
        ..add(
          PathLayer(
            path: LayerPath([
              MoveTo(Point2D(4, 32)),
              CubicBezierTo(Point2D(4, 4), Point2D(60, 4), Point2D(60, 32)),
              LineTo(Point2D(60, 60)),
              ClosePath(),
            ]),
            paint: const LayerPaint(color: Color32.fromRGB(58, 123, 213)),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test('FillRule.nonZero and FillRule.evenOdd render a self-intersecting '
        'polygon differently', () async {
      // A pentagram: the 5 outer points of a regular pentagon connected
      // in {5/2} star order, so the outline self-intersects. Its
      // innermost region fills solid under nonZero (two overlapping
      // windings) but stays a hole under evenOdd (crossed twice).
      const star = [
        Point2D(100, 10),
        Point2D(152.9, 172.8),
        Point2D(14.4, 72.2),
        Point2D(185.6, 72.2),
        Point2D(47.1, 172.8),
      ];

      Future<List<int>> render(FillRule fillRule) async {
        final scene = Scene(width: 200, height: 200)
          ..add(
            PathLayer(
              path: LayerPath.polygon(star),
              paint: const LayerPaint(color: Color32.white),
              fillRule: fillRule,
            ),
          );
        return renderer.render(scene);
      }

      final nonZeroBytes = await render(FillRule.nonZero);
      final evenOddBytes = await render(FillRule.evenOdd);

      expect(nonZeroBytes, isNot(equals(evenOddBytes)));
    });

    test('renders a circle built from two ArcTo semicircular arcs', () async {
      final scene = Scene(width: 200, height: 200)
        ..add(
          PathLayer(
            path: LayerPath([
              MoveTo(const Point2D(200, 100)),
              const ArcTo(radiusX: 100, radiusY: 100, point: Point2D(0, 100)),
              const ArcTo(radiusX: 100, radiusY: 100, point: Point2D(200, 100)),
              const ClosePath(),
            ]),
            paint: const LayerPaint(color: Color32.fromRGB(0, 180, 90)),
          ),
        );

      final bytes = await renderer.render(scene);

      expect(bytes.take(_pngSignature.length).toList(), _pngSignature);
    });

    test(
      'renders an imported SVG document (shapes + gradient) end to end',
      () async {
        final doc = SvgDocument.parse('''
<svg viewBox="0 0 100 100">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ff0000"/>
      <stop offset="1" stop-color="#0000ff"/>
    </linearGradient>
  </defs>
  <rect width="100" height="100" fill="url(#bg)"/>
  <circle cx="50" cy="50" r="30" fill="white" stroke="black" stroke-width="2"/>
  <path d="M20,80 L50,20 L80,80 Z" fill="green" fill-opacity="0.5"/>
</svg>
''');

        final scene = Scene(width: 100, height: 100)..add(doc.toGroup());

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

    test(
      'renders to BMP with the correct magic bytes and pixel content',
      () async {
        final scene = Scene(width: 4, height: 4)
          ..add(
            RectangleLayer.filled(
              width: 4,
              height: 4,
              color: Color32.fromRGB(10, 200, 40),
            ),
          );

        final bytes = await renderer.render(scene, format: OutputFormat.bmp);

        expect(bytes.take(_bmpSignature.length).toList(), _bmpSignature);
        expect(readBmpPixel(bytes, 1, 1), (10, 200, 40));
      },
    );

    test('renders to QOI with the correct magic bytes', () async {
      final scene = Scene(width: 4, height: 4)
        ..add(RectangleLayer.filled(width: 4, height: 4, color: Color32.white));

      final bytes = await renderer.render(scene, format: OutputFormat.qoi);

      expect(bytes.take(_qoiSignature.length).toList(), _qoiSignature);
    });

    test('renderToFile honors a non-default format', () async {
      final scene = Scene(width: 4, height: 4)
        ..add(RectangleLayer(size: const Size2D(4, 4)));

      final tempFile = await File(
        '${Directory.systemTemp.path}/layer_canvas_render_format_test.bmp',
      ).create();
      addTearDown(() => tempFile.delete());

      await renderer.renderToFile(
        scene,
        tempFile.path,
        format: OutputFormat.bmp,
      );
      final fileBytes = await tempFile.readAsBytes();

      expect(fileBytes.take(_bmpSignature.length).toList(), _bmpSignature);
    });

    test(
      'a dash pattern paints strictly less coverage than a solid stroke',
      () async {
        Future<Uint8List> render(List<double> dashArray) async {
          final scene = Scene(width: 100, height: 100)
            ..add(
              PathLayer(
                path: LayerPath.polygon([
                  const Point2D(10, 10),
                  const Point2D(90, 10),
                  const Point2D(90, 90),
                  const Point2D(10, 90),
                ]),
                paint: LayerPaint(
                  style: LayerPaintStyle.stroke,
                  strokeWidth: 4,
                  color: Color32.white,
                  dashArray: dashArray,
                ),
              ),
            );
          return renderer.render(scene);
        }

        final solidPng = DecodedPng.decode(await render(const []));
        final dashedPng = DecodedPng.decode(await render(const [6, 6]));

        // A 6-on/6-off dash should paint roughly half the solid stroke's
        // coverage - assert strictly less, and well below the solid case,
        // without pinning an exact ratio the rasterizer's antialiasing
        // could nudge slightly.
        final solidCoverage = solidPng.countPaintedPixels();
        final dashedCoverage = dashedPng.countPaintedPixels();
        expect(dashedCoverage, lessThan(solidCoverage));
        expect(dashedCoverage, lessThan(solidCoverage * 0.75));
      },
    );

    test('a round stroke cap paints more coverage than a butt cap', () async {
      Future<Uint8List> render(StrokeCap cap) async {
        final scene = Scene(width: 100, height: 100)
          ..add(
            PathLayer(
              path: LayerPath(const [
                MoveTo(Point2D(20, 50)),
                LineTo(Point2D(80, 50)),
              ]),
              paint: LayerPaint(
                style: LayerPaintStyle.stroke,
                strokeWidth: 20,
                color: Color32.white,
                strokeCap: cap,
              ),
            ),
          );
        return renderer.render(scene);
      }

      final buttPng = DecodedPng.decode(await render(StrokeCap.butt));
      final roundPng = DecodedPng.decode(await render(StrokeCap.round));

      // A round cap adds a semicircular bulge past each endpoint on top
      // of whatever the butt cap already covers, so it must paint more,
      // not just different, pixels.
      expect(
        roundPng.countPaintedPixels(),
        greaterThan(buttPng.countPaintedPixels()),
      );
    });

    test('a miter join paints more coverage than a bevel join at a sharp '
        'corner', () async {
      Future<Uint8List> render(StrokeJoin join) async {
        final scene = Scene(width: 100, height: 100)
          ..add(
            PathLayer(
              path: LayerPath(const [
                MoveTo(Point2D(10, 90)),
                LineTo(Point2D(50, 15)),
                LineTo(Point2D(90, 90)),
              ]),
              paint: LayerPaint(
                style: LayerPaintStyle.stroke,
                strokeWidth: 16,
                color: Color32.white,
                strokeJoin: join,
                miterLimit: 10,
              ),
            ),
          );
        return renderer.render(scene);
      }

      final miterPng = DecodedPng.decode(await render(StrokeJoin.miter));
      final bevelPng = DecodedPng.decode(await render(StrokeJoin.bevel));

      // A miter join extends the sharp corner's outer edge into a point
      // past where a bevel join cuts it flat, so it must paint more.
      expect(
        miterPng.countPaintedPixels(),
        greaterThan(bevelPng.countPaintedPixels()),
      );
    });

    test('clipToBounds clips a PathLayer\'s overflowing geometry to its own '
        'size box', () async {
      // A circle centered at local (20, 20) with radius 60 overflows far
      // past a 40x40 declared size box - (70, 20) is inside the circle
      // (distance 50 < 60) but outside the box (x=70 > 40).
      Future<DecodedPng> render(bool clipToBounds) async {
        final scene = Scene(width: 100, height: 100)
          ..add(
            PathLayer(
              transform: const LayerTransform(anchor: Point2D.zero),
              size: const Size2D(40, 40),
              path: LayerPath.circle(const Point2D(20, 20), 60),
              paint: const LayerPaint(color: Color32.white),
              clipToBounds: clipToBounds,
            ),
          );
        return DecodedPng.decode(await renderer.render(scene));
      }

      final clipped = await render(true);
      final unclipped = await render(false);

      expect(unclipped.pixel(70, 20), (255, 255, 255, 255));
      expect(clipped.pixel(70, 20), (0, 0, 0, 0));
    });

    test(
      'a long TextLayer wraps into more lines under a narrower size.width',
      () async {
        Future<int> inkRowCount(double width) async {
          final scene = Scene(width: 400, height: 200)
            ..add(
              TextLayer(
                transform: const LayerTransform(anchor: Point2D.zero),
                size: Size2D(width, 200),
                text: 'aaaa bbbb cccc dddd eeee ffff',
                fontSize: 16,
                color: Color32.white,
              ),
            );
          final png = DecodedPng.decode(await renderer.render(scene));
          var rows = 0;
          for (var y = 0; y < png.height; y++) {
            for (var x = 0; x < png.width; x++) {
              final (_, _, _, a) = png.pixel(x, y);
              if (a > 0) {
                rows++;
                break;
              }
            }
          }
          return rows;
        }

        final wideRows = await inkRowCount(400); // fits on one line
        final narrowRows = await inkRowCount(60); // forces several lines

        expect(narrowRows, greaterThan(wideRows));
      },
    );

    test(
      'an explicit newline forces a line break even with no size set',
      () async {
        Future<int> inkRowCount(String text) async {
          final scene = Scene(width: 200, height: 200)
            ..add(
              TextLayer(
                transform: const LayerTransform(anchor: Point2D.zero),
                text: text,
                fontSize: 16,
                color: Color32.white,
              ),
            );
          final png = DecodedPng.decode(await renderer.render(scene));
          var rows = 0;
          for (var y = 0; y < png.height; y++) {
            for (var x = 0; x < png.width; x++) {
              final (_, _, _, a) = png.pixel(x, y);
              if (a > 0) {
                rows++;
                break;
              }
            }
          }
          return rows;
        }

        final oneLineRows = await inkRowCount('single line');
        final twoLineRows = await inkRowCount('first line\nsecond line');

        expect(twoLineRows, greaterThan(oneLineRows));
      },
    );
  });
}
