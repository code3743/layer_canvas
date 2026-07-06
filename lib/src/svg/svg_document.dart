import 'package:xml/xml.dart';

import '../model/color.dart';
import '../model/geometry.dart';
import '../model/gradient.dart';
import '../model/group.dart';
import '../model/layer.dart';
import '../model/layers/path_layer.dart';
import '../model/paint.dart';
import '../model/path.dart';
import '../model/transform.dart';
import 'svg_color.dart';
import 'svg_path_data.dart';
import 'svg_transform.dart';

/// Thrown by [SvgDocument.parse] when its `source` isn't well-formed XML.
///
/// Malformed or unsupported *SVG* content within an otherwise well-formed
/// document — an unknown element, a bad number, an unresolvable gradient
/// reference — is never fatal: it's skipped element by element, the same
/// "don't fail the whole render over one bad value" philosophy the rest of
/// this package follows.
class SvgParseException implements Exception {
  /// Description of what went wrong.
  final String message;

  /// Creates an exception with the given [message].
  SvgParseException(this.message);

  @override
  String toString() => 'SvgParseException: $message';
}

/// A parsed SVG document, ready to be composited into a [Scene] via
/// [toGroup].
///
/// Parses a static subset of SVG 1.1 into this package's existing layer
/// types (`PathLayer`, `Group`) — see the package README's "SVG import"
/// section for exactly what's supported. There is no dedicated `SvgLayer`
/// type: an imported document is just a `Group` like any other, produced
/// once by [parse] rather than re-parsed on every render.
class SvgDocument {
  /// The document's natural size, derived from its `viewBox` (preferred)
  /// or `width`/`height` attributes. `null` if neither was present or
  /// parseable. Scale the result yourself via [toGroup]'s `transform`
  /// (e.g. `LayerTransform(scale: Point2D(target.width / naturalSize.width,
  /// ...))`) — there is no separate `fit` parameter, matching how every
  /// other layer kind in this package is scaled.
  final Size2D? naturalSize;

  final List<Layer> _children;

  SvgDocument._(this.naturalSize, this._children);

  /// Parses [source] (SVG document text) into an [SvgDocument].
  ///
  /// Throws [SvgParseException] if [source] isn't well-formed XML.
  static SvgDocument parse(String source) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlException catch (e) {
      throw SvgParseException(e.message);
    }

    final root = document.rootElement;
    final naturalSize = _parseNaturalSize(root);
    final gradients = _collectGradients(root);
    final children = _parseChildren(
      root,
      _rootMatrix(root),
      _SvgStyle.initial,
      gradients,
    );

    return SvgDocument._(naturalSize, children);
  }

  /// Composes the parsed document into a [Group], ready to `scene.add(...)`.
  Group toGroup({
    String? id,
    LayerTransform transform = const LayerTransform(),
    Size2D? size,
    double opacity = 1.0,
    int zIndex = 0,
    bool visible = true,
  }) {
    return Group(
      children: _children,
      id: id,
      transform: transform,
      size: size,
      opacity: opacity,
      zIndex: zIndex,
      visible: visible,
    );
  }
}

// ---------------------------------------------------------------------------
// Document-level parsing: natural size, root coordinate offset, gradients.
// ---------------------------------------------------------------------------

List<double>? _parseViewBox(XmlElement root) {
  final viewBox = root.getAttribute('viewBox');
  if (viewBox == null) return null;
  final parts = viewBox
      .trim()
      .split(RegExp(r'[,\s]+'))
      .map(double.tryParse)
      .toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return null;
  return parts.cast<double>();
}

Size2D? _parseNaturalSize(XmlElement root) {
  final viewBox = _parseViewBox(root);
  if (viewBox != null) return Size2D(viewBox[2], viewBox[3]);

  final width = _parseLength(root.getAttribute('width'));
  final height = _parseLength(root.getAttribute('height'));
  if (width != null && height != null) return Size2D(width, height);
  return null;
}

/// A non-zero `viewBox` origin (`minX`/`minY`) shifts every coordinate in
/// the document — baked in as the initial accumulated matrix, same as any
/// other transform.
SvgMatrix _rootMatrix(XmlElement root) {
  final viewBox = _parseViewBox(root);
  if (viewBox == null) return SvgMatrix.identity;
  final minX = viewBox[0], minY = viewBox[1];
  if (minX == 0 && minY == 0) return SvgMatrix.identity;
  return SvgMatrix.translate(-minX, -minY);
}

