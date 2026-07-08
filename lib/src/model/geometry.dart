/// A 2D point or vector in the [Scene]'s logical pixel space.
///
/// Used for [LayerTransform.position], [LayerTransform.scale], and
/// [LayerTransform.anchor].
class Point2D {
  /// The horizontal coordinate.
  final double x;

  /// The vertical coordinate.
  final double y;

  /// Creates a point at ([x], [y]).
  const Point2D(this.x, this.y);

  /// The origin, `(0, 0)`.
  static const zero = Point2D(0, 0);

  /// The unit point, `(1, 1)` — the identity value for [operator *] and for
  /// [LayerTransform.scale].
  static const one = Point2D(1, 1);

  /// Adds [other]'s coordinates to this point's.
  Point2D operator +(Point2D other) => Point2D(x + other.x, y + other.y);

  /// Subtracts [other]'s coordinates from this point's.
  Point2D operator -(Point2D other) => Point2D(x - other.x, y - other.y);

  /// Scales both coordinates by [factor].
  Point2D operator *(double factor) => Point2D(x * factor, y * factor);

  @override
  bool operator ==(Object other) =>
      other is Point2D && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2D($x, $y)';

  /// Converts to a JSON-safe map, see `Scene.toJson`.
  Map<String, Object?> toJson() => {'x': x, 'y': y};

  /// Reconstructs a [Point2D] from [toJson]'s output.
  factory Point2D.fromJson(Map<String, Object?> json) =>
      Point2D((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

/// A 2D size in the [Scene]'s logical pixel space.
///
/// Used for [Layer.size] and scene canvas dimensions.
class Size2D {
  /// The horizontal extent.
  final double width;

  /// The vertical extent.
  final double height;

  /// Creates a size of [width] by [height].
  const Size2D(this.width, this.height);

  /// The zero size, `0 x 0`.
  static const zero = Size2D(0, 0);

  /// Whether [width] or [height] is zero or negative.
  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is Size2D && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size2D($width x $height)';

  /// Converts to a JSON-safe map, see `Scene.toJson`.
  Map<String, Object?> toJson() => {'width': width, 'height': height};

  /// Reconstructs a [Size2D] from [toJson]'s output.
  factory Size2D.fromJson(Map<String, Object?> json) => Size2D(
    (json['width'] as num).toDouble(),
    (json['height'] as num).toDouble(),
  );
}
