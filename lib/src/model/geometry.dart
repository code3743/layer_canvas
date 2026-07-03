/// A 2D point or vector in the [Scene]'s logical pixel space.
///
/// Used for [LayerTransform.position], [LayerTransform.scale], and
/// [LayerTransform.anchor].
class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  static const zero = Point2D(0, 0);
  static const one = Point2D(1, 1);

  Point2D operator +(Point2D other) => Point2D(x + other.x, y + other.y);
  Point2D operator -(Point2D other) => Point2D(x - other.x, y - other.y);
  Point2D operator *(double factor) => Point2D(x * factor, y * factor);

  @override
  bool operator ==(Object other) =>
      other is Point2D && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2D($x, $y)';
}

/// A 2D size in the [Scene]'s logical pixel space.
///
/// Used for [Layer.size] and scene canvas dimensions.
class Size2D {
  final double width;
  final double height;

  const Size2D(this.width, this.height);

  static const zero = Size2D(0, 0);

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is Size2D && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size2D($width x $height)';
}