Map<String, Gradient> _collectGradients(XmlElement root) {
  final result = <String, Gradient>{};
  for (final element in root.descendantElements) {
    final id = element.getAttribute('id');
    if (id == null) continue;
    switch (element.localName) {
      case 'linearGradient':
        final gradient = _parseLinearGradient(element);
        if (gradient != null) result[id] = gradient;
      case 'radialGradient':
        final gradient = _parseRadialGradient(element);
        if (gradient != null) result[id] = gradient;
    }
  }
  return result;
}

Gradient? _parseLinearGradient(XmlElement element) {
  final stops = _parseStops(element);
  if (stops.isEmpty) return null;
  return LinearGradient(
    start: Point2D(
      _parseFraction(element.getAttribute('x1')) ?? 0.0,
      _parseFraction(element.getAttribute('y1')) ?? 0.0,
    ),
    end: Point2D(
      _parseFraction(element.getAttribute('x2')) ?? 1.0,
      _parseFraction(element.getAttribute('y2')) ?? 0.0,
    ),
    stops: stops,
    extendMode: _parseSpreadMethod(element.getAttribute('spreadMethod')),
  );
}

Gradient? _parseRadialGradient(XmlElement element) {
  final stops = _parseStops(element);
  if (stops.isEmpty) return null;
  return RadialGradient(
    center: Point2D(
      _parseFraction(element.getAttribute('cx')) ?? 0.5,
      _parseFraction(element.getAttribute('cy')) ?? 0.5,
    ),
    radius: _parseFraction(element.getAttribute('r')) ?? 0.5,
    stops: stops,
    extendMode: _parseSpreadMethod(element.getAttribute('spreadMethod')),
  );
}

GradientExtendMode _parseSpreadMethod(String? value) => switch (value) {
  'repeat' => GradientExtendMode.repeat,
  'reflect' => GradientExtendMode.reflect,
  _ => GradientExtendMode.pad,
};

List<GradientStop> _parseStops(XmlElement gradientElement) {
  final stops = <GradientStop>[];
  for (final stop in gradientElement.childElements) {
    if (stop.localName != 'stop') continue;
    final offset = (_parseFraction(stop.getAttribute('offset')) ?? 0.0).clamp(
      0.0,
      1.0,
    );
    final attrs = _effectiveAttributes(stop, const [
      'stop-color',
      'stop-opacity',
    ]);
    final color =
        parseSvgColor(attrs['stop-color'] ?? '#000000') ?? Color32.black;
    final opacity = _parseOpacity(attrs['stop-opacity']) ?? 1.0;
    stops.add(GradientStop(offset, color.withOpacity(color.opacity * opacity)));
  }
  return stops;
}

// ---------------------------------------------------------------------------
// Inherited presentation style (fill/stroke/opacity/fill-rule).
// ---------------------------------------------------------------------------

sealed class _SvgPaintRef {
  const _SvgPaintRef();
}

class _SvgPaintNone extends _SvgPaintRef {
  const _SvgPaintNone();
}

class _SvgPaintColor extends _SvgPaintRef {
  final Color32 color;
  const _SvgPaintColor(this.color);
}

class _SvgPaintUrl extends _SvgPaintRef {
  final String id;
  const _SvgPaintUrl(this.id);
}

class _SvgStyle {
  final _SvgPaintRef fill;
  final _SvgPaintRef stroke;
  final double strokeWidth;
  final double fillOpacity;
  final double strokeOpacity;
  final FillRule fillRule;

  const _SvgStyle({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.fillOpacity,
    required this.strokeOpacity,
    required this.fillRule,
  });

  // SVG's own initial/default property values.
  static const initial = _SvgStyle(
    fill: _SvgPaintColor(Color32.black),
    stroke: _SvgPaintNone(),
    strokeWidth: 1.0,
    fillOpacity: 1.0,
    strokeOpacity: 1.0,
    fillRule: FillRule.nonZero,
  );
}

const _inheritedStyleAttributeNames = [
  'fill',
  'stroke',
  'stroke-width',
  'fill-opacity',
  'stroke-opacity',
  'fill-rule',
];

