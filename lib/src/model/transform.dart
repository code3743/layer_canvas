import 'geometry.dart';

/// Common 2D transform applied to a layer before it is composited.
///
/// [anchor] is expressed in fractional coordinates of the layer's own size
/// (0,0 = top-left, 0.5,0.5 = center, 1,1 = bottom-right) and defines the
/// pivot used by [rotation] and [scale].
class LayerTransform {
  final Point2D position;
  final double rotation; // radians
  final Point2D scale;
  final Point2D anchor;

  const LayerTransform({
    this.position = Point2D.zero,
    this.rotation = 0,
    this.scale = Point2D.one,
    this.anchor = const Point2D(0.5, 0.5),
  });

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
