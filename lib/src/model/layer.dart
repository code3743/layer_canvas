import 'geometry.dart';
import 'transform.dart';

int _nextLayerId = 0;

/// Base type for every element that can be composited onto a [Scene].
///
/// [Layer] only carries properties that are meaningful for *any* kind of
/// visual element (position/size/rotation/scale/opacity/stacking/
/// visibility, all via [transform], [size], [opacity], [zIndex] and
/// [visible]). Anything specific to one kind of content (an image, a run
/// of text, a rectangle...) lives on the concrete subclass and is exposed
/// through [properties] instead of new fields here.
///
/// This is what lets the renderer core composite a [Scene] knowing only
/// [type] and [properties] — never a concrete subclass — so new layer
/// kinds (`CircleLayer`, `SvgLayer`, `QrLayer`, even a user-defined
/// `CustomLayer`) can be added later purely by subclassing, with no change
/// to [Layer], [Scene] or the renderer.
abstract class Layer {
  /// Unique identifier, stable for the lifetime of this layer instance.
  final String id;

  /// Position/rotation/scale/anchor applied before this layer is composited.
  final LayerTransform transform;

  /// The layer's own size, in the [Scene]'s logical pixel space.
  ///
  /// `null` means "intrinsic": the backend derives it from content (e.g. an
  /// [ImageLayer] with no explicit size uses the source image's natural
  /// pixel dimensions; a [TextLayer] with no explicit size uses its laid
  /// out text bounds). Layers whose content has no natural size (e.g.
  /// [RectangleLayer]) require it explicitly.
  final Size2D? size;

  /// Opacity multiplier applied on top of the layer's own content, `0.0..1.0`.
  final double opacity;

  /// Stacking order among sibling layers — higher values paint on top.
  /// Layers with equal [zIndex] keep their relative insertion order.
  final int zIndex;

  /// Whether this layer is painted at all. An invisible layer is skipped
  /// entirely, as if it weren't in the [Scene].
  final bool visible;

  /// When `true`, this layer's own painted content is clipped to its own
  /// [size] box, in its own local space (i.e. after its own
  /// position/rotation/scale is applied — the clip rectangle moves and
  /// rotates with the layer exactly like its paint geometry does). Requires
  /// an explicit [size]; a layer with no size (intrinsic sizing) has
  /// nothing well-defined to clip to, and ends up fully clipped away (an
  /// empty box) — so leave this `false` on an intrinsically-sized layer.
  ///
  /// Has no effect on a [Group]: a group is expanded into its concrete
  /// descendants before reaching the native renderer (see
  /// `scene_flattener.dart`), so there's no single composited surface left
  /// to clip by the time rendering happens. Clipping an entire composed
  /// cluster of layers together isn't supported by this package today.
  final bool clipToBounds;

  /// Creates a layer. Subclasses forward these as `super` parameters.
  Layer({
    String? id,
    this.transform = const LayerTransform(),
    this.size,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.visible = true,
    this.clipToBounds = false,
  }) : assert(
         opacity >= 0.0 && opacity <= 1.0,
         'opacity must be between 0.0 and 1.0',
       ),
       id = id ?? 'layer-${_nextLayerId++}';

  /// Discriminator sent across the FFI boundary so the native backend knows
  /// how to interpret [properties]. Must be stable and unique per subclass.
  String get type;

  /// Content specific to this layer kind (e.g. text/color/image source),
  /// opaque to [Scene] and to the renderer core.
  Map<String, Object?> get properties;

  @override
  String toString() => '$runtimeType(id: $id, type: $type)';

  /// Converts to a JSON-safe map, see `Scene.toJson`.
  ///
  /// Unlike [properties] (raw Dart objects, used only internally to cross
  /// the FFI boundary), this must be JSON-safe end to end. A subclass
  /// implements this by spreading [commonJson]'s result alongside its own
  /// `'properties'` map (each value serialized with its own `toJson`, same
  /// shape [properties] exposes but JSON-safe) — see e.g.
  /// `RectangleLayer.toJson`. A custom `Layer` subclass that skips this
  /// override simply doesn't support [Scene.toJson]/[Scene.fromJson] — call
  /// [Scene.toJson] on layers of only built-in types, and it (or
  /// [LayerRegistry.registerLayer]) never fails render-side, since neither
  /// [Renderer] nor [properties] depend on this method at all.
  Map<String, Object?> toJson();

  /// The `id`/`transform`/`size`/`opacity`/`zIndex`/`visible`/`clipToBounds`/
  /// `type` fields every concrete [toJson] override shares — spread this
  /// map's result alongside a `'properties'` map of the subclass's own
  /// fields.
  Map<String, Object?> commonJson() => {
    'type': type,
    'id': id,
    'transform': transform.toJson(),
    'size': size?.toJson(),
    'opacity': opacity,
    'zIndex': zIndex,
    'visible': visible,
    'clipToBounds': clipToBounds,
  };
}

/// The common [Layer] fields ([commonJson]'s output) already parsed back
/// into their Dart types — every concrete `Layer.fromJson` destructures
/// this instead of repeating the same field lookups.
typedef CommonLayerFields = ({
  String id,
  LayerTransform transform,
  Size2D? size,
  double opacity,
  int zIndex,
  bool visible,
  bool clipToBounds,
});

/// Parses the fields [Layer.commonJson] adds, shared by every concrete
/// layer's `fromJson`.
CommonLayerFields parseCommonLayerJson(Map<String, Object?> json) {
  final sizeJson = json['size'] as Map<String, Object?>?;
  return (
    id: json['id'] as String,
    transform: LayerTransform.fromJson(
      json['transform'] as Map<String, Object?>,
    ),
    size: sizeJson == null ? null : Size2D.fromJson(sizeJson),
    opacity: (json['opacity'] as num).toDouble(),
    zIndex: json['zIndex'] as int,
    visible: json['visible'] as bool,
    clipToBounds: json['clipToBounds'] as bool? ?? false,
  );
}