/// Reads [names] off [element], then overlays any of the same names found
/// in a `style="..."` attribute — the `style` attribute wins, matching
/// real CSS specificity (presentation attributes lose to inline styles).
Map<String, String> _effectiveAttributes(
  XmlElement element,
  List<String> names,
) {
  final result = <String, String>{};
  for (final name in names) {
    final value = element.getAttribute(name);
    if (value != null) result[name] = value;
  }
  final style = element.getAttribute('style');
  if (style != null) {
    for (final declaration in style.split(';')) {
      final parts = declaration.split(':');
      if (parts.length != 2) continue;
      final key = parts[0].trim();
      final value = parts[1].trim();
      if (names.contains(key) && value.isNotEmpty) result[key] = value;
    }
  }
  return result;
}

_SvgStyle _resolveStyle(XmlElement element, _SvgStyle inherited) {
  final attrs = _effectiveAttributes(element, _inheritedStyleAttributeNames);

  final fill = attrs.containsKey('fill')
      ? _parsePaintRef(attrs['fill']!)
      : inherited.fill;
  final stroke = attrs.containsKey('stroke')
      ? _parsePaintRef(attrs['stroke']!)
      : inherited.stroke;
  final strokeWidth = attrs.containsKey('stroke-width')
      ? (_parseLength(attrs['stroke-width']) ?? inherited.strokeWidth)
      : inherited.strokeWidth;
  final fillOpacity = attrs.containsKey('fill-opacity')
      ? (_parseOpacity(attrs['fill-opacity']) ?? inherited.fillOpacity)
      : inherited.fillOpacity;
  final strokeOpacity = attrs.containsKey('stroke-opacity')
      ? (_parseOpacity(attrs['stroke-opacity']) ?? inherited.strokeOpacity)
      : inherited.strokeOpacity;
  final fillRule = switch (attrs['fill-rule']) {
    'evenodd' => FillRule.evenOdd,
    'nonzero' => FillRule.nonZero,
    _ => inherited.fillRule,
  };

  return _SvgStyle(
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    fillOpacity: fillOpacity,
    strokeOpacity: strokeOpacity,
    fillRule: fillRule,
  );
}

final _urlReferencePattern = RegExp(r'url\(\s*#([^)\s]+)\s*\)');

_SvgPaintRef _parsePaintRef(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('url(')) {
    final match = _urlReferencePattern.firstMatch(trimmed);
    return match == null
        ? const _SvgPaintNone()
        : _SvgPaintUrl(match.group(1)!);
  }
  final color = parseSvgColor(trimmed);
  return color == null ? const _SvgPaintNone() : _SvgPaintColor(color);
}

LayerPaint? _resolveFillPaint(
  _SvgStyle style,
  Map<String, Gradient> gradients,
) {
  switch (style.fill) {
    case _SvgPaintNone():
      return null;
    case _SvgPaintUrl(:final id):
      final gradient = gradients[id];
      return gradient == null
          ? null
          : LayerPaint(gradient: gradient, style: LayerPaintStyle.fill);
    case _SvgPaintColor(:final color):
      return LayerPaint(
        color: color.withOpacity(color.opacity * style.fillOpacity),
        style: LayerPaintStyle.fill,
      );
  }
}

LayerPaint? _resolveStrokePaint(
  _SvgStyle style,
  Map<String, Gradient> gradients,
) {
  if (style.strokeWidth <= 0) return null;
  switch (style.stroke) {
    case _SvgPaintNone():
      return null;
    case _SvgPaintUrl(:final id):
      final gradient = gradients[id];
      return gradient == null
          ? null
          : LayerPaint(
              gradient: gradient,
              style: LayerPaintStyle.stroke,
              strokeWidth: style.strokeWidth,
            );
    case _SvgPaintColor(:final color):
      return LayerPaint(
        color: color.withOpacity(color.opacity * style.strokeOpacity),
        style: LayerPaintStyle.stroke,
        strokeWidth: style.strokeWidth,
      );
  }
}

// ---------------------------------------------------------------------------
// Element tree walking.
// ---------------------------------------------------------------------------

const _nonRenderableElements = {
  'defs',
  'title',
  'desc',
  'metadata',
  'linearGradient',
  'radialGradient',
  'style',
  'symbol',
  'clipPath',
  'mask',
  'pattern',
};

