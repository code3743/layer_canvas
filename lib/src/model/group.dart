import 'layer.dart';

/// A composite [Layer] that groups other layers so they can share a single
/// [Layer.transform] and [Layer.opacity], and be reordered together.
///
/// A [Group] composites exactly like any other layer from the engine's
/// point of view — its [type] is `'group'` and [properties] simply exposes
/// [children] — so grouping requires no special-casing in [Scene] or the
/// renderer core. Groups can be nested arbitrarily.
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
