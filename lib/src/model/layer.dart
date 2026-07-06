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

  /// Creates a layer. Subclasses forward these as `super` parameters.
  Layer({
    String? id,
    this.transform = const LayerTransform(),
    this.size,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.visible = true,
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
}