List<Layer> _parseChildren(
  XmlElement parent,
  SvgMatrix matrix,
  _SvgStyle style,
  Map<String, Gradient> gradients,
) {
  final result = <Layer>[];
  for (final child in parent.childElements) {
    result.addAll(_parseElement(child, matrix, style, gradients));
  }
  return result;
}

List<Layer> _parseElement(
  XmlElement element,
  SvgMatrix matrix,
  _SvgStyle inheritedStyle,
  Map<String, Gradient> gradients,
) {
  final tag = element.localName;
  if (_nonRenderableElements.contains(tag)) return const [];

  final style = _resolveStyle(element, inheritedStyle);
  final transformAttr = element.getAttribute('transform');
  final ownMatrix = transformAttr == null
      ? matrix
      : matrix.multiply(parseSvgTransform(transformAttr));
  final opacity = _parseOpacity(element.getAttribute('opacity')) ?? 1.0;

  switch (tag) {
    case 'g':
    case 'svg': // A nested <svg> is treated like a plain group - its own
      // viewBox/clipping semantics aren't honored (MVP scope).
      final children = _parseChildren(element, ownMatrix, style, gradients);
      return children.isEmpty
          ? const []
          : [Group(children: children, opacity: opacity)];
    case 'rect':
      return _buildShapeLayers(
        _rectCommands(element),
        ownMatrix,
        style,
        gradients,
        opacity,
      );
    case 'circle':
      return _buildShapeLayers(
        _ellipseCommands(element, isCircle: true),
        ownMatrix,
        style,
        gradients,
        opacity,
      );
    case 'ellipse':
      return _buildShapeLayers(
        _ellipseCommands(element, isCircle: false),
        ownMatrix,
        style,
        gradients,
        opacity,
      );
    case 'line':
      return _buildShapeLayers(
        _lineCommands(element),
        ownMatrix,
        style,
        gradients,
        opacity,
      );
    case 'polyline':
      return _buildShapeLayers(
        _polyCommands(element, closed: false),
        ownMatrix,
        style,
        gradients,
        opacity,
      );
    case 'polygon':
      return _buildShapeLayers(
        _polyCommands(element, closed: true),
        ownMatrix,
        style,
        gradients,
        opacity,
      );
    case 'path':
      return _buildShapeLayers(
        _pathCommands(element),
        ownMatrix,
        style,
        gradients,
        opacity,
      );
    default:
      return const []; // Unrecognized element - skip, don't fail.
  }
}

/// Builds up to two [PathLayer]s (fill, then stroke, matching SVG's own
/// paint order) sharing the same transformed geometry — our `LayerPaint`
/// has one shared color/gradient for fill+stroke, but SVG allows
/// independent ones, so a shape with different fill and stroke paints
/// becomes two stacked layers instead of one `fillAndStroke` layer.
List<Layer> _buildShapeLayers(
  List<PathCommand>? localCommands,
  SvgMatrix matrix,
  _SvgStyle style,
  Map<String, Gradient> gradients,
  double opacity,
) {
  if (localCommands == null || localCommands.isEmpty) return const [];

  final fillPaint = _resolveFillPaint(style, gradients);
  final strokePaint = _resolveStrokePaint(style, gradients);
  if (fillPaint == null && strokePaint == null) return const [];

  final path = LayerPath(applySvgMatrix(localCommands, matrix));
  return [
    if (fillPaint != null)
      PathLayer(
        path: path,
        paint: fillPaint,
        fillRule: style.fillRule,
        opacity: opacity,
      ),
    if (strokePaint != null)
      PathLayer(path: path, paint: strokePaint, opacity: opacity),
  ];
}

// ---------------------------------------------------------------------------
// Per-element geometry, in local (untransformed) coordinates.
// ---------------------------------------------------------------------------

