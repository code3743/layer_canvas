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
  bool operator ==(Object other) =>
      other is LayerTransform &&
      other.position == position &&
      other.rotation == rotation &&
      other.scale == scale &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(position, rotation, scale, anchor);

  @override
  String toString() =>
      'LayerTransform(position: $position, '
      'rotation: $rotation, scale: $scale, anchor: $anchor)';

  /// Converts to a JSON-safe map, see `Scene.toJson`.
  Map<String, Object?> toJson() => {
    'position': position.toJson(),
    'rotation': rotation,
    'scale': scale.toJson(),
    'anchor': anchor.toJson(),
  };

  /// Reconstructs a [LayerTransform] from [toJson]'s output.
  factory LayerTransform.fromJson(Map<String, Object?> json) => LayerTransform(
    position: Point2D.fromJson(json['position'] as Map<String, Object?>),
    rotation: (json['rotation'] as num).toDouble(),
    scale: Point2D.fromJson(json['scale'] as Map<String, Object?>),
    anchor: Point2D.fromJson(json['anchor'] as Map<String, Object?>),
  );
}
