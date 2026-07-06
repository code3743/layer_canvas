import 'geometry.dart';

/// Common 2D transform applied to a layer before it is composited.
///
/// [anchor] is expressed in fractional coordinates of the layer's own size
/// (0,0 = top-left, 0.5,0.5 = center, 1,1 = bottom-right) and defines the
/// pivot used by [rotation] and [scale].
class LayerTransform {
  /// Offset from the layer's untransformed position, in the [Scene]'s
  /// logical pixel space.
  final Point2D position;

  /// Rotation around [anchor], in radians.
  final double rotation; // radians

  /// Scale factor around [anchor] on each axis (`1.0` = no scaling).
  final Point2D scale;

  /// Pivot for [rotation] and [scale], fractional relative to the layer's
  /// own size.
  final Point2D anchor;

  /// Creates a transform. Defaults to no offset/rotation/scaling, pivoting
  /// around the layer's center.
  const LayerTransform({
    this.position = Point2D.zero,
    this.rotation = 0,
    this.scale = Point2D.one,
    this.anchor = const Point2D(0.5, 0.5),
  });

  /// Returns a copy with the given fields replaced.
  LayerTransform copyWith({
    Point2D? position,
    double? rotation,
    Point2D? scale,
    Point2D? anchor,
  }) {
    return LayerTransform(
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      anchor: anchor ?? this.anchor,
    );
  }

  @override
  String toString() =>
      'LayerTransform(position: $position, '
      'rotation: $rotation, scale: $scale, anchor: $anchor)';
}
