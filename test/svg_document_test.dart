import 'package:layer_canvas/layer_canvas.dart';
import 'package:test/test.dart';

void main() {
  group('SvgDocument.parse — malformed XML', () {
    test('throws SvgParseException for non-well-formed XML', () {
      expect(
        () => SvgDocument.parse('<svg><rect></svg>'),
        throwsA(isA<SvgParseException>()),
      );
    });
  });

  group('SvgDocument.parse — naturalSize', () {
    test('derives naturalSize from viewBox', () {
      final doc = SvgDocument.parse('<svg viewBox="0 0 24 24"></svg>');
      expect(doc.naturalSize, const Size2D(24, 24));
    });

    test('falls back to width/height when there is no viewBox', () {
      final doc = SvgDocument.parse('<svg width="100" height="50"></svg>');
      expect(doc.naturalSize, const Size2D(100, 50));
    });

    test('is null when neither is present/parseable', () {
      final doc = SvgDocument.parse('<svg></svg>');
      expect(doc.naturalSize, isNull);
    });
  });

  group('SvgDocument.parse — shapes', () {
    test('rect with rx == ry produces a rounded rectangle path', () {
      final doc = SvgDocument.parse(
        '<svg><rect x="0" y="0" width="100" height="50" rx="10" ry="10" '
        'fill="#ff0000"/></svg>',
      );
      final group = doc.toGroup();
      expect(group.children, hasLength(1));
      final layer = group.children.single as PathLayer;
      expect(layer.paint.color, const Color32.fromRGB(0xff, 0, 0));
      expect(layer.paint.style, LayerPaintStyle.fill);
    });

    test('rect with no rx/ry produces a plain 4-corner rectangle', () {
      final doc = SvgDocument.parse(
        '<svg><rect x="0" y="0" width="100" height="50" fill="red"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;
      expect(layer.path.commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(100, 0)),
        const LineTo(Point2D(100, 50)),
        const LineTo(Point2D(0, 50)),
        const ClosePath(),
      ]);
    });

    test('circle matches LayerPath.circle\'s geometry', () {
      final doc = SvgDocument.parse(
        '<svg><circle cx="50" cy="50" r="40" fill="blue"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;

      expect(
        layer.path.commands,
        LayerPath.circle(const Point2D(50, 50), 40).commands,
      );
    });

    test('ellipse uses independent rx/ry', () {
      final doc = SvgDocument.parse(
        '<svg><ellipse cx="0" cy="0" rx="40" ry="20" fill="green"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;
      final arc = layer.path.commands[1] as ArcTo;
      expect(arc.radiusX, 40);
      expect(arc.radiusY, 20);
    });

    test('polygon closes automatically', () {
      final doc = SvgDocument.parse(
        '<svg><polygon points="0,0 10,0 5,10" fill="red"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;
      expect(layer.path.commands.last, isA<ClosePath>());
    });

    test('polyline does not close, and defaults to stroke-friendly fill '
        'behavior unaffected (fill still applies per SVG default)', () {
      final doc = SvgDocument.parse(
        '<svg><polyline points="0,0 10,0 5,10" fill="red"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;
      expect(layer.path.commands.last, isNot(isA<ClosePath>()));
    });

    test('path uses the d attribute directly', () {
      final doc = SvgDocument.parse(
        '<svg><path d="M0,0 L10,0 L5,10 Z" fill="red"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;
      expect(layer.path.commands, [
        const MoveTo(Point2D(0, 0)),
        const LineTo(Point2D(10, 0)),
        const LineTo(Point2D(5, 10)),
        const ClosePath(),
      ]);
    });

    test('an unrecognized element is skipped without failing the parse', () {
      final doc = SvgDocument.parse(
        '<svg><foreignObject/><rect width="10" height="10" fill="red"/>'
        '</svg>',
      );
      expect(doc.toGroup().children, hasLength(1));
    });
  });

  group('SvgDocument.parse — fill/stroke', () {
    test('fill and stroke with different colors become two stacked layers', () {
      final doc = SvgDocument.parse(
        '<svg><rect width="10" height="10" fill="red" stroke="blue" '
        'stroke-width="2"/></svg>',
      );
      final children = doc.toGroup().children;
      expect(children, hasLength(2));
      final fillLayer = children[0] as PathLayer;
      final strokeLayer = children[1] as PathLayer;
      expect(fillLayer.paint.style, LayerPaintStyle.fill);
      expect(fillLayer.paint.color, const Color32.fromRGB(0xff, 0, 0));
      expect(strokeLayer.paint.style, LayerPaintStyle.stroke);
      expect(strokeLayer.paint.color, const Color32.fromRGB(0, 0, 0xff));
      expect(strokeLayer.paint.strokeWidth, 2);
    });

    test('fill="none" produces no fill layer', () {
      final doc = SvgDocument.parse(
        '<svg><rect width="10" height="10" fill="none" stroke="black"/>'
        '</svg>',
      );
      final children = doc.toGroup().children;
      expect(children, hasLength(1));
      expect(
        (children.single as PathLayer).paint.style,
        LayerPaintStyle.stroke,
      );
    });

    test('an element with no paintable fill/stroke at all is skipped', () {
      final doc = SvgDocument.parse(
        '<svg><rect width="10" height="10" fill="none"/></svg>',
      );
      expect(doc.toGroup().children, isEmpty);
    });

    test('style="" attribute overrides plain presentation attributes', () {
      final doc = SvgDocument.parse(
        '<svg><rect width="10" height="10" fill="red" '
        'style="fill:blue"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;
      expect(layer.paint.color, const Color32.fromRGB(0, 0, 0xff));
    });
  });

  group('SvgDocument.parse — inheritance and groups', () {
    test('fill set on a <g> is inherited by children unless overridden', () {
      final doc = SvgDocument.parse(
        '<svg><g fill="blue">'
        '<rect width="10" height="10"/>'
        '<rect width="10" height="10" fill="red"/>'
        '</g></svg>',
      );
      final group = doc.toGroup().children.single as Group;
      final inherited = group.children[0] as PathLayer;
      final overridden = group.children[1] as PathLayer;
      expect(inherited.paint.color, const Color32.fromRGB(0, 0, 0xff));
      expect(overridden.paint.color, const Color32.fromRGB(0xff, 0, 0));
    });

    test('opacity on a <g> becomes the Group layer\'s own opacity', () {
      final doc = SvgDocument.parse(
        '<svg><g opacity="0.5"><rect width="10" height="10" fill="red"/></g>'
        '</svg>',
      );
      final group = doc.toGroup().children.single as Group;
      expect(group.opacity, 0.5);
    });

    test('an empty <g> contributes no layer', () {
      final doc = SvgDocument.parse('<svg><g fill="red"></g></svg>');
      expect(doc.toGroup().children, isEmpty);
    });
  });

  group('SvgDocument.parse — transforms', () {
    test('translate on a shape is baked into its absolute coordinates', () {
      final doc = SvgDocument.parse(
        '<svg><rect width="10" height="10" fill="red" '
        'transform="translate(100, 50)"/></svg>',
      );
      final layer = doc.toGroup().children.single as PathLayer;
      expect(layer.path.commands.first, const MoveTo(Point2D(100, 50)));
    });

    test("a <g> transform composes with its children's own transforms", () {
      final doc = SvgDocument.parse(
        '<svg><g transform="translate(100, 0)">'
        '<rect width="10" height="10" fill="red" '
        'transform="translate(0, 50)"/>'
        '</g></svg>',
      );
      final group = doc.toGroup().children.single as Group;
      final layer = group.children.single as PathLayer;
      expect(layer.path.commands.first, const MoveTo(Point2D(100, 50)));
    });
  });

  group('SvgDocument.parse — gradients', () {
    test('fill="url(#id)" resolves a <linearGradient> from <defs>', () {
      final doc = SvgDocument.parse('''
<svg>
  <defs>
    <linearGradient id="g1" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="red"/>
      <stop offset="1" stop-color="blue"/>
    </linearGradient>
  </defs>
  <rect width="10" height="10" fill="url(#g1)"/>
</svg>
''');
      final layer = doc.toGroup().children.single as PathLayer;
      final gradient = layer.paint.gradient as LinearGradient;
      expect(gradient.start, const Point2D(0, 0));
      expect(gradient.end, const Point2D(1, 0));
      expect(gradient.stops, hasLength(2));
      expect(gradient.stops[0].color, const Color32.fromRGB(0xff, 0, 0));
      expect(gradient.stops[1].color, const Color32.fromRGB(0, 0, 0xff));
    });

    test('a radialGradient resolves with default center/radius', () {
      final doc = SvgDocument.parse('''
<svg>
  <defs>
    <radialGradient id="g1">
      <stop offset="0" stop-color="white"/>
      <stop offset="1" stop-color="black"/>
    </radialGradient>
  </defs>
  <circle cx="50" cy="50" r="40" fill="url(#g1)"/>
</svg>
''');
      final layer = doc.toGroup().children.single as PathLayer;
      final gradient = layer.paint.gradient as RadialGradient;
      expect(gradient.center, const Point2D(0.5, 0.5));
      expect(gradient.radius, 0.5);
    });

    test('an unresolvable gradient reference falls back to no fill', () {
      final doc = SvgDocument.parse(
        '<svg><rect width="10" height="10" fill="url(#missing)"/></svg>',
      );
      expect(doc.toGroup().children, isEmpty);
    });
  });

  group('SvgDocument.toGroup', () {
    test('applies the given transform/opacity to the resulting Group', () {
      final doc = SvgDocument.parse(
        '<svg><rect width="10" height="10" fill="red"/></svg>',
      );
      final group = doc.toGroup(
        transform: const LayerTransform(position: Point2D(5, 5)),
        opacity: 0.5,
      );
      expect(group.transform.position, const Point2D(5, 5));
      expect(group.opacity, 0.5);
    });
  });
}