List<PathCommand>? _rectCommands(XmlElement element) {
  final x = _parseLength(element.getAttribute('x')) ?? 0;
  final y = _parseLength(element.getAttribute('y')) ?? 0;
  final width = _parseLength(element.getAttribute('width'));
  final height = _parseLength(element.getAttribute('height'));
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }

  double? rx = _parseLength(element.getAttribute('rx'));
  double? ry = _parseLength(element.getAttribute('ry'));
  rx ??= ry;
  ry ??= rx;
  rx = (rx ?? 0).clamp(0, width / 2);
  ry = (ry ?? 0).clamp(0, height / 2);

  if (rx <= 0 || ry <= 0) {
    return [
      MoveTo(Point2D(x, y)),
      LineTo(Point2D(x + width, y)),
      LineTo(Point2D(x + width, y + height)),
      LineTo(Point2D(x, y + height)),
      const ClosePath(),
    ];
  }

  return [
    MoveTo(Point2D(x + rx, y)),
    LineTo(Point2D(x + width - rx, y)),
    ArcTo(
      radiusX: rx,
      radiusY: ry,
      sweep: true,
      point: Point2D(x + width, y + ry),
    ),
    LineTo(Point2D(x + width, y + height - ry)),
    ArcTo(
      radiusX: rx,
      radiusY: ry,
      sweep: true,
      point: Point2D(x + width - rx, y + height),
    ),
    LineTo(Point2D(x + rx, y + height)),
    ArcTo(
      radiusX: rx,
      radiusY: ry,
      sweep: true,
      point: Point2D(x, y + height - ry),
    ),
    LineTo(Point2D(x, y + ry)),
    ArcTo(radiusX: rx, radiusY: ry, sweep: true, point: Point2D(x + rx, y)),
    const ClosePath(),
  ];
}

List<PathCommand>? _ellipseCommands(
  XmlElement element, {
  required bool isCircle,
}) {
  final cx = _parseLength(element.getAttribute('cx')) ?? 0;
  final cy = _parseLength(element.getAttribute('cy')) ?? 0;
  final r = isCircle ? _parseLength(element.getAttribute('r')) : null;
  final rx = isCircle ? r : _parseLength(element.getAttribute('rx'));
  final ry = isCircle ? r : _parseLength(element.getAttribute('ry'));
  if (rx == null || ry == null || rx <= 0 || ry <= 0) return null;

  return LayerPath.ellipse(Point2D(cx, cy), rx, ry).commands;
}

List<PathCommand> _lineCommands(XmlElement element) {
  final x1 = _parseLength(element.getAttribute('x1')) ?? 0;
  final y1 = _parseLength(element.getAttribute('y1')) ?? 0;
  final x2 = _parseLength(element.getAttribute('x2')) ?? 0;
  final y2 = _parseLength(element.getAttribute('y2')) ?? 0;
  return [MoveTo(Point2D(x1, y1)), LineTo(Point2D(x2, y2))];
}

List<PathCommand>? _polyCommands(XmlElement element, {required bool closed}) {
  final pointsAttr = element.getAttribute('points');
  if (pointsAttr == null) return null;

  final numbers = pointsAttr
      .trim()
      .split(RegExp(r'[,\s]+'))
      .where((s) => s.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (numbers.length < 4 ||
      numbers.length.isOdd ||
      numbers.any((n) => n == null)) {
    return null;
  }

  final points = <Point2D>[
    for (var i = 0; i < numbers.length; i += 2)
      Point2D(numbers[i]!, numbers[i + 1]!),
  ];
  final path = closed ? LayerPath.polygon(points) : LayerPath.polyline(points);
  return path.commands;
}

List<PathCommand>? _pathCommands(XmlElement element) {
  final d = element.getAttribute('d');
  if (d == null) return null;
  final commands = parseSvgPathData(d);
  return commands.isEmpty ? null : commands;
}

// ---------------------------------------------------------------------------
// Small shared value parsers.
// ---------------------------------------------------------------------------

const _lengthUnits = ['px', 'pt', 'pc', 'mm', 'cm', 'in', 'em', 'ex', '%'];

/// A plain SVG length. Percentage/unit suffixes are stripped and the
/// numeric part used as-is (user-space units) — this package doesn't
/// resolve percentages against the SVG viewport.
double? _parseLength(String? value) {
  if (value == null) return null;
  var s = value.trim();
  for (final unit in _lengthUnits) {
    if (s.endsWith(unit)) {
      s = s.substring(0, s.length - unit.length);
      break;
    }
  }
  return double.tryParse(s.trim());
}

/// A bare fraction (`0.5`) or percentage (`50%`) - used for gradient
/// coordinates in the default `objectBoundingBox` unit space.
double? _parseFraction(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.endsWith('%')) {
    final v = double.tryParse(trimmed.substring(0, trimmed.length - 1));
    return v == null ? null : v / 100;
  }
  return double.tryParse(trimmed);
}

double? _parseOpacity(String? value) {
  final v = _parseFraction(value);
  return v?.clamp(0.0, 1.0);
}
