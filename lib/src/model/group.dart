import 'layer.dart';

/// A composite [Layer] that groups other layers so they can share a single
/// [Layer.transform] and [Layer.opacity], and be reordered together.
///
/// The native engine never sees a [Group] — before a [Scene] crosses the
/// FFI boundary, the renderer recursively expands every group into its
/// concrete descendants, composing the group's transform/opacity into each
/// one (see `scene_flattener.dart`). `scene_desc.h` and the Blend2D backend
/// need no changes to support grouping, and Groups can be nested
/// arbitrarily.
class Group extends Layer {
  final List<Layer> children;

  Group({
    required this.children,
    super.id,
    super.transform,
    super.size,
    super.opacity,
    super.zIndex,
    super.visible,
  });

  @override
  String get type => 'group';

  @override
  Map<String, Object?> get properties => {'children': children};
}
