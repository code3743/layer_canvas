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
  /// The grouped layers, in the same insertion-order/[Layer.zIndex]
  /// stacking rules a [Scene]'s own layer list follows.
  final List<Layer> children;

  /// Creates a group of [children].
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

  @override
  Map<String, Object?> toJson() => {
    ...commonJson(),
    'properties': {
      'children': [for (final child in children) child.toJson()],
    },
  };

  /// Reconstructs a [Group] from [toJson]'s output. [decodeChild] resolves
  /// each entry in `'children'` — pass `LayerRegistry.decodeLayer` (the
  /// default every built-in decoder uses) unless you've built your own
  /// registry.
  factory Group.fromJson(
    Map<String, Object?> json, {
    required Layer Function(Map<String, Object?>) decodeChild,
  }) {
    final common = parseCommonLayerJson(json);
    final properties = json['properties'] as Map<String, Object?>;
    final childrenJson = properties['children'] as List<Object?>;
    return Group(
      id: common.id,
      transform: common.transform,
      size: common.size,
      opacity: common.opacity,
      zIndex: common.zIndex,
      visible: common.visible,
      children: [
        for (final childJson in childrenJson)
          decodeChild(childJson as Map<String, Object?>),
      ],
    );
  }
}
