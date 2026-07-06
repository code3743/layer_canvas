import 'dart:math' as math;

import '../model/geometry.dart';
import '../model/layer.dart';
import '../model/scene.dart';
import '../model/transform.dart';
import 'scene_flattener.dart';

/// Returns the topmost visible [Layer] in [scene] whose bounding box
/// contains [point] (both in the scene's own logical pixel space), or
/// `null` if none does.
///
/// "Topmost" follows the same stacking rule [Scene.layers] documents:
/// highest [Layer.zIndex] first, ties broken by insertion order (later
/// wins) — the same order [flattenScene] already resolves a scene into, so
/// this is a search through that list from the end. [Group] children are
/// tested in the group's own composed transform space: a rotated, scaled,
/// or offset group carries its children's hit boxes along exactly the way
/// it carries their paint geometry (see [flattenScene] for the one
/// documented approximation that composition involves).
///
/// This is a bounding-box test against [Layer.size], not the exact painted
/// shape — a circular [PathLayer] is hit-tested as its bounding square, for
/// instance. A layer with no explicit [Layer.size] (intrinsic sizing, e.g.
/// a [TextLayer]/[ImageLayer] left to size itself from its content) can
/// never match: its true rendered bounds are resolved by the native
/// backend and aren't available here. Give such layers an explicit `size`
/// if they need to participate in hit-testing.
Layer? hitTestScene(Scene scene, Point2D point) {
  final resolved = flattenScene(scene.layers);
  for (var i = resolved.length - 1; i >= 0; i--) {
    final candidate = resolved[i];
    final size = candidate.source.size;
    if (size == null) continue;
    if (_transformedRectContains(candidate.transform, size, point)) {
      return candidate.source;
    }
  }
  return null;
}

/// Whether [point] (in world space) falls inside the rectangle
/// `[0, size.width] x [0, size.height]` once [transform] (already in
/// canonical, anchor-at-origin form, as every [flattenScene] result is) is
/// applied to it — i.e. the inverse of the same `position + R·S·local`
/// mapping [flattenScene] uses to place a layer's local geometry in world
/// space.
bool _transformedRectContains(LayerTransform transform, Size2D size, Point2D point) {
  final dx = point.x - transform.position.x;
  final dy = point.y - transform.position.y;

  double localX;
  double localY;
  if (transform.rotation == 0) {
    localX = dx;
    localY = dy;
  } else {
    final cosR = math.cos(-transform.rotation);
    final sinR = math.sin(-transform.rotation);
    localX = dx * cosR - dy * sinR;
    localY = dx * sinR + dy * cosR;
  }

  if (transform.scale.x != 1) {
    if (transform.scale.x == 0) return false;
    localX /= transform.scale.x;
  }
  if (transform.scale.y != 1) {
    if (transform.scale.y == 0) return false;
    localY /= transform.scale.y;
  }

  return localX >= 0 && localX <= size.width && localY >= 0 && localY <= size.height;
}
