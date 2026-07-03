import 'dart:math' as math;

import '../model/group.dart';
import '../model/geometry.dart';
import '../model/layer.dart';
import '../model/transform.dart';

/// A concrete (non-[Group]) layer whose [transform] and [opacity] have
/// already been composed with every ancestor [Group]'s transform/opacity.
///
/// [transform] is always in canonical form — `anchor` is `(0, 0)`, with any
/// original anchor (of this layer or of an ancestor group) already folded
/// into `position` — because a flattened layer's transform must round-trip
/// through the native wire format (`LcLayerDesc`), which composites every
/// layer independently and has no notion of nesting.
class ResolvedLayer {
  final Layer source;
  final LayerTransform transform;
  final double opacity;

  const ResolvedLayer(this.source, this.transform, this.opacity);
}

/// Expands every [Group] in [layers] (recursively) into a flat list of
/// concrete layers in final compositing order, ready to hand to
/// `fillNativeLayerDesc` one by one.
///
/// This is what lets [Group] add zero surface area to the native engine:
/// `scene_desc.h` and the Blend2D backend never see a group, only the
/// leaf layers it resolves to. At each nesting level, invisible layers are
/// dropped and the rest are stable-sorted by `zIndex` before recursing, so
/// a group's whole subtree stays contiguous in stacking order at the point
/// its own `zIndex` places it among its siblings — it isn't merged into one
/// global sort across every depth.
///
/// Composition is exact for translation and opacity in every case, and for
/// rotation and scale in every case except one: a non-uniform `scale` (x
/// and y differ) on a [Group] combined with a rotated descendant introduces
/// shear that `LayerTransform` (rotation + scale, no skew) cannot represent
/// exactly. That combination is approximated by composing rotation and
/// scale independently (angles add, scale factors multiply per-axis) —
/// exact whenever a group's scale is uniform or a descendant isn't rotated,
/// which covers every common use of grouping (moving/rotating/fading a
/// cluster of layers together).
List<ResolvedLayer> flattenScene(List<Layer> layers) {
  return _flatten(layers, const LayerTransform(), 1.0);
}

List<ResolvedLayer> _flatten(
  List<Layer> layers,
  LayerTransform parentTransform,
  double parentOpacity,
) {
  final visible = layers.where((layer) => layer.visible).toList()
    ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

  final result = <ResolvedLayer>[];
  for (final layer in visible) {
    final ownTransform = _reduceAnchor(
      layer.transform,
      layer.size ?? Size2D.zero,
    );
    final worldTransform = _compose(parentTransform, ownTransform);
    final worldOpacity = parentOpacity * layer.opacity;

    if (layer is Group) {
      result.addAll(_flatten(layer.children, worldTransform, worldOpacity));
    } else {
      result.add(ResolvedLayer(layer, worldTransform, worldOpacity));
    }
  }
  return result;
}

/// Rewrites [transform] so its pivot is the local origin instead of
/// `anchor * size`, folding the anchor offset into `position`. Any
/// transform `T(pos) · T(a) · R · S · T(-a)` (translate, pivot to anchor,
/// rotate, scale, pivot back) equals `T(pos + a - R·S·a) · R · S` — the
/// same rotation and scale, applied around the local origin instead of
/// `a`, with position adjusted to compensate.
LayerTransform _reduceAnchor(LayerTransform transform, Size2D size) {
  if (transform.anchor == Point2D.zero) {
    return LayerTransform(
      position: transform.position,
      rotation: transform.rotation,
      scale: transform.scale,
      anchor: Point2D.zero,
    );
  }

  final anchorOffset = Point2D(
    transform.anchor.x * size.width,
    transform.anchor.y * size.height,
  );
  final rotatedScaledAnchor = _rotateThenScale(
    anchorOffset,
    transform.rotation,
    transform.scale,
  );
  return LayerTransform(
    position: transform.position + anchorOffset - rotatedScaledAnchor,
    rotation: transform.rotation,
    scale: transform.scale,
    anchor: Point2D.zero,
  );
}

/// Composes an already-canonical (anchor at local origin) [parent]
/// transform with an already-canonical [child] transform, returning the
/// child's transform in world space — see [flattenScene] for the exact
/// semantics (and its one documented approximation).
LayerTransform _compose(LayerTransform parent, LayerTransform child) {
  final childPositionInParentSpace = _rotateThenScale(
    child.position,
    parent.rotation,
    parent.scale,
  );
  return LayerTransform(
    position: parent.position + childPositionInParentSpace,
    rotation: parent.rotation + child.rotation,
    scale: Point2D(
      parent.scale.x * child.scale.x,
      parent.scale.y * child.scale.y,
    ),
    anchor: Point2D.zero,
  );
}

/// Scales [point] by [scale] (per-axis) and then rotates it by [rotation]
/// (clockwise radians, matching [LayerTransform.rotation]) — i.e. applies
/// `R · S` to [point].
Point2D _rotateThenScale(Point2D point, double rotation, Point2D scale) {
  final scaled = Point2D(point.x * scale.x, point.y * scale.y);
  if (rotation == 0) return scaled;

  final cosR = math.cos(rotation);
  final sinR = math.sin(rotation);
  return Point2D(
    scaled.x * cosR - scaled.y * sinR,
    scaled.x * sinR + scaled.y * cosR,
  );
}
